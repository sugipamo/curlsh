#!/usr/bin/env bash
set -Eeuo pipefail

repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$repo_dir"
platform=lxc components=base repo=sugipamo/curlsh ref=v0.2.0
checkout_entrypoint="$repo_dir/bootstrap.sh"
codex_target=0.157.1
# shellcheck source=lib/components.sh
source "$repo_dir/lib/components.sh"
# shellcheck source=lib/diagnostics.sh
source "$repo_dir/lib/diagnostics.sh"
# shellcheck source=lib/updates.sh
source "$repo_dir/lib/updates.sh"

# Test subprocesses override the probe boundaries, never the host package database.
(
  package_version() { [[ $1 == curl ]] && printf '1.0\n'; }
  read_command_version() { printf 'curl 1.0\n'; }
  probe_component base
  [[ ${observed_state[base]} == partial ]]
  [[ ${observed_detail[base]} == *'package(s) missing'* ]]
)
(
  package_version() { printf '1.0\n'; }
  read_command_version() { return 1; }
  probe_component base
  [[ ${observed_state[base]} == partial ]]
)
(
  package_version() { printf '1.0\n'; }
  component_commands[github_cli]=curlsh_test_command_not_on_path
  read_command_version() { printf 'gh version 1.0\n'; }
  probe_component github_cli
  [[ ${observed_state[github_cli]} == partial ]]
  [[ ${observed_detail[github_cli]} == *'not on current PATH'* ]]
)

mock_preflight() {
  read_target_os() { target_os=debian target_release=13 target_codename=trixie; }
  available_kib() { printf '99999999\n'; }
  systemd_running() { return 0; }
  tun_available() { return 0; }
  qemu_channel_available() { return 0; }
  codex_entry_compatible() { return 0; }
  probe_url() { return 0; }
  package_version() { return 1; }
}
(
  mock_preflight
  tun_available() { return 1; }
  if output=$(preflight tailscale 2>&1); then
    echo 'Missing TUN must block Tailscale on LXC' >&2; exit 1
  fi
  [[ $output == *'/dev/net/tun'* ]]
  # TUN is irrelevant when Tailscale was not selected.
  preflight base >/dev/null
)
(
  mock_preflight
  platform=vm
  package_version() { [[ $1 == docker.io ]] && printf '1.0\n'; }
  if output=$(preflight docker 2>&1); then exit 1; fi
  [[ $output == *'Docker conflict: docker.io'* ]]
)
(
  mock_preflight
  platform=vm
  qemu_channel_available() { return 1; }
  if output=$(preflight qemu_guest_agent 2>&1); then exit 1; fi
  [[ $output == *'qm set VMID --agent enabled=1'* ]]
)
(
  mock_preflight
  available_kib() { printf '1024\n'; }
  if output=$(preflight base 2>&1); then exit 1; fi
  [[ $output == *'free-space reserve'* ]]
)
(
  mock_preflight
  probe_url() { return 1; }
  if output=$(preflight github_cli 2>&1); then exit 1; fi
  [[ $output == *'Cannot reach'* ]]
)
(
  mock_preflight
  systemd_running() { return 1; }
  if output=$(preflight tailscale 2>&1); then exit 1; fi
  [[ $output == *'running systemd'* ]]
)

(
  # Shared packages are checked once; update checks never invoke an installer.
  # shellcheck disable=SC2329
  apt-get() { echo 'Unexpected package mutation' >&2; exit 99; }
  package_version() { printf '1.0\n'; }
  apt_candidate() { printf '2.0\n'; }
  output=$(check_updates base devtools)
  [[ $(printf '%s\n' "$output" | grep -c '^git ') -eq 1 ]]
  [[ $output == *'update available'* && $output == *'--only-upgrade'* ]]
  [[ $output == *'cached indexes'* ]]
)
(
  package_version() { printf '1.0\n'; }
  apt_candidate() { printf '(none)\n'; }
  if output=$(check_updates github_cli); then exit 1; fi
  [[ $output == *'UNKNOWN'* ]]
)
(
  package_version() { return 1; }
  output=$(check_updates github_cli)
  [[ $output == *'not installed'* ]]
  [[ $output != *'--only-upgrade'* ]]
)
(
  read_command_version() { printf 'codex-cli 0.150.0\n'; }
  latest_codex_version() { printf '0.160.0\n'; }
  output=$(check_updates codex)
  [[ $output == *'pinned update available'* ]]
  [[ $output == *'--non-interactive'* && $output == *'--components codex'* ]]
  [[ $output == *'upstream stable: 0.160.0'* ]]
)
(
  read_command_version() { printf 'codex-cli 0.160.0\n'; }
  latest_codex_version() { return 1; }
  if output=$(check_updates codex); then exit 1; fi
  [[ $output == *'reinstall would downgrade'* && $output == *'UNKNOWN codex upstream'* ]]
  [[ $output != *'--non-interactive'* ]]
)
(
  curl() { printf '{"tag_name":"rust-v0.160.0"}'; }
  [[ $(latest_codex_version) == 0.160.0 ]]
  curl() { printf '{"tag_name":"unexpected"}'; }
  if latest_codex_version >/dev/null 2>&1; then exit 1; fi
)
(
  resolve_command() { printf '/usr/local/bin/codex\n'; }
  read_command_version() { return 1; }
  if output=$(check_updates codex); then exit 1; fi
  [[ $output == *'UNKNOWN codex'* ]]
)
(
  # A stopped service is a verification failure, even if its packages are present.
  probe_component() { observed_state[$1]=installed; observed_detail[$1]='version 1.0'; }
  read_command_version() { printf 'version 1.0\n'; }
  systemd_running() { return 0; }
  systemctl() { return 3; }
  if output=$(verify_selected tailscale); then exit 1; fi
  [[ $output == *'tailscaled is not active'* && $output == *'journalctl'* ]]
)
(
  # Authentication is suggested, never executed and never inferred from root's credentials.
  probe_component() { observed_state[$1]=installed; observed_detail[$1]='version 1.0'; }
  read_command_version() { printf 'version 1.0\n'; }
  # shellcheck disable=SC2329
  gh() { echo 'Unexpected authentication access' >&2; exit 99; }
  output=$(verify_selected github_cli)
  [[ $output == *'OK '* && $output == *'gh auth status'* && $output == *'gh auth login'* ]]
)
(
  # A standalone invocation must not print paths inside its soon-to-be-deleted archive.
  checkout_entrypoint=
  output=$(followup_command --check-updates)
  [[ $output == *"https://raw.githubusercontent.com/$repo/$ref/bootstrap.sh"* ]]
  [[ $output != *'/tmp/'* && $output == *'--check-updates'* ]]
)
echo 'diagnostic and update checks passed'
