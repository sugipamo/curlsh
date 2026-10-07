#!/usr/bin/env bash
# Checks arguments and config parsing. Nothing here changes the machine.
set -Eeuo pipefail

repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
install_sh=$repo_dir/install.sh
shellcheck "$install_sh" "$repo_dir/tests/test-install.sh"

work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT

expect_fail() {
  if "$@" >/dev/null 2>&1; then
    echo "Unexpectedly accepted: $*" >&2
    exit 1
  fi
}

check_config() {
  printf '%b\n' "$1" >"$work/config.yaml"
  "$install_sh" --check --config "$work/config.yaml"
}

expect_fail "$install_sh"
expect_fail "$install_sh" --check
expect_fail "$install_sh" --config
expect_fail "$install_sh" --components base
expect_fail "$install_sh" --check --config "$work/missing.yaml"
expect_fail "$install_sh" --check --config http://example.com/curlsh.yaml

bad_configs=(
  ''
  'platform: vm'
  'components:'
  'components: []'
  'components: base'
  'platform: vm\ncomponents: [base, invalid]'
  'platform: vm\ncomponents: [base]\nextra: 1'
  'platform: lxc\ncomponents: [docker]'
  'platform: lxc\ncomponents: [qemu_guest_agent]'
  'platform: bogus\ncomponents: [base]'
  'platform: vm\nplatform: lxc\ncomponents: [base]'
  'platform: vm\ncomponents: [base]\ncomponents: [codex]'
  'platform: vm\n- base'
  'platform: vm\ncomponents:\n  - "base"'
  'platform: vm\ncomponents: [base'
)
for config in "${bad_configs[@]}"; do
  if check_config "$config" >/dev/null 2>&1; then
    echo "Unexpectedly accepted config: $config" >&2
    exit 1
  fi
done

# Block list, comments, CRLF and duplicates.
output=$(check_config '---\n# Proxmox VM\nplatform: vm   # fixed\ncomponents:\n  - base\r\n  - nodejs\n  - base\n')
[[ $output == *'Platform: vm'* ]]
[[ $output == *'Components: base nodejs'* ]]
[[ $output == *'Packages'* ]]
[[ $output == *'Check: '*' change(s) needed'* ]]

# Flow list.
output=$(check_config 'platform: lxc\ncomponents: [ base , devtools ]')
[[ $output == *'Components: base devtools'* ]]

echo 'install checks passed'
