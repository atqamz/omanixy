#!/usr/bin/env bash
set -euo pipefail

manifest=${1:?compatibility manifest required}
runtime_paths=${2:?feature runtime path map required}

test "$(jq '[.externalExecutableCapabilities | to_entries[] | select(.key == "pacman" or .value == "host")] | length' "$manifest")" = 0

runtime_path() {
  sed -n 's/^export PATH="\(.*\)"$/\1/p' "$1/bin/omanixy-shell-runtime"
}

while IFS=$'\t' read -r executable feature; do
  if [ "$feature" = host ]; then
    printf 'unsupported host executable capability=%s executable=%s\n' "$feature" "$executable" >&2
    exit 1
  fi
  runtime=$(jq -er --arg feature "$feature" '.[$feature]' "$runtime_paths")
  if ! PATH="$(runtime_path "$runtime")" command -v "$executable" >/dev/null; then
    printf 'missing executable=%s feature=%s runtime=%s\n' "$executable" "$feature" "$runtime" >&2
    exit 1
  fi
done < <(jq -r '.externalExecutableCapabilities | to_entries[] | [.key, .value] | @tsv' "$manifest")

printf '%s\n' 'feature runtime inputs match canonical executable ownership'
