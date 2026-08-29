#!/usr/bin/env bash
set -euo pipefail

repo=${1:?repository path required}
pinned_source=${2:?pinned source path required}
compatibility_root=${3:?compatibility root path required}
compatibility_bin=${4:?compatibility bin path required}
compatibility_probes=${5:?compatibility probes path required}
manifest=$repo/upstream/compatibility-contracts.json
snapshot=$repo/upstream/quattro-contracts.json
checker=$repo/scripts/check-contract-closure
test_script=$repo/test/compat-adapters.sh
adapter=$repo/packages/omanixy-shell/compat-adapter.bash
auditor=$repo/scripts/audit-quattro-contracts
test_root=$(mktemp -d)
trap 'rm -rf "$test_root"' EXIT
checker_error=$test_root/checker-error

snapshot_a=$test_root/a.json
snapshot_b=$test_root/b.json
"${PYTHON:-python3}" "$repo/scripts/audit-quattro-contracts" "$pinned_source" > "$snapshot_a"
"${PYTHON:-python3}" "$repo/scripts/audit-quattro-contracts" "$pinned_source" > "$snapshot_b"
cmp "$snapshot_a" "$snapshot_b"
cmp "$snapshot_a" "$snapshot"

checker_probes=$compatibility_probes
jq -e '.helpers | index("omarchy-remove-launcher-entry") | not' \
  "$compatibility_probes/probe-surface.json" >/dev/null
jq -e '.["omarchy-remove-launcher-entry"].consumerProbe.invocation == "omitted-headless"' \
  "$compatibility_bin/runtime-surface.json" >/dev/null

run_checker() {
  "${PYTHON:-python3}" "$checker" "$repo" "$pinned_source" "$1" "$compatibility_bin" "$checker_probes" "${OMANIXY_RUNTIME:?selected runtime required}" "$2" "$snapshot" "$3" "$adapter" "$auditor" 2>"$checker_error"
}

fake_quickshell=$test_root/fake-quickshell
printf '%s\n' \
  '#!/bin/sh' \
  'set -eu' \
  'printf "%s\\n" "INFO: Configuration Loaded" "WARN: Failed to create wl_display (No such file or directory)" >&2' \
  'printf "%s\\n" "$OMANIXY_PROBE_HELPER" > "$OMANIXY_CONSUMER_MARKER.$OMANIXY_PROBE_HELPER"' \
  > "$fake_quickshell"
chmod u+x "$fake_quickshell"

prepare_probe_copy() {
  local destination=$1
  cp -R -- "$compatibility_probes" "$destination"
  chmod -R u+w "$destination"
  for probe in "$destination"/bin/omanixy-consumer-*; do
    sed -i "s|timeout 14s \".*\" -n -p|timeout 14s \"$fake_quickshell\" -n -p|" "$probe"
  done
}

noisy_probes=$test_root/noisy-probes
prepare_probe_copy "$noisy_probes"
checker_probes=$noisy_probes
if ! run_checker "$compatibility_root" "$manifest" "$test_script" > "$test_root/noisy-output"; then
  printf '%s\n' 'contract closure rejected a correct marker with Quickshell diagnostic output' >&2
  cat "$checker_error" >&2
  exit 1
fi
printf '%s\n' 'ACCEPTED\tcorrect dispatcher marker with Quickshell diagnostic output'

wrong_quickshell=$test_root/wrong-quickshell
printf '%s\n' \
  '#!/bin/sh' \
  'set -eu' \
  'printf "%s\\n" "INFO: Configuration Loaded" "WARN: Failed to create wl_display (No such file or directory)" >&2' \
  'printf "%s\\n" wrong-identity > "$OMANIXY_CONSUMER_MARKER.$OMANIXY_PROBE_HELPER"' \
  > "$wrong_quickshell"
chmod u+x "$wrong_quickshell"
wrong_probes=$test_root/wrong-probes
prepare_probe_copy "$wrong_probes"
for probe in "$wrong_probes"/bin/omanixy-consumer-*; do
  sed -i "s|$fake_quickshell|$wrong_quickshell|" "$probe"
done
checker_probes=$wrong_probes
if run_checker "$compatibility_root" "$manifest" "$test_script" > "$test_root/wrong-output"; then
  printf '%s\n' 'contract closure accepted an incorrect dispatcher marker' >&2
  exit 1
fi
if ! grep -Fq 'generated consumer probe failed its dispatcher marker check' "$checker_error"; then
  printf '%s\n' 'contract closure rejected the incorrect marker for an unrelated reason' >&2
  cat "$checker_error" >&2
  exit 1
fi
if ! grep -Fq 'quickshell log:' "$checker_error" || ! grep -Fq 'Failed to create wl_display' "$checker_error"; then
  printf '%s\n' 'contract closure omitted Quickshell diagnostic output from the marker failure' >&2
  cat "$checker_error" >&2
  exit 1
fi
if grep -Fq 'did not execute its consumer' "$checker_error"; then
  printf '%s\n' 'contract closure retained the misleading consumer execution diagnostic' >&2
  cat "$checker_error" >&2
  exit 1
fi
printf '%s\n' 'REJECTED\tincorrect dispatcher marker with diagnostic output'
checker_probes=$compatibility_probes

expect_rejection() {
  local description=$1 reason=$2 root=$3 mutated_manifest=$4
  if run_checker "$root" "$mutated_manifest" "$test_script" >/dev/null; then
    printf '%s\n' "contract closure accepted $description" >&2
    exit 1
  fi
  if ! grep -Fq "$reason" "$checker_error"; then
    printf '%s\n' "contract closure rejected $description for an unrelated reason" >&2
    cat "$checker_error" >&2
    exit 1
  fi
  printf 'REJECTED\t%s\t%s\n' "$description" "$reason"
}

mutated_root=$test_root/mutated-root
cp -R -- "$compatibility_root" "$mutated_root"
chmod -R u+w "$mutated_root"
chmod u+w "$mutated_root/shell/services/AppLibrary.qml"
printf '%s\n' 'command: ["omarchy-unknown-contract"]' >> "$mutated_root/shell/services/AppLibrary.qml"
expect_rejection 'referenced consumer-source drift' \
  'generated consumer identity drifted' "$mutated_root" "$manifest"

drift_manifest=$test_root/drift.json
jq '.helpers["omarchy-display-text-size"].hash = "0"' "$manifest" > "$drift_manifest"
expect_rejection 'referenced helper drift' \
  'pinned helper reference drifted' "$compatibility_root" "$drift_manifest"

native_drift_manifest=$test_root/native-drift.json
jq '.native["uwsm-app"].hash = "0"' "$manifest" > "$native_drift_manifest"
expect_rejection 'referenced native evidence drift' \
  'native reference drifted' "$compatibility_root" "$native_drift_manifest"

missing_matrix_source=$test_root/missing-matrix-cases.json
jq 'del(.helpers["omarchy-display-text-size"].tests.valid)' \
  "$repo/upstream/compatibility-test-matrix.json" > "$missing_matrix_source"
missing_matrix=$test_root/missing-matrix.json
jq --arg path "$missing_matrix_source" '.testMatrix = $path' \
  "$manifest" > "$missing_matrix"
expect_rejection 'missing per-helper matrix coverage' \
  'has no declared valid test-matrix case' "$compatibility_root" "$missing_matrix"

unledgered_root=$test_root/unledgered-root
cp -R -- "$compatibility_root" "$unledgered_root"
chmod -R u+w "$unledgered_root"
mkdir -p "$unledgered_root/shell/plugins/panels/probe"
printf '%s\n' 'Process { command: ["omarchy-unknown-contract"] }' \
  > "$unledgered_root/shell/plugins/panels/probe/Panel.qml"
expect_rejection 'a newly reachable unlisted contract' \
  'reachable contracts lack ledger disposition: omarchy-unknown-contract' \
  "$unledgered_root" "$manifest"

noise_root=$test_root/noise-root
cp -R -- "$compatibility_root" "$noise_root"
chmod -R u+w "$noise_root"
mkdir -p "$noise_root/shell/plugins/panels/probe"
printf '%s\n' 'root.bar.run("omarchy-default-browser")' \
  > "$noise_root/shell/plugins/panels/probe/Panel.qml"
expect_rejection 'a former noise helper at a new source identity' \
  'reachable contracts lack ledger disposition: omarchy-default-browser' \
  "$noise_root" "$manifest"

foreign_probes=$test_root/foreign-probes
mkdir -p "$foreign_probes/bin"
for probe in "$compatibility_probes/bin/"*; do
  ln -s "$probe" "$foreign_probes/bin/${probe##*/}"
done
jq '.compatibilityBin = "/nix/store/00000000000000000000000000000000-foreign-compatibility-bin"' \
  "$compatibility_probes/probe-surface.json" > "$foreign_probes/probe-surface.json"
checker_probes=$foreign_probes
expect_rejection 'consumer probes built against another helper surface' \
  'consumer probes were generated against a different runtime helper path' \
  "$compatibility_root" "$manifest"

jq --arg helper omarchy-network-status \
  '.helpers = (.helpers | map(select(. != $helper)))' \
  "$compatibility_probes/probe-surface.json" > "$foreign_probes/probe-surface.json"
expect_rejection 'consumer probes missing a helper' \
  'consumer probes do not cover the executable helper surface' \
  "$compatibility_root" "$manifest"
checker_probes=$compatibility_probes

printf '%s\n' 'contract closure adversarial checks passed'
