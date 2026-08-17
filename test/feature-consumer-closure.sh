#!/usr/bin/env bash
set -euo pipefail

: "${1:?repository path required}"
pinned_source=${2:?pinned source path required}
full_root=${3:?full compatibility root path required}
full_bin=${4:?full compatibility bin path required}
weather_root=${5:?weather compatibility root path required}
weather_bin=${6:?weather compatibility bin path required}
clipboard_root=${7:?clipboard compatibility root path required}
clipboard_bin=${8:?clipboard compatibility bin path required}
core_root=${9:?core compatibility root path required}
core_bin=${10:?core compatibility bin path required}
checker=${11:?feature consumer checker required}
test_root=$(mktemp -d)
trap 'rm -rf "$test_root"' EXIT

output="$test_root/evidence.json"
"${PYTHON:-python3}" "$checker" "$full_root" "$pinned_source" \
  "$full_bin/runtime-surface.json" "$full_bin/feature-surface.json" "$output"
jq -e '.selectedFeatures | index("weather") != null' "$output" >/dev/null
jq -e '.evidence | any(.[]; .consumerFeature == "weather" and .helper == "omarchy-notification-send")' \
  "$output" >/dev/null
jq -e '."omarchy-capture-screenshot".referenceSources | map(.path) == ["default/omarchy/omarchy-menu.jsonc"]' \
  "$full_bin/runtime-surface.json" >/dev/null

missing_surface="$test_root/missing-runtime.json"
jq '."omarchy-shell".consumer = "shell/missing.qml"' \
  "$full_bin/runtime-surface.json" > "$missing_surface"
if "${PYTHON:-python3}" "$checker" "$full_root" "$pinned_source" \
  "$missing_surface" "$full_bin/feature-surface.json" "$test_root/missing.json" \
  >"$test_root/missing-output" 2>"$test_root/missing-error"; then
  printf '%s\n' 'feature consumer closure accepted a missing declared consumer' >&2
  exit 1
fi
grep -Fq 'declared post-patch consumer is missing: shell/missing.qml' "$test_root/missing-error"
printf '%s\n' 'REJECTED missing declared post-patch consumer'

mutated_root="$test_root/mutated-root"
cp -R -- "$weather_root" "$mutated_root"
chmod -R u+w "$mutated_root"
printf '%s\n' 'root.bar.run("omarchy-audio-output-sink")' \
  >> "$mutated_root/shell/plugins/panels/weather/BarWidget.qml"
if "${PYTHON:-python3}" "$checker" "$mutated_root" "$pinned_source" \
  "$weather_bin/runtime-surface.json" "$weather_bin/feature-surface.json" "$test_root/mutated.json" \
  >"$test_root/mutated-output" 2>"$test_root/mutated-error"; then
  printf '%s\n' 'feature consumer closure accepted an undeclared weather-to-audio dependency' >&2
  exit 1
fi
grep -Fq 'requires omarchy-audio-output-sink (audio)' "$test_root/mutated-error"
printf '%s\n' 'REJECTED known cross-feature helper without dependency edge'

unknown_fixture="$test_root/unknown-helper-root"
cp -R -- "$weather_root" "$unknown_fixture"
chmod -R u+w "$unknown_fixture"
printf '%s\n' 'root.bar.run("omarchy-undeclared-helper")' \
  >> "$unknown_fixture/shell/plugins/panels/weather/BarWidget.qml"
if "${PYTHON:-python3}" "$checker" "$unknown_fixture" "$pinned_source" \
  "$weather_bin/runtime-surface.json" "$weather_bin/feature-surface.json" "$test_root/unknown.json" \
  >"$test_root/unknown-output" 2>"$test_root/unknown-error"; then
  printf '%s\n' 'feature consumer closure accepted an unknown helper' >&2
  exit 1
fi
grep -Fq 'references helpers without feature identities: omarchy-undeclared-helper' "$test_root/unknown-error"
printf '%s\n' 'REJECTED unknown helper without feature identity'

if ! "${PYTHON:-python3}" "$checker" "$clipboard_root" "$pinned_source" \
  "$clipboard_bin/runtime-surface.json" "$clipboard_bin/feature-surface.json" "$test_root/clipboard.json" \
  2>"$test_root/clipboard-error"; then
  cat "$test_root/clipboard-error" >&2
  exit 1
fi
jq -e '.selectedFeatures == ["clipboard", "core"]' "$test_root/clipboard.json" >/dev/null

if ! "${PYTHON:-python3}" "$checker" "$core_root" "$pinned_source" \
  "$core_bin/runtime-surface.json" "$core_bin/feature-surface.json" "$test_root/core.json" \
  2>"$test_root/core-error"; then
  cat "$test_root/core-error" >&2
  exit 1
fi
jq -e '.selectedFeatures == ["core"]' "$test_root/core.json" >/dev/null

printf '%s\n' 'feature consumer closure passed'
