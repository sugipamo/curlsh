#!/usr/bin/env bash
set -Eeuo pipefail

usage() {
  cat <<'EOF'
Usage: bootstrap.sh [--platform auto|lxc|vm|baremetal] [--components LIST]
                    [--non-interactive] [--dry-run] [--repo OWNER/NAME] [--ref TAG]

Components: base,github_cli,tailscale,codex,docker,nodejs,devtools,qemu_guest_agent

Run from this checkout, or download this one file from a version tag. A
downloaded bootstrap fetches the complete repository archive at the same tag.
Non-interactive mode requires --components; interactive mode requires a TTY.
EOF
}

platform=auto
components=
non_interactive=0
dry_run=0
repo=sugipamo/curlsh
ref=v0.1.0
while (($#)); do
  case "$1" in
    --platform|--components|--repo|--ref)
      (($# >= 2)) || { echo "Missing value for $1" >&2; exit 2; }
      case "$1" in
        --platform) platform=$2 ;;
        --components) components=$2 ;;
        --repo) repo=$2 ;;
        --ref) ref=$2 ;;
      esac
      shift 2 ;;
    --non-interactive) non_interactive=1; shift ;;
    --dry-run) dry_run=1; shift ;;
    --help|-h) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

if [[ -n $repo && ! $repo =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]]; then
  echo 'Invalid --repo (expected OWNER/NAME)' >&2
  exit 2
fi
[[ $ref =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo 'Use a fixed vX.Y.Z tag for --ref' >&2; exit 2; }
case "$platform" in auto|lxc|vm|baremetal) ;; *) echo 'Invalid platform' >&2; exit 2 ;; esac

if [[ $platform == auto ]]; then
  virt=$(systemd-detect-virt 2>/dev/null || true)
  case "$virt" in
    lxc|openvz|systemd-nspawn) platform=lxc ;;
    kvm|qemu|vmware|microsoft|oracle|xen) platform=vm ;;
    docker|podman) echo 'Container runtime detected; specify a supported platform explicitly' >&2; exit 2 ;;
    *) platform=baremetal ;;
  esac
fi

valid_component() {
  case "$1" in
    base|github_cli|tailscale|codex|docker|nodejs|devtools|qemu_guest_agent) return 0 ;;
    *) return 1 ;;
  esac
}

if ((non_interactive)); then
  [[ -n $components ]] || { echo '--non-interactive requires --components' >&2; exit 2; }
elif [[ -n $components ]]; then
  echo 'Use --non-interactive with --components' >&2
  exit 2
elif ((dry_run)); then
  echo '--dry-run requires --non-interactive and --components' >&2
  exit 2
fi

if [[ -z $components ]]; then
  [[ -t 0 && -t 1 ]] || { echo 'Interactive mode requires a TTY' >&2; exit 2; }
  [[ $EUID -eq 0 ]] || { echo 'Run as root (sudo ./bootstrap.sh)' >&2; exit 1; }
  [[ -r /etc/os-release ]] || { echo 'Cannot identify the OS' >&2; exit 1; }
  # shellcheck source=/dev/null
  source /etc/os-release
  [[ $ID == debian && ( $VERSION_ID == 12 || $VERSION_ID == 13 ) ]] || {
    echo 'Debian 12 or 13 is required' >&2; exit 1;
  }
  if ! command -v gum >/dev/null 2>&1; then
    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get install -y ca-certificates curl gnupg
    install -d -m 0755 /etc/apt/keyrings
    curl -fsSL https://repo.charm.sh/apt/gpg.key | gpg --dearmor -o /etc/apt/keyrings/charm.gpg
    chmod 0644 /etc/apt/keyrings/charm.gpg
    printf '%s\n' 'deb [signed-by=/etc/apt/keyrings/charm.gpg] https://repo.charm.sh/apt/ * *' \
      >/etc/apt/sources.list.d/charm.list
    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get install -y gum
  fi
  choices=(base github_cli tailscale codex nodejs devtools)
  if [[ $platform == vm ]]; then
    choices+=(docker qemu_guest_agent)
  elif [[ $platform == baremetal ]]; then
    choices+=(docker)
  fi
  printf 'Detected platform: %s\n' "$platform"
  selection=$(printf '%s\n' "${choices[@]}" | gum choose --no-limit --header 'Install components (Space to select, Enter to continue)')
  [[ -n $selection ]] || { echo 'No components selected' >&2; exit 1; }
  components=$(printf '%s\n' "$selection" | paste -sd, -)
fi

if [[ $components == ,* || $components == *, || $components == *,,* ]]; then
  echo 'Empty component in --components' >&2
  exit 2
fi
IFS=, read -r -a requested <<<"$components"
((${#requested[@]} > 0)) || { echo 'No components selected' >&2; exit 2; }
declare -A seen=()
selected=()
for item in "${requested[@]}"; do
  valid_component "$item" || { echo "Unknown component: $item" >&2; exit 2; }
  if [[ $item == qemu_guest_agent && $platform != vm ]]; then
    echo 'qemu_guest_agent requires --platform vm' >&2; exit 2
  fi
  if [[ $item == docker && $platform == lxc ]]; then
    echo 'Docker is not supported by this bootstrap on LXC' >&2; exit 2
  fi
  if [[ -z ${seen[$item]+yes} ]]; then
    selected+=("$item")
    seen[$item]=1
  fi
done
components=$(IFS=,; echo "${selected[*]}")

printf 'Platform: %s\nComponents: %s\n' "$platform" "$components"
if ((dry_run)); then
  exit 0
fi
if [[ $platform == lxc && ,$components, == *,tailscale,* && ! -e /dev/net/tun ]]; then
  echo 'Tailscale on LXC requires /dev/net/tun passed through from Proxmox (see docs/proxmox.md).' >&2
  exit 1
fi
if ((!non_interactive)); then
  gum confirm 'Apply this configuration?' || { echo 'Cancelled'; exit 1; }
fi

[[ $EUID -eq 0 ]] || { echo 'Run as root (sudo ./bootstrap.sh)' >&2; exit 1; }
# shellcheck source=/dev/null
source /etc/os-release
[[ $ID == debian && ( $VERSION_ID == 12 || $VERSION_ID == 13 ) ]] || {
  echo 'Debian 12 or 13 is required' >&2; exit 1;
}

script_dir=
if [[ -n ${BASH_SOURCE[0]-} ]]; then
  script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
fi
temp_dir=
cleanup() { [[ -z $temp_dir ]] || rm -rf -- "$temp_dir"; }
trap cleanup EXIT
if [[ -n $script_dir && -f $script_dir/playbook.yml && -d $script_dir/roles ]]; then
  project_dir=$script_dir
else
  [[ -n $repo ]] || { echo '--repo OWNER/NAME is required outside a checkout' >&2; exit 2; }
  command -v curl >/dev/null || { echo 'curl is required to fetch the repository' >&2; exit 1; }
  temp_dir=$(mktemp -d)
  curl -fsSL --retry 3 "https://github.com/$repo/archive/refs/tags/$ref.tar.gz" \
    -o "$temp_dir/source.tar.gz"
  mkdir "$temp_dir/source"
  tar -xzf "$temp_dir/source.tar.gz" --strip-components=1 -C "$temp_dir/source"
  project_dir=$temp_dir/source
fi

if ! command -v ansible-playbook >/dev/null 2>&1; then
  apt-get update
  DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends ansible-core
fi
if ! dpkg-query -W -f='${Status}' python3-apt 2>/dev/null | grep -qx 'install ok installed'; then
  apt-get update
  DEBIAN_FRONTEND=noninteractive apt-get install -y python3-apt
fi

cd "$project_dir"
ansible-playbook -i localhost, -c local playbook.yml \
  --tags "$components" --extra-vars "bootstrap_platform=$platform"

echo 'Bootstrap complete. Register Tailscale and sign in to Codex on this machine if selected.'
