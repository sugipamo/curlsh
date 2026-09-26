"""Check the narrow, mechanical part of documentation/recipe agreement.

Requires PyYAML (already a dependency of the CI Ansible environment).
Descriptions and upstream side effects still need human review.
"""

import re
import subprocess
from pathlib import Path

import yaml


repo = Path(__file__).resolve().parent.parent
spec_dir = repo / "docs/changes"
fields = ("Packages", "Sources", "Writes", "Services", "Conflicts", "Rerun", "Uncertain", "Does not run", "Implementation")
metadata = subprocess.check_output(
    ["bash", "-c", 'source "$1/lib/components.sh"; for id in "${component_ids[@]}"; do '
     'printf "%s\\t%s\\t%s\\n" "$id" "${component_packages[$id]}" "${component_services[$id]-}"; done',
     "spec-test", str(repo)], text=True,
)


def validate_document(name):
    path = spec_dir / f"{name}.md"
    content = path.read_text()
    for field in fields:
        assert f"\n{field}: " in content, (name, "missing field", field)
    for target in re.findall(r"\]\(([^)]+)\)", content):
        assert (path.parent / target).is_file(), (name, "broken implementation link", target)
    return content


def paragraph(content, field):
    return content.split(f"\n{field}: ", 1)[1].split("\n\n", 1)[0]


for line in metadata.splitlines():
    component, package_text, service = line.split("\t")
    content = validate_document(component)
    tasks = yaml.safe_load((repo / f"roles/{component}/tasks/main.yml").read_text())
    role_packages = set()
    role_services = set()
    for task in tasks:
        if "ansible.builtin.apt" in task:
            names = task["ansible.builtin.apt"]["name"]
            role_packages.update([names] if isinstance(names, str) else names)
        if "ansible.builtin.systemd_service" in task:
            role_services.add(task["ansible.builtin.systemd_service"]["name"])
    documented_packages = set(re.findall(r"`([^`]+)`", paragraph(content, "Packages")))
    documented_services = set(re.findall(r"`([^`]+)`", paragraph(content, "Services")))
    assert role_packages == set(package_text.split()) == documented_packages, (component, "package drift")
    assert role_services == ({service} if service else set()) == documented_services, (component, "service drift")
    assert f"../../roles/{component}/tasks/main.yml" in content
    dependency_file = repo / f"roles/{component}/meta/main.yml"
    has_shared_dependency = dependency_file.is_file()
    if dependency_file.is_file():
        dependencies = yaml.safe_load(dependency_file.read_text())["dependencies"]
        assert dependencies == [{"role": "repository_prerequisites"}]
        assert "Shared repository prerequisites also apply." in content
    plan = subprocess.check_output(
        ["bash", str(repo / "bootstrap.sh"), "--dry-run", "--platform", "vm", "--components", component],
        text=True,
    )
    assert content in plan, (component, "CLI explanation differs from published specification")
    assert ("## Shared repository prerequisites" in plan) == has_shared_dependency, (component, "plan dependency drift")

validate_document("runtime")
shared = validate_document("repository_prerequisites")
shared_tasks = yaml.safe_load((repo / "roles/repository_prerequisites/tasks/main.yml").read_text())
assert set(shared_tasks[0]["ansible.builtin.apt"]["name"]) == set(re.findall(r"`([^`]+)`", paragraph(shared, "Packages")))
print("change specifications match component packages, services and implementation links")
