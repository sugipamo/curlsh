#!/usr/bin/env bash
set -Eeuo pipefail
repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
fixture_dir=$(mktemp -d)
trap 'rm -rf -- "$fixture_dir"' EXIT
mkdir "$fixture_dir/bin" "$fixture_dir/bundle" "$fixture_dir/tmp"
cp -a "$repo_dir/bootstrap.sh" "$repo_dir/playbook.yml" "$repo_dir/vars" \
  "$repo_dir/lib" "$repo_dir/roles" "$repo_dir/docs" "$fixture_dir/bundle/"
tar -czf "$fixture_dir/source.tar.gz" -C "$fixture_dir" bundle
ln -s "$repo_dir/tests/fixtures/curl-source" "$fixture_dir/bin/curl"
cp "$repo_dir/bootstrap.sh" "$fixture_dir/standalone.sh"
export CURLSH_TEST_ARCHIVE="$fixture_dir/source.tar.gz"
export CURLSH_TEST_FETCH_MARKER="$fixture_dir/fetch-marker"
export PATH="$fixture_dir/bin:$PATH"
export TMPDIR="$fixture_dir/tmp"
cd "$repo_dir"
for invocation in file stdin; do
  if [[ $invocation == file ]]; then
    output=$(bash "$fixture_dir/standalone.sh" --status --platform lxc --components codex)
  else
    output=$(bash -s -- --status --platform lxc --components codex <"$repo_dir/bootstrap.sh")
  fi
  [[ $output == *'https://raw.githubusercontent.com/sugipamo/curlsh/v0.2.0/bootstrap.sh'* ]]
  [[ $output != *"$fixture_dir"* ]]
  if [[ $invocation == file ]]; then
    output=$(bash "$fixture_dir/standalone.sh" --dry-run --platform lxc --components base,codex)
  else
    output=$(bash -s -- --dry-run --platform lxc --components base,codex <"$repo_dir/bootstrap.sh")
  fi
  [[ $output == *'Source: sugipamo/curlsh at v0.2.0'* ]]
  [[ $output == *'## codex - Codex CLI'* && $output == *'Dry-run complete.'* ]]
  [[ $output != *"$fixture_dir"* ]]
done
[[ $(wc -l <"$fixture_dir/fetch-marker") -eq 4 ]]
[[ -z $(find "$TMPDIR" -mindepth 1 -print -quit) ]]

# Catch mismatched/old tag archives instead of silently using the current checkout.
tar -czf "$fixture_dir/old.tar.gz" -C "$fixture_dir" bundle/bootstrap.sh bundle/playbook.yml
export CURLSH_TEST_ARCHIVE="$fixture_dir/old.tar.gz"
if output=$(bash "$fixture_dir/standalone.sh" --status --platform lxc --components base 2>&1); then
  echo 'An archive without matching helpers must fail' >&2; exit 1
fi
[[ $output == *'matching release archive'* ]]
echo 'standalone and piped bootstrap fetch checks passed'
