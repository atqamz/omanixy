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
launcher_root=${11:?launcher compatibility root required}
launcher_bin=${12:?launcher compatibility bin required}
screenshot_root=${13:?screenshot compatibility root required}
screenshot_bin=${14:?screenshot compatibility bin required}
checker=${15:?feature consumer checker required}
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
grep -Fq 'requires omarchy-audio-output-sink (audio-control)' "$test_root/mutated-error"
printf '%s\n' 'REJECTED known cross-feature helper without dependency edge'

unregistered_source="$test_root/unregistered-source-root"
cp -R -- "$weather_root" "$unregistered_source"
chmod -R u+w "$unregistered_source"
test -f "$unregistered_source/shell/plugins/panels/weather/Model.js"
if jq -e --arg path 'shell/plugins/panels/weather/Model.js' \
  'any(.[]; any(.consumerSources[]?; .path == $path) or .consumer == $path)' \
  "$weather_bin/runtime-surface.json" >/dev/null; then
  printf '%s\n' 'weather Panel.qml unexpectedly has existing runtime-surface consumer evidence' >&2
  exit 1
fi
printf '%s\n' 'root.bar.run("omarchy-audio-output-sink")' \
  >> "$unregistered_source/shell/plugins/panels/weather/Model.js"
if "${PYTHON:-python3}" "$checker" "$unregistered_source" "$pinned_source" \
  "$weather_bin/runtime-surface.json" "$weather_bin/feature-surface.json" "$test_root/unregistered.json" \
  >"$test_root/unregistered-output" 2>"$test_root/unregistered-error"; then
  printf '%s\n' 'feature consumer closure accepted a known helper in an unregistered source' >&2
  exit 1
fi
grep -Fq 'omarchy-audio-output-sink (audio-control)' "$test_root/unregistered-error" || {
  cat "$test_root/unregistered-error" >&2
  exit 1
}
printf '%s\n' 'REJECTED known cross-feature helper in previously unregistered selected source'

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
grep -Fq 'references helpers without capability identities: omarchy-undeclared-helper' "$test_root/unknown-error"
printf '%s\n' 'REJECTED unknown helper without feature identity'

unknown_unregistered="$test_root/unknown-unregistered-root"
cp -R -- "$weather_root" "$unknown_unregistered"
chmod -R u+w "$unknown_unregistered"
printf '%s\n' 'root.bar.run("omarchy-undeclared-helper")' \
  >> "$unknown_unregistered/shell/plugins/panels/weather/Model.js"
if "${PYTHON:-python3}" "$checker" "$unknown_unregistered" "$pinned_source" \
  "$weather_bin/runtime-surface.json" "$weather_bin/feature-surface.json" "$test_root/unknown-unregistered.json" \
  >"$test_root/unknown-unregistered-output" 2>"$test_root/unknown-unregistered-error"; then
  printf '%s\n' 'feature consumer closure accepted an unknown helper in an unregistered source' >&2
  exit 1
fi
grep -Fq 'references helpers without capability identities: omarchy-undeclared-helper' \
  "$test_root/unknown-unregistered-error"
printf '%s\n' 'REJECTED unknown helper in previously unregistered selected source'

inline_comment_fixture="$test_root/inline-comment-root"
cp -R -- "$weather_root" "$inline_comment_fixture"
chmod -R u+w "$inline_comment_fixture"
printf '%s\n' '/* note */ root.bar.run("omarchy-undeclared-helper")' \
  >> "$inline_comment_fixture/shell/plugins/panels/weather/BarWidget.qml"
if "${PYTHON:-python3}" "$checker" "$inline_comment_fixture" "$pinned_source" \
  "$weather_bin/runtime-surface.json" "$weather_bin/feature-surface.json" "$test_root/inline-comment.json" \
  >"$test_root/inline-comment-output" 2>"$test_root/inline-comment-error"; then
  printf '%s\n' 'feature consumer closure accepted an unknown helper after an inline block comment' >&2
  exit 1
fi
grep -Fq 'references helpers without capability identities: omarchy-undeclared-helper' \
  "$test_root/inline-comment-error"
printf '%s\n' 'REJECTED unknown helper after an inline block comment'

unselected_fixture="$test_root/unselected-source-root"
cp -R -- "$weather_root" "$unselected_fixture"
chmod -R u+w "$unselected_fixture"
printf '%s\n' 'root.bar.run("omarchy-audio-output-sink")' \
  >> "$unselected_fixture/shell/plugins/panels/network/Panel.qml"
if ! "${PYTHON:-python3}" "$checker" "$unselected_fixture" "$pinned_source" \
  "$weather_bin/runtime-surface.json" "$weather_bin/feature-surface.json" "$test_root/unselected.json" \
  >"$test_root/unselected-output" 2>"$test_root/unselected-error"; then
  cat "$test_root/unselected-error" >&2
  exit 1
fi
printf '%s\n' 'IGNORED helper references in unselected feature source'

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

test ! -e "$core_bin/bin/omarchy-remove-launcher-entry"
test ! -e "$core_bin/bin/uwsm-app"
test ! -e "$core_bin/bin/gtk-launch"
jq -e '
  any(.featureRoots[]; .prefix == "shell/services/hidden-entries.sh" and .feature == "launcher")
' "$core_bin/feature-surface.json" >/dev/null
printf '%s\n' 'verified launcher-gated AppLibrary and hidden-entries source identity'

core_registry="$test_root/core-registry-root"
cp -R -- "$core_root" "$core_registry"
chmod -R u+w "$core_registry"
printf '%s\n' 'root.bar.run("omarchy-audio-output-sink")' \
  >> "$core_registry/shell/services/PluginRegistry.qml"
if "${PYTHON:-python3}" "$checker" "$core_registry" "$pinned_source" \
  "$core_bin/runtime-surface.json" "$core_bin/feature-surface.json" "$test_root/core-registry.json" \
  >"$test_root/core-registry-output" 2>"$test_root/core-registry-error"; then
  printf '%s\n' 'feature consumer closure accepted a cross-feature helper in core PluginRegistry' >&2
  exit 1
fi
grep -Fq 'PluginRegistry.qml (core) requires omarchy-audio-output-sink (audio-control)' "$test_root/core-registry-error"
printf '%s\n' 'REJECTED core PluginRegistry cross-feature helper without dependency'

core_bar_registry="$test_root/core-bar-registry-root"
cp -R -- "$core_root" "$core_bar_registry"
chmod -R u+w "$core_bar_registry"
printf '%s\n' 'root.bar.run("omarchy-audio-output-sink")' \
  >> "$core_bar_registry/shell/services/BarWidgetRegistry.qml"
if "${PYTHON:-python3}" "$checker" "$core_bar_registry" "$pinned_source" \
  "$core_bin/runtime-surface.json" "$core_bin/feature-surface.json" "$test_root/core-bar-registry.json" \
  >"$test_root/core-bar-registry-output" 2>"$test_root/core-bar-registry-error"; then
  printf '%s\n' 'feature consumer closure accepted a cross-feature helper in core BarWidgetRegistry' >&2
  exit 1
fi
grep -Fq 'BarWidgetRegistry.qml (core) requires omarchy-audio-output-sink (audio-control)' "$test_root/core-bar-registry-error"
printf '%s\n' 'REJECTED core BarWidgetRegistry cross-feature helper without dependency'

launcher_source="$test_root/launcher-source-root"
cp -R -- "$launcher_root" "$launcher_source"
chmod -R u+w "$launcher_source"
printf '%s\n' 'root.bar.run("omarchy-network-status")' \
  >> "$launcher_source/shell/services/AppLibrary.qml"
if "${PYTHON:-python3}" "$checker" "$launcher_source" "$pinned_source" \
  "$launcher_bin/runtime-surface.json" "$launcher_bin/feature-surface.json" "$test_root/launcher-source.json" \
  >"$test_root/launcher-source-output" 2>"$test_root/launcher-source-error"; then
  printf '%s\n' 'feature consumer closure accepted a cross-feature helper in launcher AppLibrary' >&2
  exit 1
fi
grep -Fq 'AppLibrary.qml (launcher) requires omarchy-network-status (network-manager)' "$test_root/launcher-source-error"
printf '%s\n' 'REJECTED launcher AppLibrary cross-feature helper without dependency'

mixed_root="$test_root/mixed-root"
cp -R -- "$full_root" "$mixed_root"
chmod -R u+w "$mixed_root"
jq '."probe.one" = {"when":"command -v wl-copy"} | ."probe.two" = {"when":"command -v wl-copy"}' \
  "$mixed_root/default/omarchy/omarchy-menu.jsonc" > "$test_root/mixed-menu.jsonc"
mv "$test_root/mixed-menu.jsonc" "$mixed_root/default/omarchy/omarchy-menu.jsonc"
jq '.consumerFeatureOverrides += [
  {"path":"default/omarchy/omarchy-menu.jsonc","executable":"wl-copy","id":"probe.one","field":"when","feature":"screenshot"},
  {"path":"default/omarchy/omarchy-menu.jsonc","executable":"wl-copy","id":"probe.two","field":"when","feature":"clipboard"}
]' "$full_bin/feature-surface.json" > "$test_root/mixed-surface.json"
if ! "${PYTHON:-python3}" "$checker" "$mixed_root" "$pinned_source" \
  "$full_bin/runtime-surface.json" "$test_root/mixed-surface.json" "$test_root/mixed.json" \
  >"$test_root/mixed-output" 2>"$test_root/mixed-error"; then
  cat "$test_root/mixed-error" >&2
  exit 1
fi
jq -e '[.executableEvidence[] | select(.executable == "wl-copy" and (.reference.id | startswith("probe."))) | .reference.id] | sort == ["probe.one", "probe.two"]' \
  "$test_root/mixed.json" >/dev/null
printf '%s\n' 'verified independent mixed-source occurrence attribution'
jq '.consumerFeatureOverrides += [
  {"path":"default/omarchy/omarchy-menu.jsonc","executable":"wl-copy","feature":"screenshot"}
]' "$test_root/mixed-surface.json" > "$test_root/mixed-generic-surface.json"
if "${PYTHON:-python3}" "$checker" "$mixed_root" "$pinned_source" \
  "$full_bin/runtime-surface.json" "$test_root/mixed-generic-surface.json" "$test_root/mixed-generic.json" \
  >"$test_root/mixed-generic-output" 2>"$test_root/mixed-generic-error"; then
  printf '%s\n' 'feature consumer closure accepted a generic override beside precise mixed references' >&2
  exit 1
fi
grep -Fq 'duplicate consumer feature override' "$test_root/mixed-generic-error"
printf '%s\n' 'REJECTED generic mixed-source override'
mixed_wrong_root="$test_root/mixed-wrong-root"
cp -R -- "$screenshot_root" "$mixed_wrong_root"
chmod -R u+w "$mixed_wrong_root"
jq '."probe.one" = {"when":"command -v wl-copy"} | ."probe.two" = {"when":"command -v wl-copy"}' \
  "$mixed_wrong_root/default/omarchy/omarchy-menu.jsonc" > "$test_root/mixed-wrong-menu.jsonc"
mv "$test_root/mixed-wrong-menu.jsonc" "$mixed_wrong_root/default/omarchy/omarchy-menu.jsonc"
jq '.consumerFeatureOverrides += [
  {"path":"default/omarchy/omarchy-menu.jsonc","executable":"wl-copy","id":"probe.one","field":"when","feature":"screenshot"},
  {"path":"default/omarchy/omarchy-menu.jsonc","executable":"wl-copy","id":"probe.two","field":"when","feature":"clipboard"}
]' "$screenshot_bin/feature-surface.json" > "$test_root/mixed-wrong-surface.json"
if "${PYTHON:-python3}" "$checker" "$mixed_wrong_root" "$pinned_source" \
  "$screenshot_bin/runtime-surface.json" "$test_root/mixed-wrong-surface.json" "$test_root/mixed-wrong.json" \
  >"$test_root/mixed-wrong-output" 2>"$test_root/mixed-wrong-error"; then
  printf '%s\n' 'feature consumer closure accepted a mixed-source occurrence with an unselected feature' >&2
  exit 1
fi
grep -Fq 'invocation feature is not selected' "$test_root/mixed-wrong-error"
printf '%s\n' 'REJECTED mixed-source occurrence with incorrect feature attribution'

weather_external="$test_root/weather-external-root"
cp -R -- "$weather_root" "$weather_external"
chmod -R u+w "$weather_external"
printf '%s\n' 'root.bar.run("nmcli")' >> "$weather_external/shell/plugins/panels/weather/Panel.qml"
if "${PYTHON:-python3}" "$checker" "$weather_external" "$pinned_source" \
  "$weather_bin/runtime-surface.json" "$weather_bin/feature-surface.json" "$test_root/weather-external.json" \
  >"$test_root/weather-external-output" 2>"$test_root/weather-external-error"; then
  printf '%s\n' 'feature consumer closure accepted weather-to-network executable drift' >&2
  exit 1
fi
grep -Fq 'Panel.qml (weather) requires executable nmcli (network-manager)' "$test_root/weather-external-error"
printf '%s\n' 'REJECTED weather external executable without dependency'

clipboard_external="$test_root/clipboard-external-root"
cp -R -- "$clipboard_root" "$clipboard_external"
chmod -R u+w "$clipboard_external"
printf '%s\n' 'root.bar.run("brightnessctl")' >> "$clipboard_external/shell/plugins/clipboard/Clipboard.qml"
if "${PYTHON:-python3}" "$checker" "$clipboard_external" "$pinned_source" \
  "$clipboard_bin/runtime-surface.json" "$clipboard_bin/feature-surface.json" "$test_root/clipboard-external.json" \
  >"$test_root/clipboard-external-output" 2>"$test_root/clipboard-external-error"; then
  printf '%s\n' 'feature consumer closure accepted clipboard-to-monitor executable drift' >&2
  exit 1
fi
grep -Fq 'Clipboard.qml (clipboard) requires executable brightnessctl (monitor-control)' "$test_root/clipboard-external-error"
printf '%s\n' 'REJECTED clipboard external executable without dependency'

clipboard_script_external="$test_root/clipboard-script-external-root"
cp -R -- "$clipboard_root" "$clipboard_script_external"
chmod -R u+w "$clipboard_script_external"
printf '%s\n' 'brightnessctl' >> "$clipboard_script_external/shell/plugins/clipboard/capture.sh"
if "${PYTHON:-python3}" "$checker" "$clipboard_script_external" "$pinned_source" \
  "$clipboard_bin/runtime-surface.json" "$clipboard_bin/feature-surface.json" "$test_root/clipboard-script-external.json" \
  >"$test_root/clipboard-script-external-output" 2>"$test_root/clipboard-script-external-error"; then
  printf '%s\n' 'feature consumer closure accepted executable drift in a shell source' >&2
  exit 1
fi
grep -Fq 'capture.sh (clipboard) requires executable brightnessctl (monitor-control)' \
  "$test_root/clipboard-script-external-error"
printf '%s\n' 'REJECTED shell-source external executable without dependency'

core_external="$test_root/core-external-root"
cp -R -- "$core_root" "$core_external"
chmod -R u+w "$core_external"
printf '%s\n' 'root.bar.run("curl")' >> "$core_external/shell/services/PluginRegistry.qml"
if "${PYTHON:-python3}" "$checker" "$core_external" "$pinned_source" \
  "$core_bin/runtime-surface.json" "$core_bin/feature-surface.json" "$test_root/core-external.json" \
  >"$test_root/core-external-output" 2>"$test_root/core-external-error"; then
  printf '%s\n' 'feature consumer closure accepted core-to-weather executable drift' >&2
  exit 1
fi
grep -Fq 'PluginRegistry.qml (core) requires executable curl (weather-network)' "$test_root/core-external-error"
printf '%s\n' 'REJECTED core external executable without dependency'

unknown_qml="$test_root/unknown-qml-root"
cp -R -- "$core_root" "$unknown_qml"
chmod -R u+w "$unknown_qml"
printf '%s\n' 'root.bar.run("foot")' >> "$unknown_qml/shell/services/PluginRegistry.qml"
if "${PYTHON:-python3}" "$checker" "$unknown_qml" "$pinned_source" \
  "$core_bin/runtime-surface.json" "$core_bin/feature-surface.json" "$test_root/unknown-qml.json" \
  >"$test_root/unknown-qml-output" 2>"$test_root/unknown-qml-error"; then
  printf '%s\n' 'feature consumer closure accepted unknown QML executable foot' >&2
  exit 1
fi
grep -Fq 'unknown external executable: foot' "$test_root/unknown-qml-error"
printf '%s\n' 'REJECTED unknown QML executable'

unknown_process="$test_root/unknown-process-root"
cp -R -- "$weather_root" "$unknown_process"
chmod -R u+w "$unknown_process"
printf '%s\n' 'Process { command: ["wget", "https://example.invalid"] }' \
  >> "$unknown_process/shell/plugins/panels/weather/Panel.qml"
if "${PYTHON:-python3}" "$checker" "$unknown_process" "$pinned_source" \
  "$weather_bin/runtime-surface.json" "$weather_bin/feature-surface.json" "$test_root/unknown-process.json" \
  >"$test_root/unknown-process-output" 2>"$test_root/unknown-process-error"; then
  printf '%s\n' 'feature consumer closure accepted unknown Process executable wget' >&2
  exit 1
fi
grep -Fq 'unknown external executable: wget' "$test_root/unknown-process-error"
printf '%s\n' 'REJECTED unknown Process executable'

unknown_shell_payload="$test_root/unknown-shell-payload-root"
cp -R -- "$weather_root" "$unknown_shell_payload"
chmod -R u+w "$unknown_shell_payload"
printf '%s\n' 'Process { command: ["bash", "-lc", "pacman"] }' \
  >> "$unknown_shell_payload/shell/plugins/panels/weather/Panel.qml"
if "${PYTHON:-python3}" "$checker" "$unknown_shell_payload" "$pinned_source" \
  "$weather_bin/runtime-surface.json" "$weather_bin/feature-surface.json" "$test_root/unknown-shell-payload.json" \
  >"$test_root/unknown-shell-payload-output" 2>"$test_root/unknown-shell-payload-error"; then
  printf '%s\n' 'feature consumer closure accepted pacman in a literal shell payload' >&2
  exit 1
fi
grep -Fq 'unknown external executable: pacman' "$test_root/unknown-shell-payload-error"
printf '%s\n' 'REJECTED pacman in a literal shell payload'

unknown_script_payload="$test_root/unknown-script-payload-root"
cp -R -- "$weather_root" "$unknown_script_payload"
chmod -R u+w "$unknown_script_payload"
printf '%s\n' 'Item { script: "pacman" }' \
  >> "$unknown_script_payload/shell/plugins/panels/weather/Panel.qml"
if "${PYTHON:-python3}" "$checker" "$unknown_script_payload" "$pinned_source" \
  "$weather_bin/runtime-surface.json" "$weather_bin/feature-surface.json" "$test_root/unknown-script-payload.json" \
  >"$test_root/unknown-script-payload-output" 2>"$test_root/unknown-script-payload-error"; then
  printf '%s\n' 'feature consumer closure accepted pacman in a script payload' >&2
  exit 1
fi
grep -Fq 'unknown external executable: pacman' "$test_root/unknown-script-payload-error"
printf '%s\n' 'REJECTED pacman in a script payload'

unknown_exec_payload="$test_root/unknown-exec-payload-root"
cp -R -- "$weather_root" "$unknown_exec_payload"
chmod -R u+w "$unknown_exec_payload"
printf '%s\n' 'Item { script: "exec pacman" }' \
  >> "$unknown_exec_payload/shell/plugins/panels/weather/Panel.qml"
if "${PYTHON:-python3}" "$checker" "$unknown_exec_payload" "$pinned_source" \
  "$weather_bin/runtime-surface.json" "$weather_bin/feature-surface.json" "$test_root/unknown-exec-payload.json" \
  >"$test_root/unknown-exec-payload-output" 2>"$test_root/unknown-exec-payload-error"; then
  printf '%s\n' 'feature consumer closure accepted exec pacman in a script payload' >&2
  exit 1
fi
grep -Fq 'unknown external executable: pacman' "$test_root/unknown-exec-payload-error"
printf '%s\n' 'REJECTED exec pacman in a script payload'

unknown_eval_payload="$test_root/unknown-eval-payload-root"
cp -R -- "$weather_root" "$unknown_eval_payload"
chmod -R u+w "$unknown_eval_payload"
printf '%s\n' 'Item { script: "eval pacman" }' \
  >> "$unknown_eval_payload/shell/plugins/panels/weather/Panel.qml"
if "${PYTHON:-python3}" "$checker" "$unknown_eval_payload" "$pinned_source" \
  "$weather_bin/runtime-surface.json" "$weather_bin/feature-surface.json" "$test_root/unknown-eval-payload.json" \
  >"$test_root/unknown-eval-payload-output" 2>"$test_root/unknown-eval-payload-error"; then
  printf '%s\n' 'feature consumer closure accepted eval pacman in a script payload' >&2
  exit 1
fi
grep -Fq 'unknown external executable: eval' "$test_root/unknown-eval-payload-error"
printf '%s\n' 'REJECTED eval pacman in a script payload'

dynamic_array_payload="$test_root/dynamic-array-payload-root"
cp -R -- "$weather_root" "$dynamic_array_payload"
chmod -R u+w "$dynamic_array_payload"
printf '%s\n' 'Process { command: ["bash", "-lc", dynamicShell] }' \
  >> "$dynamic_array_payload/shell/plugins/panels/weather/Panel.qml"
if "${PYTHON:-python3}" "$checker" "$dynamic_array_payload" "$pinned_source" \
  "$weather_bin/runtime-surface.json" "$weather_bin/feature-surface.json" "$test_root/dynamic-array-payload.json" \
  >"$test_root/dynamic-array-payload-output" 2>"$test_root/dynamic-array-payload-error"; then
  printf '%s\n' 'feature consumer closure accepted a dynamic shell payload' >&2
  exit 1
fi
grep -Fq 'unknown external executable: __dynamic-executable__' "$test_root/dynamic-array-payload-error"
printf '%s\n' 'REJECTED dynamic shell payload'

dynamic_command_payload="$test_root/dynamic-command-payload-root"
cp -R -- "$weather_root" "$dynamic_command_payload"
chmod -R u+w "$dynamic_command_payload"
printf '%s\n' 'Process { command: dynamicCommand }' \
  >> "$dynamic_command_payload/shell/plugins/panels/weather/Panel.qml"
if "${PYTHON:-python3}" "$checker" "$dynamic_command_payload" "$pinned_source" \
  "$weather_bin/runtime-surface.json" "$weather_bin/feature-surface.json" "$test_root/dynamic-command-payload.json" \
  >"$test_root/dynamic-command-payload-output" 2>"$test_root/dynamic-command-payload-error"; then
  printf '%s\n' 'feature consumer closure accepted a dynamic command payload' >&2
  exit 1
fi
grep -Fq 'unknown external executable: __dynamic-executable__' "$test_root/dynamic-command-payload-error"
printf '%s\n' 'REJECTED dynamic command payload'

unknown_shell="$test_root/unknown-shell-root"
cp -R -- "$launcher_root" "$unknown_shell"
chmod -R u+w "$unknown_shell"
printf '%s\n' 'totally-unknown-runtime-command' >> "$unknown_shell/shell/services/hidden-entries.sh"
if "${PYTHON:-python3}" "$checker" "$unknown_shell" "$pinned_source" \
  "$launcher_bin/runtime-surface.json" "$launcher_bin/feature-surface.json" "$test_root/unknown-shell.json" \
  >"$test_root/unknown-shell-output" 2>"$test_root/unknown-shell-error"; then
  printf '%s\n' 'feature consumer closure accepted unknown shell executable' >&2
  exit 1
fi
grep -Fq 'unknown external executable: totally-unknown-runtime-command' "$test_root/unknown-shell-error"
printf '%s\n' 'REJECTED unknown shell executable'

unknown_indented_shell="$test_root/unknown-indented-shell-root"
cp -R -- "$launcher_root" "$unknown_indented_shell"
chmod -R u+w "$unknown_indented_shell"
printf '%s\n' '  totally-unknown-indented-command' >> "$unknown_indented_shell/shell/services/hidden-entries.sh"
if "${PYTHON:-python3}" "$checker" "$unknown_indented_shell" "$pinned_source" \
  "$launcher_bin/runtime-surface.json" "$launcher_bin/feature-surface.json" "$test_root/unknown-indented-shell.json" \
  >"$test_root/unknown-indented-shell-output" 2>"$test_root/unknown-indented-shell-error"; then
  printf '%s\n' 'feature consumer closure accepted an indented unknown shell executable' >&2
  exit 1
fi
grep -Fq 'unknown external executable: totally-unknown-indented-command' \
  "$test_root/unknown-indented-shell-error"
printf '%s\n' 'REJECTED indented unknown shell executable'

launcher_external="$test_root/launcher-external-root"
cp -R -- "$launcher_root" "$launcher_external"
chmod -R u+w "$launcher_external"
printf '%s\n' 'nmcli' >> "$launcher_external/shell/services/hidden-entries.sh"
if "${PYTHON:-python3}" "$checker" "$launcher_external" "$pinned_source" \
  "$launcher_bin/runtime-surface.json" "$launcher_bin/feature-surface.json" "$test_root/launcher-external.json" \
  >"$test_root/launcher-external-output" 2>"$test_root/launcher-external-error"; then
  printf '%s\n' 'feature consumer closure accepted launcher-to-network executable drift' >&2
  exit 1
fi
grep -Fq 'hidden-entries.sh (launcher) requires executable nmcli (network-manager)' \
  "$test_root/launcher-external-error"
printf '%s\n' 'REJECTED launcher external executable without capability'

pacman_root="$test_root/pacman-root"
cp -R -- "$core_root" "$pacman_root"
chmod -R u+w "$pacman_root"
printf '%s\n' 'root.bar.run("pacman")' >> "$pacman_root/shell/services/PluginRegistry.qml"
if "${PYTHON:-python3}" "$checker" "$pacman_root" "$pinned_source" \
  "$core_bin/runtime-surface.json" "$core_bin/feature-surface.json" "$test_root/pacman.json" \
  >"$test_root/pacman-output" 2>"$test_root/pacman-error"; then
  printf '%s\n' 'feature consumer closure accepted omitted pacman executable' >&2
  exit 1
fi
grep -Fq 'unknown external executable: pacman' "$test_root/pacman-error"
printf '%s\n' 'REJECTED omitted pacman executable'

weather_edge_surface="$test_root/weather-edge-surface.json"
jq '.featureCapabilities.weather += ["network-manager"] | .selectedCapabilities += ["network-manager"]' \
  "$weather_bin/feature-surface.json" > "$weather_edge_surface"
if ! "${PYTHON:-python3}" "$checker" "$weather_external" "$pinned_source" \
  "$weather_bin/runtime-surface.json" "$weather_edge_surface" "$test_root/weather-edge.json" \
  2>"$test_root/weather-edge-error"; then
  cat "$test_root/weather-edge-error" >&2
  exit 1
fi
printf '%s\n' 'ACCEPTED weather external executable with explicit dependency'

noise_root="$test_root/noise-root"
cp -R -- "$full_root" "$noise_root"
chmod -R u+w "$noise_root"
printf '%s\n' 'root.bar.run("omarchy-default-browser")' \
  >> "$noise_root/shell/plugins/menu/MenuModel.js"
if "${PYTHON:-python3}" "$checker" "$noise_root" "$pinned_source" \
  "$full_bin/runtime-surface.json" "$full_bin/feature-surface.json" "$test_root/noise.json" \
  >"$test_root/noise-output" 2>"$test_root/noise-error"; then
  printf '%s\n' 'feature consumer closure accepted a real invocation of a noise helper' >&2
  exit 1
fi
grep -Fq 'scanner noise evidence drifted for shell/plugins/menu/MenuModel.js: omarchy-default-browser' \
  "$test_root/noise-error"
printf '%s\n' 'REJECTED real invocation of a former noise helper'

noise_new_path="$test_root/noise-new-path-root"
cp -R -- "$full_root" "$noise_new_path"
chmod -R u+w "$noise_new_path"
printf '%s\n' 'root.bar.run("omarchy-default-browser")' \
  >> "$noise_new_path/shell/plugins/panels/weather/Panel.qml"
if "${PYTHON:-python3}" "$checker" "$noise_new_path" "$pinned_source" \
  "$full_bin/runtime-surface.json" "$full_bin/feature-surface.json" "$test_root/noise-new-path.json" \
  >"$test_root/noise-new-path-output" 2>"$test_root/noise-new-path-error"; then
  printf '%s\n' 'feature consumer closure accepted a former noise helper at a new path' >&2
  exit 1
fi
grep -Fq 'references helpers without capability identities: omarchy-default-browser' \
  "$test_root/noise-new-path-error"
printf '%s\n' 'REJECTED former noise helper at an unledgered path'

noise_shape="$test_root/noise-shape-root"
cp -R -- "$full_root" "$noise_shape"
chmod -R u+w "$noise_shape"
sed -i 's/  "omarchy-default-browser",/  "omarchy-default-browser", \/\/ changed/' \
  "$noise_shape/shell/plugins/menu/MenuModel.js"
if "${PYTHON:-python3}" "$checker" "$noise_shape" "$pinned_source" \
  "$full_bin/runtime-surface.json" "$full_bin/feature-surface.json" "$test_root/noise-shape.json" \
  >"$test_root/noise-shape-output" 2>"$test_root/noise-shape-error"; then
  printf '%s\n' 'feature consumer closure accepted changed noise source shape' >&2
  exit 1
fi
grep -Fq 'scanner noise evidence drifted for shell/plugins/menu/MenuModel.js: omarchy-default-browser' \
  "$test_root/noise-shape-error"
printf '%s\n' 'REJECTED changed noise source shape'

printf '%s\n' 'feature consumer closure passed'
