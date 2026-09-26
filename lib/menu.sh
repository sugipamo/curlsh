#!/usr/bin/env bash
# No menu dependency is installed. Existing gum is optional; Bash is the fallback.

choose_components() {
  local id selection
  local -a choices=()
  for id in "${component_ids[@]}"; do
    component_supported "$id" || continue
    probe_component "$id"
    choices+=("$id | ${component_labels[$id]} | ${observed_state[$id]}: ${observed_detail[$id]:0:80}")
  done
  printf 'Detected platform: %s\n' "$platform"
  printf 'Selection does not install menu tools or change APT sources.\n'
  if command -v gum >/dev/null 2>&1; then
    selection=$(printf '%s\n' "${choices[@]}" |
      gum choose --no-limit --header 'Install components (Space: select, Enter: continue)') || return 1
    [[ -n $selection ]] || return 1
    requested=()
    while IFS= read -r id; do requested+=("${id%% | *}"); done <<<"$selection"
  else
    printf '%s\n' "${choices[@]}"
    printf 'Enter comma-separated component IDs (example: base,codex), or leave blank to cancel: '
    IFS= read -r selection || return 1
    [[ -n $selection ]] || return 1
    if [[ $selection == ,* || $selection == *, || $selection == *,,* ]]; then
      echo 'Empty component in selection' >&2
      return 1
    fi
    IFS=, read -r -a requested <<<"$selection"
  fi
}

confirm_installation() {
  local answer
  printf '\nNo installation has started. Approve the plan, including execution dependencies?\n'
  printf 'Type yes to begin system changes; anything else cancels: '
  IFS= read -r answer || return 1
  [[ $answer == yes ]]
}
