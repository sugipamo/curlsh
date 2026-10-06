#!/usr/bin/env bash
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

output=$("$install_sh" --dry-run --platform vm --components base,codex,qemu_guest_agent,codex)
[[ $output == *'Config: command line -> /etc/curlsh/config.yaml'* ]]
[[ $output == *'Platform: vm'* ]]
[[ $output == *'Components: base,codex,qemu_guest_agent'* ]]
[[ $output == *'Version: local'* ]]

expect_fail "$install_sh" --dry-run --platform lxc --components docker
expect_fail "$install_sh" --dry-run --platform vm --components invalid
expect_fail "$install_sh" --dry-run --platform lxc --components qemu_guest_agent
expect_fail "$install_sh" --dry-run --platform vm --components base,
expect_fail "$install_sh" --dry-run --platform vm --components base,,codex
expect_fail "$install_sh" --dry-run --components base --repo invalid
expect_fail "$install_sh" --dry-run --components base --ref main
expect_fail "$install_sh" --dry-run --platform bogus --components base
expect_fail "$install_sh" --dry-run --config "$work/missing.yaml"
expect_fail "$install_sh" --dry-run --config http://example.com/curlsh.yaml
expect_fail "$install_sh" --dry-run --config "$work/missing.yaml" --components base
expect_fail "$install_sh" configure --dry-run --components base
# --platform belongs in the config file unless components are chosen here.
expect_fail "$install_sh" --dry-run --platform vm --config "$work/missing.yaml"

cat >"$work/good.yaml" <<'EOF'
# Proxmox VM
platform: vm
components: [base, tailscale, qemu_guest_agent, base]
EOF
output=$("$install_sh" --dry-run --config "$work/good.yaml")
[[ $output == *"Config: $work/good.yaml -> /etc/curlsh/config.yaml"* ]]
[[ $output == *'Platform: vm'* ]]
[[ $output == *'Components: base,tailscale,qemu_guest_agent'* ]]

# Without a platform the config auto-detects, which refuses containers.
case "$(systemd-detect-virt 2>/dev/null || true)" in
  docker|podman) ;;
  *)
    printf 'components:\n  - base\n  - codex\n' >"$work/default-platform.yaml"
    output=$("$install_sh" --dry-run --config "$work/default-platform.yaml")
    [[ $output == *'Components: base,codex'* ]]
    ;;
esac

bad_configs=(
  'components: []'
  'components: base\nplatform: vm'
  'components: [base, invalid]\nplatform: vm'
  'components: [base]\nplatform: lxc\nextra: 1'
  'components: [docker]\nplatform: lxc'
  'components: ["base\\ncodex"]'
  'components: [base]\nplatform: [vm]'
  '- base'
  'components: [base'
)
for config in "${bad_configs[@]}"; do
  printf '%b\n' "$config" >"$work/bad.yaml"
  expect_fail "$install_sh" --dry-run --config "$work/bad.yaml"
done

# Piped into bash, the script must not mistake the working directory for a checkout.
output=$(cd "$repo_dir" && bash -s -- --dry-run --ref v0.1.0 --platform vm --components base <"$install_sh")
[[ $output == *'Version: v0.1.0'* ]]

echo 'install argument checks passed'

