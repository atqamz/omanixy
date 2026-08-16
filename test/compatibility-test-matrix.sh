#!/usr/bin/env bash
set -euo pipefail

repo=${1:?repository path required}
compat_root=${2:?compatibility root path required}
manifest=${3:?test matrix path required}
runtime_bin=${4:?built runtime helper bin required}
test_root=$(mktemp -d)
trap 'rm -rf "$test_root"' EXIT

output="$test_root/compat-adapters.log"
bash "$repo/test/compat-adapters.sh" "$repo" "$compat_root" "$runtime_bin" >"$output"
grep '^CASE' "$output" | cut -f2- | sort -u > "$test_root/actual"

jq -e --arg actual "$test_root/actual" '
  .helpers
  | to_entries
  | all(.[];
      .value.tests
      | to_entries
      | all(.[]; .value == true or .value == "not-applicable" or .value == "reference-only"))
' "$manifest" >/dev/null

jq -r '.helpers | to_entries[] | .key as $helper | .value.tests | to_entries[] | select(.value == true) | "\($helper)\t\(.key)"' "$manifest" | sort > "$test_root/expected"
if ! cmp -s "$test_root/expected" "$test_root/actual"; then
  diff -u "$test_root/expected" "$test_root/actual" >&2 || true
  printf '%s\n' 'compatibility test matrix is not covered by executed named cases' >&2
  exit 1
fi

printf '%s\n' 'compatibility test matrix passed'
