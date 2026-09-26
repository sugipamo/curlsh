#!/usr/bin/env bash
set -Eeuo pipefail

usage() {
  cat <<'EOF'
Usage: bootstrap.sh [--platform auto|lxc|vm|baremetal] [--components LIST]
                    [--non-interactive] [--dry-run] [--repo OWNER/NAME] [--ref TAG]
       bootstrap.sh --status|--check|--check-updates [--platform ...] [--components LIST]

Components: base,github_cli,tailscale,codex,docker,nodejs,devtools,qemu_guest_agent

--status         Read installed packages, command versions and service status.
--check          Check prerequisites and selected HTTPS endpoints without installing.
--check-updates  Compare installed versions with cached APT candidates / Codex releases.
                 Does NOT refresh APT indexes or apply updates.
--dry-run        Validate arguments and show the selection without installing.

Read-only modes default to all components supported on the selected platform.
Non-interactive installation requires --components; interactive installation needs a TTY.
A standalone script fetches the repository archive at --ref (default: v0.2.0).
EOF
}

platform=auto components='' repo=sugipamo/curlsh ref=v0.2.0 mode=install
non_interactive=0 dry_run=0
while (($#)); do
  case "$1" in
    --platform|--components|--repo|--ref)
      if (($# < 2)) || [[ -z ${2-} || ${2-} == --* ]]; then
        echo "Missing value for $1" >&2; exit 2
      fi
      case "$1" in
        --platform) platform=$2 ;;
        --components) components=$2 ;;
        --repo) repo=$2 ;;
        --ref) ref=$2 ;;
      esac
      shift 2 ;;
    --status|--check|--check-updates)
      [[ $mode == install ]] || { echo 'Choose only one diagnostic mode' >&2; exit 2; }
      mode=${1#--}; shift ;;
    --non-interactive) non_interactive=1; shift ;;
    --dry-run) dry_run=1; shift ;;
    --help|-h) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

[[ $repo =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || { echo 'Invalid --repo' >&2; exit 2; }
[[ $ref =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo 'Use a fixed vX.Y.Z tag for --ref' >&2; exit 2; }
case "$platform" in auto|lxc|vm|baremetal) ;; *) echo 'Invalid platform' >&2; exit 2 ;; esac
if [[ $platform == auto ]]; then
  virt=$(systemd-detect-virt 2>/dev/null || true)
  case "$virt" in
    lxc|openvz|systemd-nspawn) platform=lxc ;;
    kvm|qemu|vmware|microsoft|oracle|xen) platform=vm ;;
    docker|podman) echo 'Container runtime detected; specify --platform explicitly' >&2; exit 2 ;;
    *) platform=baremetal ;;
  esac
fi
if [[ $mode != install ]] && ((dry_run || non_interactive)); then
  echo 'Diagnostic modes do not need --dry-run or --non-interactive' >&2; exit 2
fi
if [[ $mode == install ]]; then
  if ((non_interactive || dry_run)); then
    [[ -n $components ]] || { echo '--non-interactive / --dry-run requires --components' >&2; exit 2; }
  elif [[ -n $components ]]; then
    echo 'Use --non-interactive with --components for installation' >&2; exit 2
  fi
fi
if [[ $components == ,* || $components == *, || $components == *,,* ]]; then
  echo 'Empty component in --components' >&2; exit 2
fi

# Resolve the entire project before loading its helpers. Never use the current
# directory as a checkout when the bootstrap itself was received on stdin.
script_dir='' checkout_entrypoint='' temp_dir=''
if [[ -n ${BASH_SOURCE[0]-} ]]; then
  script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
fi
cleanup() { [[ -z $temp_dir ]] || rm -rf -- "$temp_dir"; }
trap cleanup EXIT
if [[ -n $script_dir && -f $script_dir/playbook.yml && -d $script_dir/lib ]]; then
  project_dir=$script_dir
  checkout_entrypoint=$script_dir/bootstrap.sh
else
  command -v curl >/dev/null || { echo 'curl is required to fetch the repository' >&2; exit 1; }
  temp_dir=$(mktemp -d)
  curl -fsSL --retry 3 --connect-timeout 5 --max-time 60 \
    "https://github.com/$repo/archive/refs/tags/$ref.tar.gz" -o "$temp_dir/source.tar.gz"
  mkdir "$temp_dir/source"
  tar -xzf "$temp_dir/source.tar.gz" --strip-components=1 -C "$temp_dir/source"
  project_dir=$temp_dir/source
  [[ -d $project_dir/lib ]] || { echo 'This bootstrap requires its matching release archive' >&2; exit 1; }
fi
# shellcheck source=lib/components.sh
source "$project_dir/lib/components.sh"
# shellcheck source=lib/diagnostics.sh
source "$project_dir/lib/diagnostics.sh"
# shellcheck source=lib/updates.sh
source "$project_dir/lib/updates.sh"
codex_target=$(sed -n "s/^codex_version: '\([^']*\)'$/\1/p" "$project_dir/vars/versions.yml")
[[ $codex_target =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo 'Invalid Codex version metadata' >&2; exit 1; }

if [[ $mode == install && -z $components ]]; then
  [[ -t 0 && -t 1 ]] || { echo 'Interactive mode requires a TTY' >&2; exit 2; }
  [[ $EUID -eq 0 ]] || { echo 'Run installation as root (sudo ./bootstrap.sh)' >&2; exit 1; }
  require_target_os || { echo 'Debian 12 or 13 is required' >&2; exit 1; }
  if ! command -v gum >/dev/null 2>&1; then
    echo 'Installing menu prerequisites: ca-certificates, curl, gnupg and gum.'
    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get install -y ca-certificates curl gnupg
    install -d -m 0755 /etc/apt/keyrings
    curl -fsSL https://repo.charm.sh/apt/gpg.key |
      gpg --batch --yes --dearmor -o /etc/apt/keyrings/charm.gpg
    chmod 0644 /etc/apt/keyrings/charm.gpg
    printf '%s\n' 'deb [signed-by=/etc/apt/keyrings/charm.gpg] https://repo.charm.sh/apt/ * *' \
      >/etc/apt/sources.list.d/charm.list
    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get install -y gum
  fi
  choices=()
  for item in "${component_ids[@]}"; do
    component_supported "$item" || continue
    probe_component "$item"
    choices+=("$item | ${component_labels[$item]} | ${observed_state[$item]}: ${observed_detail[$item]:0:80}")
  done
  printf 'Detected platform: %s\n' "$platform"
  selection=$(printf '%s\n' "${choices[@]}" |
    gum choose --no-limit --header 'Install components (Space: select, Enter: continue)')
  [[ -n $selection ]] || { echo 'No components selected' >&2; exit 1; }
  requested=()
  while IFS= read -r item; do requested+=("${item%% | *}"); done <<<"$selection"
else
  if [[ -n $components ]]; then
    IFS=, read -r -a requested <<<"$components"
  else
    requested=()
    for item in "${component_ids[@]}"; do
      component_supported "$item" && requested+=("$item")
    done
  fi
fi

declare -A seen=()
selected=()
for item in "${requested[@]}"; do
  valid_component "$item" || { echo "Unknown component: $item" >&2; exit 2; }
  component_supported "$item" || { echo "$item is not supported on $platform" >&2; exit 2; }
  if [[ -z ${seen[$item]+yes} ]]; then
    selected+=("$item"); seen[$item]=1
  fi
done
(("${#selected[@]}")) || { echo 'No components selected' >&2; exit 2; }
components=$(IFS=,; echo "${selected[*]}")
printf 'Platform: %s\nComponents: %s\n' "$platform" "$components"
((dry_run == 0)) || exit 0

case "$mode" in
  status) show_status "${selected[@]}"; print_next_steps "${selected[@]}"; exit 0 ;;
  check) preflight "${selected[@]}"; exit $? ;;
  check-updates) check_updates "${selected[@]}"; exit $? ;;
esac

[[ $EUID -eq 0 ]] || { echo 'Run installation as root (sudo ./bootstrap.sh)' >&2; exit 1; }
preflight "${selected[@]}" || exit 1
show_status "${selected[@]}"
if ((!non_interactive)); then
  gum confirm 'Apply this configuration?' || { echo 'Cancelled'; exit 1; }
fi
tooling=()
command -v ansible-playbook >/dev/null || tooling+=(ansible-core)
package_version python3-apt >/dev/null || tooling+=(python3-apt)
if (("${#tooling[@]}")); then
  apt-get update
  DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "${tooling[@]}"
fi
cd "$project_dir"
install_result=0
ansible-playbook -i localhost, -c local playbook.yml \
  --tags "$components" --extra-vars "bootstrap_platform=$platform" || install_result=$?
verify_result=0
verify_selected "${selected[@]}" || verify_result=$?
if ((install_result)); then
  printf '\nInstallation failed (Ansible exit %s). Inspect the task error above; successful checks do not mean installation completed.\n' "$install_result" >&2
  exit "$install_result"
fi
if ((verify_result)); then
  echo 'Installation tasks finished, but verification found an issue.' >&2
  exit "$verify_result"
fi
echo 'Bootstrap complete; command/service checks passed.'
