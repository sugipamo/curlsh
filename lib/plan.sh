#!/usr/bin/env bash
# These Markdown files are both the published specification and the CLI explanation.
# A plan is an explanation of scope, not a saved transaction or dependency solver.

show_change_plan() {
  local id package executable spec shared=0
  local -a specs=(runtime) packages
  for id in "$@"; do
    case "$id" in github_cli|tailscale|codex|docker) shared=1 ;; esac
  done
  ((shared == 0)) || specs+=(repository_prerequisites)
  specs+=("$@")
  # Fail before any installation if a release is missing its explanation.
  for spec in "${specs[@]}"; do
    if [[ ! -r $project_dir/docs/changes/$spec.md ]]; then
      printf 'Missing change specification: %s. Use a complete matching release.\n' "$spec" >&2
      return 1
    fi
  done

  printf '\nExecution plan (scope, not an exact diff; nothing is applied by this display)\n'
  if [[ -n $checkout_entrypoint ]]; then
    printf 'Source: local checkout %s (including local edits; --ref does not replace it).\n' "$project_dir"
  else
    printf 'Source: %s at %s (downloaded into temporary storage).\n' "$repo" "$ref"
  fi
  printf 'Specification: docs/changes/README.md in the same source.\n'
  printf 'Observation: local package metadata only; no vendor queries or tool-version probes.\n'
  for spec in "${specs[@]}"; do
    printf '\n'
    cat -- "$project_dir/docs/changes/$spec.md"
    if [[ $spec == runtime ]]; then
      if executable=$(command -v ansible-playbook); then
        printf '\nObserved: ansible-playbook available at %s; its version is not checked by this plan.\n' "$executable"
      else
        printf '\nObserved: ansible-playbook unavailable; ansible-core will be requested.\n'
      fi
      packages=(python3-apt)
    elif [[ $spec == repository_prerequisites ]]; then
      packages=(ca-certificates curl)
    elif [[ $spec == codex ]]; then
      packages=()
      printf '\nPinned Codex version: %s (a newer installed version may be downgraded).\n' "$codex_target"
      if executable=$(resolve_command codex); then
        printf 'Observed executable: %s; version/ownership not determined by this plan.\n' "$executable"
      else
        printf 'Observed executable: not found in the searched paths.\n'
      fi
    else
      read -r -a packages <<<"${component_packages[$spec]}"
    fi
    for package in "${packages[@]}"; do
      if executable=$(package_version "$package"); then
        printf 'Observed package: %s = %s\n' "$package" "$executable"
      else
        printf 'Observed package: %s = not reported installed (will be requested)\n' "$package"
      fi
    done
  done
  printf '\nNot determined: exact APT transaction, upstream installer side effects, or current preflight readiness.\n'
  printf 'Use --check separately for prerequisites/connectivity; it does not approve or apply this plan.\n'
}
