#!/usr/bin/env bash
# Runtime observations only; these values are never saved between invocations.

component_ids=(base github_cli tailscale codex docker nodejs devtools qemu_guest_agent)
declare -A component_labels=(
  [base]='Basic tools' [github_cli]='GitHub CLI' [tailscale]='Tailscale'
  [codex]='Codex CLI' [docker]='Docker Engine + Compose'
  [nodejs]='Node.js + npm' [devtools]='Development tools'
  [qemu_guest_agent]='QEMU guest agent'
)
declare -A component_packages=(
  [base]='ca-certificates curl git jq openssh-client'
  [github_cli]='gh' [tailscale]='tailscale' [codex]=''
  [docker]='docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin'
  [nodejs]='nodejs npm'
  [devtools]='build-essential git make pkg-config ripgrep unzip'
  [qemu_guest_agent]='qemu-guest-agent'
)
declare -A component_commands=(
  [base]='curl git jq ssh' [github_cli]='gh' [tailscale]='tailscale'
  [codex]='codex' [docker]='docker' [nodejs]='node npm'
  [devtools]='cc make pkg-config rg unzip' [qemu_guest_agent]='qemu-ga'
)
declare -A component_services=(
  [tailscale]='tailscaled' [docker]='docker' [qemu_guest_agent]='qemu-guest-agent'
)
declare -A observed_state=() observed_detail=() observed_version=()

valid_component() {
  case "$1" in
    base|github_cli|tailscale|codex|docker|nodejs|devtools|qemu_guest_agent) return 0 ;;
    *) return 1 ;;
  esac
}

component_supported() {
  case "$1:$platform" in docker:lxc|qemu_guest_agent:lxc|qemu_guest_agent:baremetal) return 1 ;; esac
}

package_version() {
  local result
  result=$(dpkg-query -W -f='${db:Status-Status} ${Version}' "$1" 2>/dev/null) || return 1
  [[ $result == 'installed '* ]] || return 1
  printf '%s\n' "${result#installed }"
}

resolve_command() {
  command -v "$1" 2>/dev/null ||
    { [[ -x /usr/local/bin/$1 ]] && printf '/usr/local/bin/%s\n' "$1"; } ||
    { [[ -x /usr/sbin/$1 ]] && printf '/usr/sbin/%s\n' "$1"; }
}

read_command_version() {
  local executable
  executable=$(resolve_command "$1") || return 1
  case "$1" in
    ssh) timeout 8 "$executable" -V 2>&1 ;;
    unzip) timeout 8 "$executable" -v 2>&1 ;;
    *) timeout 8 "$executable" --version 2>&1 ;;
  esac
}

one_line() {
  # Do not let terminal control characters from a version banner enter the menu.
  LC_ALL=C tr -cd '\11\12\15\40-\176' | tr '\t\r\n' '   ' | cut -c 1-160 | sed 's/ *$//'
}

probe_component() {
  local id=$1 package count=0 missing=0 version primary
  local -a packages commands
  read -r -a packages <<<"${component_packages[$id]}"
  read -r -a commands <<<"${component_commands[$id]}"
  primary=${commands[0]}
  observed_state[$id]=missing
  observed_detail[$id]='not installed'
  observed_version[$id]=
  for package in "${packages[@]}"; do
    if package_version "$package" >/dev/null; then
      count=$((count + 1))
    else
      missing=$((missing + 1))
    fi
  done
  if version=$(read_command_version "$primary"); then
    observed_state[$id]=installed
    observed_version[$id]=$(printf '%s\n' "$version" | head -n 1 | one_line)
    observed_detail[$id]=${observed_version[$id]}
    if ((missing)); then
      observed_state[$id]=partial
      observed_detail[$id]+="; $missing package(s) missing"
    fi
    if ! command -v "$primary" >/dev/null 2>&1; then
      observed_state[$id]=partial
      observed_detail[$id]+="; not on current PATH"
    fi
  elif ((count)) || resolve_command "$primary" >/dev/null; then
    observed_state[$id]=partial
    observed_detail[$id]='installed files found, but version check failed'
  fi
}

show_status() {
  local id service state
  printf '\n%-18s %-12s %s\n' COMPONENT STATE DETAILS
  for id in "$@"; do
    probe_component "$id"
    printf '%-18s %-12s %s\n' "$id" "${observed_state[$id]}" "${observed_detail[$id]}"
    service=${component_services[$id]-}
    if [[ -n $service ]] && systemd_running; then
      state=$(systemctl is-active "$service" 2>/dev/null) || true
      printf '  service: %s (%s)\n' "$service" "${state:-unknown}"
    fi
  done
}
