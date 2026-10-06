#!/usr/bin/env bash
# curlsh: choose, install and update development tools on Debian.
#
#   curl -fsSL https://github.com/sugipamo/curlsh/releases/latest/download/install.sh | sudo bash
#
# Nothing of curlsh itself stays installed. Each run fetches the release and
# applies the declaration in /etc/curlsh/config.yaml. Everything runs from
# main at the last line, so a truncated download never executes.
set -Eeuo pipefail

# The release workflow writes its tag here. Empty means "the latest release".
embedded_ref=

config_path=/etc/curlsh/config.yaml
state_path=/var/lib/curlsh/state

usage() {
  cat <<'EOF'
Usage: install.sh [apply|configure] [options]

  apply      Apply /etc/curlsh/config.yaml (default). Without a config,
             choose components interactively first.
  configure  Choose components interactively, save them, and apply.

Options:
  --config PATH|URL   Use this config (https URL or file); it is saved to
                      /etc/curlsh/config.yaml for later runs
  --components LIST   Comma-separated components; saved to the config
  --platform NAME     auto|lxc|vm|baremetal (with --components or configure)
  --ref vX.Y.Z        Use roles from this release instead of the latest
  --repo OWNER/NAME   Fetch releases from a fork
  --non-interactive   Never prompt
  --dry-run           Show what would be applied, change nothing
  -h, --help          Show this help

Components: base,github_cli,tailscale,codex,docker,nodejs,devtools,qemu_guest_agent
EOF
}

die() {
  local code=$1
  shift
  printf '%s\n' "$*" >&2
  exit "$code"
}

valid_component() {
  case "$1" in
    base|github_cli|tailscale|codex|docker|nodejs|devtools|qemu_guest_agent) return 0 ;;
    *) return 1 ;;
  esac
}

valid_platform() {
  case "$1" in auto|lxc|vm|baremetal) return 0 ;; *) return 1 ;; esac
}

valid_ref() {
  [[ $1 =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]
}

have_tty() {
  (exec </dev/tty) 2>/dev/null
}

require_root() {
  [[ $EUID -eq 0 ]] || die 1 'Run as root (curl ... | sudo bash)'
}

require_debian() {
  [[ -r /etc/os-release ]] || die 1 'Cannot identify the OS'
  local ID VERSION_ID
  # shellcheck source=/dev/null
  source /etc/os-release
  [[ $ID == debian && ( $VERSION_ID == 12 || $VERSION_ID == 13 ) ]] ||
    die 1 'Debian 12 or 13 is required'
}

apt_install() {
  apt-get update
  DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "$@"
}

detect_platform() {
  local virt
  virt=$(systemd-detect-virt 2>/dev/null || true)
  case "$virt" in
    lxc|openvz|systemd-nspawn) echo lxc ;;
    kvm|qemu|vmware|microsoft|oracle|xen) echo vm ;;
    docker|podman) die 2 'Container runtime detected; specify a supported platform explicitly' ;;
    *) echo baremetal ;;
  esac
}

ensure_yaml() {
  python3 -c 'import yaml' 2>/dev/null && return 0
  [[ $EUID -eq 0 ]] || die 1 'Reading the config needs python3-yaml (run as root to install it)'
  require_debian
  apt_install python3-yaml
}

# Prints the platform and the comma-joined components of a config file.
read_config() {
  python3 -I - "$1" <<'EOF'
import re
import sys

import yaml

try:
    with open(sys.argv[1], encoding='utf-8') as stream:
        data = yaml.safe_load(stream)
except (OSError, UnicodeDecodeError, yaml.YAMLError) as error:
    sys.exit(f'Cannot read config: {error}')
if not isinstance(data, dict):
    sys.exit('Config must be a mapping with "components"')
unknown = sorted(str(key) for key in data if key not in ('components', 'platform'))
if unknown:
    sys.exit('Unknown config keys: ' + ', '.join(unknown))
components = data.get('components')
if not isinstance(components, list) or not components:
    sys.exit('Config "components" must be a non-empty list')
for name in components:
    if not isinstance(name, str) or not re.fullmatch(r'[a-z_]+', name):
        sys.exit(f'Invalid component in config: {name!r}')
platform = data.get('platform', 'auto')
if not isinstance(platform, str) or not re.fullmatch(r'[a-z]+', platform):
    sys.exit(f'Invalid platform in config: {platform!r}')
print(platform)
print(','.join(components))
EOF
}

# Copies a config file or https URL to a private staging path.
stage_config() {
  local source=$1 staged
  staged=$temp_dir/config.yaml
  case "$source" in
    https://*)
      curl -fsSL --proto '=https' --max-filesize 65536 --retry 3 "$source" -o "$staged" ||
        die 1 "Cannot download config: $source"
      ;;
    *://*) die 2 'Config URLs must use https://' ;;
    *)
      [[ -f $source && -r $source ]] || die 1 "Cannot read config file: $source"
      cp -- "$source" "$staged"
      ;;
  esac
  printf '%s\n' "$staged"
}

load_config() {
  local parsed
  ensure_yaml
  parsed=$(read_config "$1") || return 1
  config_platform=${parsed%%$'\n'*}
  config_components=${parsed#*$'\n'}
}

render_config() {
  local item
  printf '# Managed by curlsh. Edit this file and run curlsh again to apply it.\n'
  printf 'platform: %s\n' "$1"
  printf 'components:\n'
  for item in "${@:2}"; do
    printf '  - %s\n' "$item"
  done
}

ensure_gum() {
  command -v gum >/dev/null 2>&1 && return 0
  apt_install ca-certificates curl gnupg
  install -d -m 0755 /etc/apt/keyrings
  curl -fsSL https://repo.charm.sh/apt/gpg.key | gpg --dearmor --yes -o /etc/apt/keyrings/charm.gpg
  chmod 0644 /etc/apt/keyrings/charm.gpg
  printf '%s\n' 'deb [signed-by=/etc/apt/keyrings/charm.gpg] https://repo.charm.sh/apt/ * *' \
    >/etc/apt/sources.list.d/charm.list
  apt_install gum
}

# Prints the chosen components, starting from the comma-joined preselection.
choose_components() {
  local platform=$1 preselected=$2 selection item
  local choices=(base github_cli tailscale codex nodejs devtools) initial=()
  if [[ $platform == vm ]]; then
    choices+=(docker qemu_guest_agent)
  elif [[ $platform == baremetal ]]; then
    choices+=(docker)
  fi
  for item in "${choices[@]}"; do
    [[ ,$preselected, == *,"$item",* ]] && initial+=("$item")
  done
  printf 'Detected platform: %s\n' "$platform" >&2
  selection=$(
    printf '%s\n' "${choices[@]}" |
      gum choose --no-limit --selected "$(IFS=,; echo "${initial[*]}")" \
        --header 'Install components (Space to select, Enter to continue)' 2>/dev/tty
  ) || die 1 'Cancelled'
  [[ -n $selection ]] || die 1 'No components selected'
  printf '%s\n' "$selection" | paste -sd, -
}

resolve_latest_ref() {
  local url tag
  url=$(curl -fsSLI -o /dev/null -w '%{url_effective}' "https://github.com/$1/releases/latest") ||
    die 1 "Cannot look up the latest release of $1"
  tag=${url##*/}
  valid_ref "$tag" || die 1 "No release found for $1"
  printf '%s\n' "$tag"
}

main() {
  local action=apply platform_flag='' components_flag='' config_source=''
  local non_interactive=0 dry_run=0 repo=sugipamo/curlsh ref=''
  temp_dir=$(mktemp -d)
  while (($#)); do
    case "$1" in
      apply|configure) action=$1; shift ;;
      --platform|--components|--config|--repo|--ref)
        (($# >= 2)) || die 2 "Missing value for $1"
        case "$1" in
          --platform) platform_flag=$2 ;;
          --components) components_flag=$2 ;;
          --config) config_source=$2 ;;
          --repo) repo=$2 ;;
          --ref) ref=$2 ;;
        esac
        shift 2 ;;
      --non-interactive) non_interactive=1; shift ;;
      --dry-run) dry_run=1; shift ;;
      --help|-h) usage; exit 0 ;;
      *) printf 'Unknown option: %s\n' "$1" >&2; usage >&2; exit 2 ;;
    esac
  done

  [[ $repo =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || die 2 'Invalid --repo (expected OWNER/NAME)'
  [[ -z $ref ]] || valid_ref "$ref" || die 2 'Use a fixed vX.Y.Z tag for --ref'
  [[ -z $platform_flag ]] || valid_platform "$platform_flag" || die 2 'Invalid platform'
  [[ -z $config_source || -z $components_flag ]] || die 2 'Use either --config or --components'
  if [[ $action == configure && -n $config_source$components_flag ]]; then
    die 2 'configure chooses components interactively; drop --config and --components'
  fi
  if [[ -n $platform_flag && $action != configure && -z $components_flag ]]; then
    die 2 '--platform works with --components or configure; otherwise set it in the config'
  fi

  # Where the declaration comes from: a given config, flags, the saved
  # config, or an interactive choice.
  local mode staged='' config_platform=auto config_components=''
  if [[ -n $config_source ]]; then
    mode=given
    staged=$(stage_config "$config_source")
    load_config "$staged" || exit 1
  elif [[ -n $components_flag ]]; then
    mode=flags
    config_platform=${platform_flag:-auto}
    config_components=$components_flag
  elif [[ $action == apply && -f $config_path ]]; then
    mode=saved
    load_config "$config_path" || exit 1
  else
    mode=interactive
    ((!dry_run)) || die 2 '--dry-run needs --config, --components or a saved config'
    ((!non_interactive)) || die 2 "No $config_path; pass --config or --components"
    have_tty || die 2 "No $config_path and no terminal; pass --config or --components"
    require_root
    require_debian
    # Preselect the saved choice; a broken config just starts empty.
    if [[ -f $config_path ]] && ! load_config "$config_path"; then
      config_platform=auto
      config_components=
    fi
    config_platform=${platform_flag:-$config_platform}
  fi

  valid_platform "$config_platform" || die 2 "Invalid platform: $config_platform"
  local platform=$config_platform
  [[ $platform != auto ]] || platform=$(detect_platform)

  if [[ $mode == interactive ]]; then
    ensure_gum
    config_components=$(choose_components "$platform" "$config_components")
  fi

  if [[ $config_components == ,* || $config_components == *, || $config_components == *,,* ]]; then
    die 2 'Empty component in the component list'
  fi
  local requested=() selected=() item
  local -A seen=()
  IFS=, read -r -a requested <<<"$config_components"
  ((${#requested[@]} > 0)) || die 2 'No components selected'
  for item in "${requested[@]}"; do
    valid_component "$item" || die 2 "Unknown component: $item"
    if [[ $item == qemu_guest_agent && $platform != vm ]]; then
      die 2 'qemu_guest_agent requires platform vm'
    fi
    if [[ $item == docker && $platform == lxc ]]; then
      die 2 'Docker is not supported by curlsh on LXC'
    fi
    if [[ -z ${seen[$item]+yes} ]]; then
      selected+=("$item")
      seen[$item]=1
    fi
  done
  local components
  components=$(IFS=,; echo "${selected[*]}")

  # Roles come from this checkout, or from the release archive.
  local script_dir='' project_dir=''
  if [[ -n $script_path ]]; then
    script_dir=$(cd -- "$(dirname -- "$script_path")" && pwd)
  fi
  if [[ -z $ref && -n $script_dir && -f $script_dir/playbook.yml && -d $script_dir/roles ]]; then
    project_dir=$script_dir
    ref=local
  else
    command -v curl >/dev/null || die 1 'curl is required'
    ref=${ref:-$embedded_ref}
    [[ -n $ref ]] || ref=$(resolve_latest_ref "$repo")
  fi

  local previous=''
  if [[ -r $state_path ]]; then
    previous=$(sed -n 's/^ref=\([A-Za-z0-9.]*\)$/\1/p' "$state_path")
  fi
  case "$mode" in
    given) printf 'Config: %s -> %s\n' "$config_source" "$config_path" ;;
    flags) printf 'Config: command line -> %s\n' "$config_path" ;;
    interactive) printf 'Config: selection -> %s\n' "$config_path" ;;
    saved) printf 'Config: %s\n' "$config_path" ;;
  esac
  printf 'Platform: %s\nComponents: %s\nVersion: %s%s\n' \
    "$platform" "$components" "${previous:+$previous -> }" "$ref"
  ((!dry_run)) || exit 0

  require_root
  require_debian
  if [[ $platform == lxc && ,$components, == *,tailscale,* && ! -e /dev/net/tun ]]; then
    die 1 'Tailscale on LXC requires /dev/net/tun passed through from Proxmox (see docs/proxmox.md).'
  fi
  if ((!non_interactive)) && have_tty; then
    ensure_gum
    gum confirm 'Apply this configuration?' </dev/tty || die 1 'Cancelled'
  fi

  # Save the declaration first, so a failed run can simply be repeated.
  if [[ $mode != saved ]]; then
    local new_config
    new_config=$temp_dir/config.new
    if [[ $mode == given ]]; then
      cp -- "$staged" "$new_config"
    else
      render_config "$config_platform" "${selected[@]}" >"$new_config"
    fi
    install -d -m 0755 "${config_path%/*}"
    install -m 0644 "$new_config" "$config_path"
  fi

  if [[ -z $project_dir ]]; then
    project_dir=$temp_dir/source
    curl -fsSL --retry 3 "https://github.com/$repo/archive/refs/tags/$ref.tar.gz" \
      -o "$temp_dir/source.tar.gz"
    mkdir "$project_dir"
    tar -xzf "$temp_dir/source.tar.gz" --strip-components=1 -C "$project_dir"
  fi

  if ! command -v ansible-playbook >/dev/null 2>&1; then
    apt_install ansible-core
  fi
  if ! dpkg-query -W -f='${Status}' python3-apt 2>/dev/null | grep -qx 'install ok installed'; then
    apt_install python3-apt
  fi

  (
    cd "$project_dir"
    ansible-playbook -i localhost, -c local playbook.yml \
      --tags "$components" --extra-vars "bootstrap_platform=$platform" </dev/null
  )

  install -d -m 0755 "${state_path%/*}"
  printf 'ref=%s\napplied_at=%s\n' "$ref" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >"$state_path"
  echo 'curlsh complete. Register Tailscale and sign in to Codex on this machine if selected.'
}

# Empty when piped into bash; read here because inside a function it is "main".
script_path=${BASH_SOURCE[0]-}
temp_dir=
trap '[[ -z $temp_dir ]] || rm -rf -- "$temp_dir"' EXIT
main "$@"
