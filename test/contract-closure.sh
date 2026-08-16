#!/usr/bin/env bash
set -euo pipefail

repo=${1:?repository path required}
pinned_source=${2:?pinned source path required}
compatibility_root=${3:?compatibility root path required}
compatibility_bin=${4:?compatibility bin path required}
manifest=$repo/upstream/compatibility-contracts.json
snapshot=$repo/upstream/quattro-contracts.json
checker=$repo/scripts/check-contract-closure
test_script=$repo/test/compat-adapters.sh
adapter=$repo/packages/omanixy-shell/compat-adapter.bash
auditor=$repo/scripts/audit-quattro-contracts
test_root=$(mktemp -d)
trap 'rm -rf "$test_root"' EXIT

snapshot_a=$test_root/a.json
snapshot_b=$test_root/b.json
"${PYTHON:-python3}" "$repo/scripts/audit-quattro-contracts" "$pinned_source" > "$snapshot_a"
"${PYTHON:-python3}" "$repo/scripts/audit-quattro-contracts" "$pinned_source" > "$snapshot_b"
cmp "$snapshot_a" "$snapshot_b"
cmp "$snapshot_a" "$snapshot"

run_checker() {
  "${PYTHON:-python3}" "$checker" "$repo" "$pinned_source" "$1" "$compatibility_bin" "$2" "$snapshot" "$3" "$adapter" "$auditor"
}

mutated_root=$test_root/mutated-root
cp -R -- "$compatibility_root" "$mutated_root"
chmod -R u+w "$mutated_root"
chmod u+w "$mutated_root/shell/services/AppLibrary.qml"
printf '%s\n' 'command: ["omarchy-unknown-contract"]' >> "$mutated_root/shell/services/AppLibrary.qml"
if run_checker "$mutated_root" "$manifest" "$test_script"; then
  printf '%s\n' 'contract closure accepted an unledgered reachable helper' >&2
  exit 1
fi

drift_manifest=$test_root/drift.json
jq '.helpers["omarchy-display-text-size"].hash = "0"' "$manifest" > "$drift_manifest"
if run_checker "$compatibility_root" "$drift_manifest" "$test_script"; then
  printf '%s\n' 'contract closure accepted referenced helper drift' >&2
  exit 1
fi

native_drift_manifest=$test_root/native-drift.json
jq '.native["uwsm-app"].hash = "0"' "$manifest" > "$native_drift_manifest"
if run_checker "$compatibility_root" "$native_drift_manifest" "$test_script"; then
  printf '%s\n' 'contract closure accepted referenced native evidence drift' >&2
  exit 1
fi

missing_matrix=$test_root/missing-matrix.json
jq '.helpers["omarchy-display-text-size"].tests.valid = false' \
  "$manifest" > "$missing_matrix"
if run_checker "$compatibility_root" "$missing_matrix" "$test_script"; then
  printf '%s\n' 'contract closure accepted missing per-helper matrix coverage' >&2
  exit 1
fi

printf '%s\n' 'contract closure adversarial checks passed'
