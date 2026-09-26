#!/usr/bin/env bash
# Integration test: run only in an expendable Debian container after installing base.
set -Eeuo pipefail
repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
fixture_dir=$(mktemp -d)
trap 'rm -rf -- "$fixture_dir"' EXIT
ln -s "$repo_dir/tests/fixtures/ansible-fail" "$fixture_dir/ansible-playbook"
result=0
output=$(PATH="$fixture_dir:$PATH" "$repo_dir/bootstrap.sh" \
  --platform lxc --non-interactive --components base 2>&1) || result=$?
[[ $result -eq 42 ]]
[[ $output == *'Installation failed (Ansible exit 42)'* ]]
[[ $output != *'Bootstrap complete'* ]]
echo 'Ansible failures retain their exit status'
