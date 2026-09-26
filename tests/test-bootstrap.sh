#!/usr/bin/env bash
set -Eeuo pipefail

repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
shellcheck "$repo_dir/bootstrap.sh" "$repo_dir/tests/test-bootstrap.sh"

output=$(
  "$repo_dir/bootstrap.sh" --dry-run --non-interactive --platform vm \
    --components base,codex,qemu_guest_agent,codex
)
[[ $output == *'Platform: vm'* ]]
[[ $output == *'Components: base,codex,qemu_guest_agent'* ]]

if "$repo_dir/bootstrap.sh" --dry-run --non-interactive --platform lxc \
  --components docker >/dev/null 2>&1; then
  echo 'Docker on LXC should fail' >&2
  exit 1
fi

if "$repo_dir/bootstrap.sh" --dry-run --non-interactive --platform vm \
  --components invalid >/dev/null 2>&1; then
  echo 'Unknown component should fail' >&2
  exit 1
fi

for invalid_args in \
  '--platform lxc --components qemu_guest_agent' \
  '--platform vm --components base,' \
  '--platform vm --components base,,codex' \
  '--platform vm --components base --repo invalid' \
  '--platform vm'; do
  # These arguments contain no spaces within a value.
  read -r -a args <<<"$invalid_args"
  if "$repo_dir/bootstrap.sh" --dry-run --non-interactive "${args[@]}" >/dev/null 2>&1; then
    echo "Unexpectedly accepted: $invalid_args" >&2
    exit 1
  fi
done

echo 'bootstrap argument checks passed'
