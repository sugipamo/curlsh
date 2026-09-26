#!/usr/bin/env bash

apt_candidate() {
  local policy
  policy=$(LC_ALL=C apt-cache policy "$1" 2>/dev/null) || return 1
  printf '%s\n' "$policy" | awk '$1 == "Candidate:" {print $2}'
}

latest_codex_version() {
  command -v curl >/dev/null && command -v python3 >/dev/null || return 1
  curl --proto '=https' --connect-timeout 5 --max-time 15 -fsSL \
    https://releases.openai.com/codex/channels/latest |
    python3 -c 'import json,re,sys
tag = json.load(sys.stdin).get("tag_name", "")
if not re.fullmatch(r"rust-v[0-9]+\.[0-9]+\.[0-9]+", tag):
    sys.exit("Unrecognized Codex release metadata")
print(tag.removeprefix("rust-v"))'
}

check_updates() {
  local id package installed candidate version latest errors=0 codex_pinned_update=0
  local -A seen_packages=()
  local -a packages upgrade_packages=()
  printf '\nUpdate check: no packages, services or APT indexes will be changed.\n'
  printf 'APT results use cached indexes. For fresh results, run as root: apt-get update\n'
  printf '%-24s %-24s %-24s %s\n' PACKAGE INSTALLED CANDIDATE RESULT
  for id in "$@"; do
    if [[ $id == codex ]]; then
      if version=$(read_command_version codex); then
        installed=${version#codex-cli }
        if [[ ! $installed =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
          printf 'UNKNOWN codex: unrecognized installed version\n'
          errors=$((errors + 1))
          continue
        fi
        printf '%-24s %-24s %-24s ' codex "$installed" "$codex_target"
        if dpkg --compare-versions "$installed" lt "$codex_target"; then
          printf 'pinned update available\n'
          codex_pinned_update=1
        elif dpkg --compare-versions "$installed" gt "$codex_target"; then
          printf 'installed is newer than the pin; reinstall would downgrade it\n'
        else
          printf 'matches curlsh pin\n'
        fi
        if latest=$(latest_codex_version 2>/dev/null); then
          printf 'Codex upstream stable: %s (curlsh pin: %s).\n' "$latest" "$codex_target"
          if dpkg --compare-versions "$latest" gt "$codex_target"; then
            printf 'A newer upstream version exists. Use a curlsh release with a reviewed pin before updating through curlsh.\n'
          fi
        else
          printf 'UNKNOWN codex upstream: need curl + python3 and access to releases.openai.com; retry --check-updates.\n'
          errors=$((errors + 1))
        fi
      else
        if resolve_command codex >/dev/null; then
          printf 'UNKNOWN codex: an executable exists but its version check failed; inspect --status.\n'
          errors=$((errors + 1))
        else
          printf '%-24s %-24s %-24s %s\n' codex 'not installed' "$codex_target" 'not checked'
        fi
      fi
      continue
    fi
    read -r -a packages <<<"${component_packages[$id]}"
    for package in "${packages[@]}"; do
      [[ -z ${seen_packages[$package]+yes} ]] || continue
      seen_packages[$package]=1
      if ! installed=$(package_version "$package"); then
        printf '%-24s %-24s %-24s %s\n' "$package" 'not installed' '-' 'not checked'
        continue
      fi
      candidate=$(apt_candidate "$package") || candidate=
      printf '%-24s %-24s %-24s ' "$package" "$installed" "${candidate:--}"
      if [[ -z $candidate || $candidate == '(none)' ]]; then
        printf 'UNKNOWN: refresh APT indexes and check the repository\n'
        errors=$((errors + 1))
      elif dpkg --compare-versions "$candidate" gt "$installed"; then
        printf 'update available\n'
        upgrade_packages+=("$package")
      else
        printf 'no newer cached candidate\n'
      fi
    done
  done
  if (("${#upgrade_packages[@]}")); then
    printf '\nTo review and apply the listed APT upgrades, run as root:\n'
    print_command apt-get install --only-upgrade "${upgrade_packages[@]}"
  fi
  if ((codex_pinned_update)); then
    printf '\nTo install the reviewed Codex pin, run as root:\n'
    components=codex followup_command --non-interactive
  fi
  printf '\nTo repeat this check after refreshing APT indexes:\n'
  followup_command --check-updates
  ((errors == 0))
}
