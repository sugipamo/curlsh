#!/usr/bin/env bash
# curlsh: set up development tools on Debian from a config file.
#
#   curl -fsSL https://github.com/sugipamo/curlsh/releases/latest/download/install.sh |
#     sudo bash -s -- --config https://example.com/curlsh.yaml
#
# curlsh leaves nothing of itself on the machine: no copy of this script, no
# saved config, no state. Each run reads the config, checks the machine, and
# installs or upgrades what the config lists. Everything runs from main at the
# last line, so a truncated download never executes.
set -Eeuo pipefail

# The release workflow writes its tag here.
embedded_ref=

usage() {
  cat <<'EOF'
Usage: install.sh --config PATH|URL [--check]

  --config PATH|URL  Config file, or an https:// URL to one (required)
  --check            Report what would change, change nothing
  -h, --help         Show this help

Config (YAML subset):
  platform: auto        # auto | lxc | vm | baremetal (optional)
  components:
    - base
    - codex

Components: base github_cli tailscale codex docker nodejs devtools qemu_guest_agent
EOF
}

die() {
  local code=$1
  shift
  printf 'curlsh: %s\n' "$*" >&2
  exit "$code"
}

valid_component() {
  case "$1" in
    base|github_cli|tailscale|codex|docker|nodejs|devtools|qemu_guest_agent) return 0 ;;
    *) return 1 ;;
  esac
}

component_packages() {
  case "$1" in
    base) echo ca-certificates curl git jq openssh-client ;;
    github_cli) echo gh ;;
    tailscale) echo tailscale ;;
    docker) echo docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin ;;
    nodejs) echo nodejs npm ;;
    devtools) echo build-essential git make pkg-config ripgrep unzip ;;
    qemu_guest_agent) echo qemu-guest-agent ;;
  esac
}

component_service() {
  case "$1" in
    tailscale) echo tailscaled ;;
    docker) echo docker ;;
    qemu_guest_agent) echo qemu-guest-agent ;;
  esac
}

# Sets repo_key_url, repo_key, repo_list and repo_line for components that
# come from a vendor APT repository.
component_repo() {
  case "$1" in
    github_cli)
      repo_key_url=https://cli.github.com/packages/githubcli-archive-keyring.gpg
      repo_key=/etc/apt/keyrings/githubcli-archive-keyring.gpg
      repo_list=/etc/apt/sources.list.d/github-cli.list
      repo_line="deb [arch=$deb_arch signed-by=$repo_key] https://cli.github.com/packages stable main"
      ;;
    tailscale)
      repo_key_url=https://pkgs.tailscale.com/stable/debian/$codename.noarmor.gpg
      repo_key=/usr/share/keyrings/tailscale-archive-keyring.gpg
      repo_list=/etc/apt/sources.list.d/tailscale.list
      repo_line="deb [signed-by=$repo_key] https://pkgs.tailscale.com/stable/debian $codename main"
      ;;
    docker)
      repo_key_url=https://download.docker.com/linux/debian/gpg
      repo_key=/etc/apt/keyrings/docker.asc
      repo_list=/etc/apt/sources.list.d/docker.list
      repo_line="deb [arch=$deb_arch signed-by=$repo_key] https://download.docker.com/linux/debian $codename stable"
      ;;
    *) return 1 ;;
  esac
}

# Prints one result line. In --check mode, actions read as plans.
report() {
  local action=$1 subject=$2 word
  case "$action" in
    ok|skip) word=$action ;;
    *)
      changes=$((changes + 1))
      if ((check)); then
        word="will $action"
      else
        case "$action" in
          install) word=installed ;; upgrade) word=upgraded ;; update) word=updated ;;
          create) word=created ;; enable) word=enabled ;; start) word=started ;;
          *) word=$action ;;
        esac
      fi
      ;;
  esac
  printf '  %-14s %s\n' "$word" "$subject"
}

fetch() {
  curl -fsSL --proto '=https' --retry 3 "$1" -o "$2" || die 1 "cannot download $1"
}

# Copies a config file or https URL to the temporary directory.
stage_config() {
  local source=$1 staged=$temp_dir/config.yaml
  case "$source" in
    https://*) curl -fsSL --proto '=https' --max-filesize 65536 --retry 3 "$source" -o "$staged" ||
      die 1 "cannot download config: $source" ;;
    *://*) die 2 'config URLs must use https://' ;;
    *) [[ -f $source && -r $source ]] || die 1 "cannot read config file: $source"
      cp -- "$source" "$staged" ;;
  esac
  config_file=$staged
}

# Reads the supported YAML subset into platform and requested.
parse_config() {
  local line n=0 in_list=0 seen_platform=0 seen_components=0 item items
  local re_item='^[[:space:]]+-[[:space:]]+([a-z_]+)$'
  local re_platform='^platform:[[:space:]]*([a-z]+)$'
  local re_block='^components:$'
  local re_flow='^components:[[:space:]]*\[(.*)\]$'
  platform=auto
  requested=()
  while IFS= read -r line || [[ -n $line ]]; do
    n=$((n + 1))
    line=${line%$'\r'}
    line=${line%%#*}
    line=${line%"${line##*[![:space:]]}"}
    [[ -n $line && $line != --- ]] || continue
    if [[ $line =~ $re_item ]]; then
      ((in_list)) || die 2 "config line $n: list item outside components"
      requested+=("${BASH_REMATCH[1]}")
      continue
    fi
    in_list=0
    if [[ $line =~ $re_platform ]]; then
      ((!seen_platform)) || die 2 "config line $n: platform is set twice"
      seen_platform=1
      platform=${BASH_REMATCH[1]}
    elif [[ $line =~ $re_block ]]; then
      ((!seen_components)) || die 2 "config line $n: components is set twice"
      seen_components=1
      in_list=1
    elif [[ $line =~ $re_flow ]]; then
      ((!seen_components)) || die 2 "config line $n: components is set twice"
      seen_components=1
      IFS=, read -r -a items <<<"${BASH_REMATCH[1]}"
      for item in "${items[@]}"; do
        item=${item//[[:space:]]/}
        [[ $item =~ ^[a-z_]+$ ]] || die 2 "config line $n: invalid component '$item'"
        requested+=("$item")
      done
    else
      die 2 "config line $n: unsupported line: $line"
    fi
  done <"$1"
  ((seen_components)) || die 2 'config has no components'
  ((${#requested[@]} > 0)) || die 2 'config components is empty'
}

detect_platform() {
  local virt
  virt=$(systemd-detect-virt 2>/dev/null || true)
  case "$virt" in
    lxc|openvz|systemd-nspawn) echo lxc ;;
    kvm|qemu|vmware|microsoft|oracle|xen) echo vm ;;
    docker|podman) die 2 'container runtime detected; set platform in the config' ;;
    *) echo baremetal ;;
  esac
}

# Prints the installed version of a package, or nothing.
installed_version() {
  local status
  status=$(dpkg-query -W -f='${db:Status-Abbrev}|${Version}' "$1" 2>/dev/null || true)
  [[ $status == ii* ]] && printf '%s\n' "${status#*|}"
  return 0
}

candidate_version() {
  LC_ALL=C apt-cache policy "$1" 2>/dev/null | awk '/Candidate:/ { print $2; exit }'
}

sync_file() {
  local source=$1 dest=$2
  if [[ -f $dest ]] && cmp -s "$source" "$dest"; then
    report ok "$dest"
    return
  fi
  if [[ -e $dest ]]; then report update "$dest"; else report create "$dest"; fi
  ((check)) || install -D -m 0644 "$source" "$dest"
}

sync_repositories() {
  local name n=0
  for name in "${selected[@]}"; do
    component_repo "$name" || continue
    ((n++)) || printf 'Repositories\n'
    fetch "$repo_key_url" "$temp_dir/$name.key"
    sync_file "$temp_dir/$name.key" "$repo_key"
    printf '%s\n' "$repo_line" >"$temp_dir/$name.list"
    sync_file "$temp_dir/$name.list" "$repo_list"
  done
}

sync_packages() {
  local -a packages=()
  local -A before=() seen=()
  local name pkg after log=$temp_dir/apt.log
  for name in "${selected[@]}"; do
    for pkg in $(component_packages "$name"); do
      [[ -n ${seen[$pkg]+yes} ]] || { packages+=("$pkg"); seen[$pkg]=1; }
    done
  done
  ((${#packages[@]})) || return 0
  printf 'Packages\n'
  for pkg in "${packages[@]}"; do
    before[$pkg]=$(installed_version "$pkg")
  done

  if ((check)); then
    for pkg in "${packages[@]}"; do
      after=$(candidate_version "$pkg")
      [[ $after != "(none)" ]] || after=''
      if [[ -z ${before[$pkg]} ]]; then
        report install "$pkg${after:+ $after}"
      elif [[ -n $after && $after != "${before[$pkg]}" ]]; then
        report upgrade "$pkg ${before[$pkg]} -> $after"
      else
        report ok "$pkg ${before[$pkg]}"
      fi
    done
    return 0
  fi

  # apt-get install also upgrades packages that are already installed.
  if ! { apt-get -q update && DEBIAN_FRONTEND=noninteractive apt-get -q install -y "${packages[@]}"; } >"$log" 2>&1; then
    cat "$log" >&2
    die 1 'apt-get failed'
  fi
  for pkg in "${packages[@]}"; do
    after=$(installed_version "$pkg")
    if [[ -z ${before[$pkg]} ]]; then
      report install "$pkg $after"
    elif [[ $after != "${before[$pkg]}" ]]; then
      report upgrade "$pkg ${before[$pkg]} -> $after"
    else
      report ok "$pkg $after"
    fi
  done
}

sync_services() {
  local name service enabled active n=0
  for name in "${selected[@]}"; do
    service=$(component_service "$name")
    [[ -n $service ]] || continue
    ((n++)) || printf 'Services\n'
    if [[ ! -d /run/systemd/system ]]; then
      report skip "$service (systemd is not running)"
      continue
    fi
    enabled=$(systemctl is-enabled "$service" 2>/dev/null || true)
    active=$(systemctl is-active "$service" 2>/dev/null || true)
    if [[ $enabled == enabled && $active == active ]]; then
      report ok "$service"
      continue
    fi
    [[ $enabled == enabled ]] || report enable "$service"
    [[ $active == active ]] || report start "$service"
    ((check)) || systemctl enable --now "$service"
  done
}

sync_codex() {
  local latest current='' link
  printf 'Codex\n'
  latest=$(curl -fsSL --retry 3 https://releases.openai.com/codex/channels/latest |
    grep -o '"tag_name": *"rust-v[^"]*"' | head -n 1 | sed 's/.*rust-v//; s/"$//') || true
  [[ $latest =~ ^[0-9]+\.[0-9]+\.[0-9]+ ]] || die 1 'cannot find the latest Codex release'
  if [[ -x /usr/local/bin/codex ]]; then
    current=$(/usr/local/bin/codex --version 2>/dev/null | awk '{ print $2 }') || true
  fi
  if [[ $current == "$latest" ]]; then
    report ok "codex $current"
  else
    if [[ -n $current ]]; then report upgrade "codex $current -> $latest"; else report install "codex $latest"; fi
    if ((!check)); then
      fetch https://releases.openai.com/codex/install.sh "$temp_dir/codex-install.sh"
      CODEX_RELEASE=$latest CODEX_NON_INTERACTIVE=1 CODEX_INSTALL_DIR=/usr/local/bin \
        CODEX_HOME=/usr/local/lib/codex sh "$temp_dir/codex-install.sh" >"$temp_dir/codex.log" 2>&1 ||
        { cat "$temp_dir/codex.log" >&2; die 1 'Codex installer failed'; }
    fi
  fi
  # A link in /usr/bin keeps codex on minimal PATHs such as non-login SSH.
  link=$(readlink /usr/bin/codex 2>/dev/null || true)
  if [[ $link == /usr/local/bin/codex ]]; then
    report ok /usr/bin/codex
  else
    report create '/usr/bin/codex -> /usr/local/bin/codex'
    ((check)) || ln -s /usr/local/bin/codex /usr/bin/codex
  fi
}

main() {
  local config_source='' item
  check=0
  while (($#)); do
    case "$1" in
      --config)
        (($# >= 2)) || die 2 'missing value for --config'
        config_source=$2
        shift 2 ;;
      --check) check=1; shift ;;
      -h|--help) usage; exit 0 ;;
      *) printf 'curlsh: unknown option: %s\n' "$1" >&2; usage >&2; exit 2 ;;
    esac
  done
  [[ -n $config_source ]] || { usage >&2; die 2 '--config is required'; }

  temp_dir=$(mktemp -d)
  stage_config "$config_source"
  parse_config "$config_file"

  case "$platform" in auto|lxc|vm|baremetal) ;; *) die 2 "invalid platform: $platform" ;; esac
  [[ $platform != auto ]] || platform=$(detect_platform)

  selected=()
  local -A seen=()
  for item in "${requested[@]}"; do
    valid_component "$item" || die 2 "unknown component: $item"
    [[ $item != qemu_guest_agent || $platform == vm ]] || die 2 'qemu_guest_agent needs platform vm'
    [[ $item != docker || $platform != lxc ]] || die 2 'docker is not supported on lxc'
    [[ -n ${seen[$item]+yes} ]] || { selected+=("$item"); seen[$item]=1; }
  done

  printf 'curlsh %s\nConfig: %s\nPlatform: %s\nComponents: %s\n' \
    "${embedded_ref:-dev}" "$config_source" "$platform" "${selected[*]}"

  local ID='' VERSION_ID='' VERSION_CODENAME=''
  # shellcheck source=/dev/null
  [[ -r /etc/os-release ]] && source /etc/os-release
  if [[ $ID != debian || ( $VERSION_ID != 12 && $VERSION_ID != 13 ) ]]; then
    ((check)) || die 1 'Debian 12 or 13 is required'
    printf 'Warning: not Debian 12 or 13; results only show what curlsh would check.\n'
  fi
  ((check)) || [[ $EUID -eq 0 ]] || die 1 'run as root (curl ... | sudo bash -s -- --config ...)'
  codename=$VERSION_CODENAME
  deb_arch=$(dpkg --print-architecture 2>/dev/null || echo amd64)
  if [[ $platform == lxc && -n ${seen[tailscale]+yes} && ! -e /dev/net/tun ]]; then
    die 1 'tailscale on LXC needs /dev/net/tun passed through from Proxmox (see docs/proxmox.md)'
  fi
  if [[ -n ${seen[codex]+yes} && -e /usr/bin/codex ]] &&
    [[ $(readlink /usr/bin/codex 2>/dev/null || true) != /usr/local/bin/codex ]]; then
    die 1 '/usr/bin/codex exists and is not managed by curlsh'
  fi

  changes=0
  sync_repositories
  sync_packages
  sync_services
  [[ -z ${seen[codex]+yes} ]] || sync_codex

  if ((check)); then
    printf 'Check: %d change(s) needed\n' "$changes"
  else
    printf 'Done: %d change(s)\n' "$changes"
  fi
}

temp_dir=
trap '[[ -z $temp_dir ]] || rm -rf -- "$temp_dir"' EXIT
main "$@"
