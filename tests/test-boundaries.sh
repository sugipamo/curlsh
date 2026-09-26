#!/usr/bin/env bash
set -Eeuo pipefail
repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
fixture_dir=$(mktemp -d)
trap 'rm -rf -- "$fixture_dir"' EXIT
mkdir "$fixture_dir/bin" "$fixture_dir/gum-bin" "$fixture_dir/project"
cp -a "$repo_dir/bootstrap.sh" "$repo_dir/playbook.yml" "$repo_dir/vars" \
  "$repo_dir/lib" "$repo_dir/docs" "$fixture_dir/project/"
cp "$repo_dir/tests/fixtures/debian-diagnostics" "$fixture_dir/project/lib/diagnostics.sh"
# An isolated PATH prevents any test from falling through to a real mutating command.
for utility in bash dirname sed cat tr cut head uname awk df; do
  ln -s "$(command -v "$utility")" "$fixture_dir/bin/$utility"
done
for spy in apt-get apt dpkg-query dpkg timeout systemctl service ansible-playbook \
  curl gpg install git jq ssh gh tailscale codex docker node cc qemu-ga; do
  ln -s "$repo_dir/tests/fixtures/boundary-command" "$fixture_dir/bin/$spy"
done
ln -s "$repo_dir/tests/fixtures/boundary-command" "$fixture_dir/gum-bin/gum"
export CURLSH_TEST_REPO="$repo_dir" CURLSH_TEST_FIXTURE="$fixture_dir"
export CURLSH_TEST_MUTATIONS="$fixture_dir/unexpected" CURLSH_TEST_PROBES="$fixture_dir/probes"

output=$(PATH="$fixture_dir/bin" bash "$fixture_dir/project/bootstrap.sh" \
  --dry-run --platform vm --components base,codex,tailscale,docker,codex)
[[ $output == *'Execution plan (scope, not an exact diff'* ]]
[[ $output == *'Components: base,codex,tailscale,docker'* ]]
[[ $output == *'Observed package: python3-apt = not reported installed'* ]]
[[ $output == *'DOWNGRADED'* && $output == *'Pinned Codex version:'* ]]
[[ $output == *'Not determined: exact APT transaction'* ]]
[[ $output == *'Dry-run complete.'* ]]
[[ $(printf '%s\n' "$output" | grep -c '^## Shared repository prerequisites$') -eq 1 ]]
[[ ! -e $CURLSH_TEST_MUTATIONS && ! -e $CURLSH_TEST_PROBES ]]

all_output=$(PATH="$fixture_dir/bin" bash "$fixture_dir/project/bootstrap.sh" \
  --dry-run --platform vm --components base,github_cli,tailscale,codex,docker,nodejs,devtools,qemu_guest_agent)
for component in base github_cli tailscale codex docker nodejs devtools qemu_guest_agent; do
  [[ $all_output == *"## $component - "* ]]
done
[[ ! -e $CURLSH_TEST_MUTATIONS && ! -e $CURLSH_TEST_PROBES ]]

base_output=$(PATH="$fixture_dir/bin" bash "$fixture_dir/project/bootstrap.sh" \
  --dry-run --platform lxc --components base)
[[ $base_output != *'## Shared repository prerequisites'* ]]
[[ $base_output != *'Pinned Codex version:'* ]]
[[ ! -e $CURLSH_TEST_MUTATIONS && ! -e $CURLSH_TEST_PROBES ]]

# Missing documentation must stop before preflight or any installation, never silently omit scope.
mv "$fixture_dir/project/docs/changes/base.md" "$fixture_dir/base.saved"
if PATH="$fixture_dir/bin" bash "$fixture_dir/project/bootstrap.sh" \
  --dry-run --platform lxc --components base >"$fixture_dir/missing-output" 2>&1; then
  echo 'An incomplete specification should fail closed' >&2; exit 1
fi
grep -q 'Missing change specification: base' "$fixture_dir/missing-output"
mv "$fixture_dir/base.saved" "$fixture_dir/project/docs/changes/base.md"
[[ ! -e $CURLSH_TEST_MUTATIONS && ! -e $CURLSH_TEST_PROBES ]]

if ((EUID == 0)); then
  python3 "$repo_dir/tests/test-interactive.py"
else
  echo 'PTY install-boundary checks require root; CI runs them separately with sudo.'
fi
echo 'dry-run and approval boundary checks passed'
