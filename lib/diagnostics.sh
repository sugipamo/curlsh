#!/usr/bin/env bash

read_target_os() {
  local ID='' VERSION_ID='' VERSION_CODENAME=''
  # shellcheck source=/dev/null
  source /etc/os-release
  target_os=$ID target_release=$VERSION_ID target_codename=$VERSION_CODENAME
}

systemd_running() { [[ -d /run/systemd/system ]] && command -v systemctl >/dev/null; }
tun_available() { [[ -c /dev/net/tun ]]; }
qemu_channel_available() { [[ -e /dev/virtio-ports/org.qemu.guest_agent.0 ]]; }
available_kib() { df -Pk /usr | awk 'NR == 2 {print $4}'; }
codex_entry_compatible() {
  [[ ! -e /usr/bin/codex && ! -L /usr/bin/codex ]] ||
    [[ -L /usr/bin/codex && $(readlink /usr/bin/codex) == /usr/local/bin/codex ]]
}

check_fail() {
  printf 'FAIL: %s\n' "$*" >&2
  checks_failed=$((checks_failed + 1))
}

require_target_os() {
  read_target_os
  [[ $target_os == debian && ( $target_release == 12 || $target_release == 13 ) ]]
}

probe_url() {
  curl --proto '=https' --connect-timeout 5 --max-time 15 -fsSL -o /dev/null "$1" 2>/dev/null
}

preflight() {
  local id package service architecture free required=262144 url command
  local -A urls=()
  checks_failed=0
  printf '\nPreflight (no packages are installed by this check)\n'
  if ! require_target_os; then
    check_fail "Debian 12 or 13 is required (found $target_os $target_release)."
  fi
  for command in apt-get dpkg-query timeout; do
    command -v "$command" >/dev/null || check_fail "Required system command is missing: $command."
  done
  architecture=$(uname -m)
  for id in "$@"; do
    service=${component_services[$id]-}
    if [[ -n $service ]] && ! systemd_running; then
      check_fail "$id requires a running systemd instance."
    fi
    case "$id" in
      codex)
        required=$((required + 1048576))
        case "$architecture" in x86_64|aarch64) ;; *)
          check_fail "Codex requires x86_64 or aarch64 (found $architecture)." ;; esac
        if ! codex_entry_compatible; then
          check_fail '/usr/bin/codex already exists outside curlsh; resolve this entry before installing.'
        fi
        urls[https://chatgpt.com/codex/install.sh]=1
        urls[https://releases.openai.com/codex/channels/latest]=1
        ;;
      github_cli) urls[https://cli.github.com/packages/githubcli-archive-keyring.gpg]=1 ;;
      tailscale)
        if [[ $platform == lxc ]] && ! tun_available; then
          check_fail 'Pass /dev/net/tun through from Proxmox before installing Tailscale; see docs/proxmox.md.'
        fi
        urls["https://pkgs.tailscale.com/stable/debian/${target_codename:-bookworm}.noarmor.gpg"]=1
        ;;
      docker)
        required=$((required + 1048576))
        for package in docker.io docker-compose docker-doc podman-docker containerd runc; do
          if package_version "$package" >/dev/null; then
            check_fail "Docker conflict: $package is installed. Review it before removing or migrating it."
          fi
        done
        urls[https://download.docker.com/linux/debian/gpg]=1
        ;;
      nodejs|devtools) required=$((required + 524288)) ;;
      qemu_guest_agent)
        if ! qemu_channel_available; then
          check_fail 'QEMU agent channel is missing. On the Proxmox host: qm set VMID --agent enabled=1 (replace VMID), then cold-start the VM.'
        fi
        ;;
    esac
  done
  free=$(available_kib)
  if [[ ! $free =~ ^[0-9]+$ ]]; then
    check_fail 'Could not determine free space on /usr.'
  elif ((free < required)); then
    check_fail "Need a free-space reserve of $((required / 1024)) MiB on /usr; found $((free / 1024)) MiB."
  fi
  if (("${#urls[@]}" > 0)); then
    if command -v curl >/dev/null; then
      for url in "${!urls[@]}"; do
        if ! probe_url "$url"; then
          check_fail "Cannot reach $url (DNS, TLS, proxy or network). Retry --check after fixing connectivity."
        fi
      done
    else
      printf 'NOTE: HTTPS checks need curl; rerun --check after installing ca-certificates and curl.\n'
    fi
    printf 'Dependencies: ca-certificates + curl are installed automatically by the selected roles.\n'
  fi
  printf 'Preflight: %s blocking issue(s). Disk checks use reserve thresholds, not exact download sizes.\n' "$checks_failed"
  ((checks_failed == 0))
}

print_command() {
  printf '  '
  printf '%q ' "$@"
  printf '\n'
}

followup_command() {
  if [[ -n $checkout_entrypoint ]]; then
    print_command bash "$checkout_entrypoint" "$@" --platform "$platform" --components "$components"
  else
    printf '  set -o pipefail; curl -fsSL %q | bash -s -- ' \
      "https://raw.githubusercontent.com/$repo/$ref/bootstrap.sh"
    printf '%q ' --repo "$repo" --ref "$ref" "$@" --platform "$platform" --components "$components"
    printf '\n'
  fi
}

print_next_steps() {
  local id
  local -a needs_install=()
  printf '\nNext steps (commands below are suggestions, not executed):\n'
  for id in "$@"; do
    [[ ${observed_state[$id]-missing} == installed ]] || needs_install+=("$id")
  done
  if (("${#needs_install[@]}")); then
    printf 'Install or repair incomplete components as root (preflight runs first):\n'
    components=$(IFS=,; echo "${needs_install[*]}") followup_command --non-interactive
  fi
  printf 'Check available updates; APT uses the current local package index:\n'
  followup_command --check-updates
  for id in "$@"; do
    [[ ${observed_state[$id]-missing} != missing ]] || continue
    case "$id" in
      codex)
        printf 'Codex: run as the user who will use it. Check sign-in; sign in if needed:\n'
        print_command codex login status
        print_command codex login --device-auth
        ;;
      github_cli)
        printf 'GitHub CLI: run as the user who will use it. Check sign-in; sign in if needed:\n'
        print_command gh auth status
        print_command gh auth login
        ;;
      tailscale)
        printf 'Tailscale: check connection; join if needed (tailscale up needs root):\n'
        print_command tailscale status
        print_command tailscale up --ssh
        ;;
      docker)
        printf 'Docker: optionally run an end-to-end container test as root:\n'
        print_command docker run --rm hello-world
        ;;
    esac
  done
}

verify_selected() {
  local id command service detail failures=0 output
  local -a commands
  printf '\nInstallation verification (authentication is a separate user action)\n'
  for id in "$@"; do
    probe_component "$id"
    detail=
    if [[ ${observed_state[$id]} != installed ]]; then
      detail=${observed_detail[$id]}
    else
      read -r -a commands <<<"${component_commands[$id]}"
      for command in "${commands[@]}"; do
        if ! read_command_version "$command" >/dev/null; then
          detail+=" $command failed its version check;"
        fi
      done
      if [[ $id == codex ]]; then
        output=$(read_command_version codex) || output=
        if [[ $output != "codex-cli $codex_target" ]]; then
          detail+=' current PATH resolves to a different Codex version;'
          printf 'Inspect which Codex command is selected by your shell:\n'
          print_command type -a codex
        fi
        output=$(PATH=/sbin:/bin:/usr/sbin:/usr/bin timeout 8 codex --version 2>/dev/null) || output=
        [[ $output == "codex-cli $codex_target" ]] || detail+=' minimal-PATH or pinned-version check failed;'
      elif [[ $id == docker ]]; then
        timeout 8 docker compose version >/dev/null 2>&1 || detail+=' docker compose is unavailable;'
      fi
    fi
    service=${component_services[$id]-}
    if [[ -n $service ]]; then
      if ! systemd_running || ! systemctl is-active --quiet "$service"; then
        detail+=" $service is not active;"
        printf 'Inspect the service:\n'
        print_command systemctl status "$service" --no-pager
        print_command journalctl -u "$service" -n 50 --no-pager
      fi
    fi
    if [[ -n $detail ]]; then
      printf 'FAIL %-18s %s\n' "$id" "$detail"
      failures=$((failures + 1))
    else
      printf 'OK   %-18s %s\n' "$id" "${observed_detail[$id]}"
    fi
  done
  print_next_steps "$@"
  ((failures == 0))
}
