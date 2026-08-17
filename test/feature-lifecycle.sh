#!/usr/bin/env bash
set -euo pipefail

full_activation=${1:?full activation script required}
clipboard_activation=${2:?clipboard activation script required}
core_activation=${3:?core activation script required}
full_runtime=${4:?full runtime required}
clipboard_runtime=${5:?clipboard runtime required}
core_runtime=${6:?core runtime required}
full_root=${7:?full compatibility root required}
clipboard_root=${8:?clipboard compatibility root required}
core_root=${9:?core compatibility root required}
quickshell=${10:?Quickshell executable required}
audio_activation=${11:?audio activation script required}
weather_activation=${12:?weather activation script required}
network_activation=${13:?network activation script required}
audio_runtime=${14:?audio runtime required}
weather_runtime=${15:?weather runtime required}
network_runtime=${16:?network runtime required}
audio_root=${17:?audio compatibility root required}
weather_root=${18:?weather compatibility root required}
network_root=${19:?network compatibility root required}
bluetooth_root=${20:?bluetooth compatibility root required}
screenshot_root=${21:?screenshot compatibility root required}

activate() {
  local home=$1
  local activation=$2
  HOME="$home" USER=omanixy-test XDG_RUNTIME_DIR="$home/runtime" \
    bash -c 'run() { "$@"; }; source "$1"' bash "$activation"
}

runtime_path() {
  sed -n 's/^export PATH="\(.*\)"$/\1/p' "$1/bin/omanixy-shell-runtime"
}

assert_absent() {
  local path=$1
  test ! -e "$path"
}

test_root=$(mktemp -d)
trap 'chmod -R u+w "$test_root" 2>/dev/null || true; rm -rf "$test_root"' EXIT

feature_plugin_ids=(
  omarchy.audio
  omarchy.bluetooth
  omarchy.monitor
  omarchy.network
  omarchy.power
  omarchy.weather
)

assert_no_feature_omissions() {
  local config=$1
  for plugin in "${feature_plugin_ids[@]}"; do
    jq -e --arg plugin "$plugin" '(.disabledPlugins | index($plugin)) == null' "$config" >/dev/null
  done
}

fresh_clipboard_home="$test_root/fresh-clipboard-home"
mkdir -p "$fresh_clipboard_home"
activate "$fresh_clipboard_home" "$clipboard_activation"
fresh_clipboard_config="$fresh_clipboard_home/.config/omarchy/shell.json"
test -f "$fresh_clipboard_config"
jq -e '(has("featureCapabilities") | not) and (has("capabilityDependencies") | not)' "$fresh_clipboard_config" >/dev/null
assert_no_feature_omissions "$fresh_clipboard_config"
jq -e '.selectedFeatures == ["core", "clipboard"] and (.runtimeBlockedPlugins | index("omarchy.audio") != null)' \
  "$fresh_clipboard_home/.local/state/omanixy/capabilities.json" >/dev/null
activate "$fresh_clipboard_home" "$full_activation"
jq -e '.selectedFeatures | index("weather") != null and index("audio") != null' \
  "$fresh_clipboard_home/.local/state/omanixy/capabilities.json" >/dev/null

fresh_core_home="$test_root/fresh-core-home"
mkdir -p "$fresh_core_home"
activate "$fresh_core_home" "$core_activation"
fresh_core_config="$fresh_core_home/.config/omarchy/shell.json"
test -f "$fresh_core_config"
jq -e '(has("featureCapabilities") | not) and (has("capabilityDependencies") | not)' "$fresh_core_config" >/dev/null
assert_no_feature_omissions "$fresh_core_config"
jq -e '.selectedFeatures == ["core"]' \
  "$fresh_core_home/.local/state/omanixy/capabilities.json" >/dev/null
activate "$fresh_core_home" "$full_activation"

fresh_audio_home="$test_root/fresh-audio-home"
mkdir -p "$fresh_audio_home"
activate "$fresh_audio_home" "$audio_activation"
fresh_audio_config="$fresh_audio_home/.config/omarchy/shell.json"
test -f "$fresh_audio_config"
assert_no_feature_omissions "$fresh_audio_config"
activate "$fresh_audio_home" "$network_activation"
jq -e '.selectedFeatures == ["core", "network"]' \
  "$fresh_audio_home/.local/state/omanixy/capabilities.json" >/dev/null

fresh_clipboard_weather_home="$test_root/fresh-clipboard-weather-home"
mkdir -p "$fresh_clipboard_weather_home"
activate "$fresh_clipboard_weather_home" "$clipboard_activation"
fresh_clipboard_weather_config="$fresh_clipboard_weather_home/.config/omarchy/shell.json"
activate "$fresh_clipboard_weather_home" "$weather_activation"
jq -e '.selectedFeatures == ["core", "weather"]' \
  "$fresh_clipboard_weather_home/.local/state/omanixy/capabilities.json" >/dev/null

full_home="$test_root/full-home"
mkdir -p "$full_home"
activate "$full_home" "$full_activation"
test -f "$full_home/.config/omarchy/shell.json"
cp "$full_home/.config/omarchy/shell.json" "$test_root/full-shell.json"
activate "$full_home" "$full_activation"
cmp "$test_root/full-shell.json" "$full_home/.config/omarchy/shell.json"
activate "$full_home" "$clipboard_activation"
cmp "$test_root/full-shell.json" "$full_home/.config/omarchy/shell.json"
jq '.bar.layout.center += [{"id": "omarchy.weather", "format": "custom"}]' \
  "$test_root/full-shell.json" > "$test_root/custom-shell.json"
cp "$test_root/custom-shell.json" "$full_home/.config/omarchy/shell.json"
activate "$full_home" "$clipboard_activation"
cmp "$test_root/custom-shell.json" "$full_home/.config/omarchy/shell.json"
activate "$full_home" "$full_activation"
cmp "$test_root/custom-shell.json" "$full_home/.config/omarchy/shell.json"
activate "$full_home" "$core_activation"
cmp "$test_root/custom-shell.json" "$full_home/.config/omarchy/shell.json"
activate "$full_home" "$clipboard_activation"
cmp "$test_root/custom-shell.json" "$full_home/.config/omarchy/shell.json"

core_home="$test_root/core-home"
mkdir -p "$core_home"
activate "$core_home" "$full_activation"
cp "$core_home/.config/omarchy/shell.json" "$test_root/core-full-shell.json"
activate "$core_home" "$core_activation"
cmp "$test_root/core-full-shell.json" "$core_home/.config/omarchy/shell.json"
activate "$core_home" "$core_activation"
cmp "$test_root/core-full-shell.json" "$core_home/.config/omarchy/shell.json"

clipboard_path=$(runtime_path "$clipboard_runtime")
full_path=$(runtime_path "$full_runtime")
audio_path=$(runtime_path "$audio_runtime")
weather_path=$(runtime_path "$weather_runtime")
network_path=$(runtime_path "$network_runtime")
core_path=$(runtime_path "$core_runtime")

jq -e 'has("trigger.screenshot") and (has("trigger.emoji") | not)' \
  "$screenshot_root/default/omarchy/omarchy-menu.jsonc" >/dev/null

test -x "$full_runtime/bin/omarchy-audio-output-set-default"
test -x "$full_runtime/bin/omarchy-weather-status"
test -x "$full_runtime/bin/omarchy-network-status"
test -x "$full_runtime/bin/omarchy-monitor-state"
test -x "$full_runtime/bin/omarchy-powerprofiles-list"
test -x "$full_runtime/bin/omarchy-bluetooth-device"
PATH="$full_path" command -v pactl >/dev/null
PATH="$full_path" command -v curl >/dev/null
PATH="$full_path" command -v nmcli >/dev/null
PATH="$audio_path" command -v pactl >/dev/null
PATH="$weather_path" command -v curl >/dev/null
PATH="$network_path" command -v nmcli >/dev/null
if PATH="$core_path" command -v uwsm-app >/dev/null || PATH="$core_path" command -v gtk-launch >/dev/null; then
  printf '%s\n' 'core-only runtime unexpectedly contains launcher executables' >&2
  exit 1
fi
test -x "$audio_runtime/bin/omarchy-audio-output-set-default"
test -x "$weather_runtime/bin/omarchy-weather-status"
test -x "$network_runtime/bin/omarchy-network-status"

test -x "$clipboard_runtime/bin/omarchy-clipboard-paste-text"
test -x "$clipboard_runtime/bin/omarchy-menu-emoji-insert"
for helper in \
  omarchy-audio-output-set-default \
  omarchy-bluetooth-device \
  omarchy-monitor-state \
  omarchy-network-status \
  omarchy-powerprofiles-list \
  omarchy-weather-status; do
  assert_absent "$clipboard_runtime/bin/$helper"
done
for backend in pactl wpctl bluetoothctl nmcli brightnessctl curl notify-send; do
  if PATH="$clipboard_path" command -v "$backend" >/dev/null; then
    printf 'clipboard-only runtime unexpectedly contains %s\n' "$backend" >&2
    exit 1
  fi
done
PATH="$clipboard_path" command -v wl-copy >/dev/null
PATH="$clipboard_path" command -v wtype >/dev/null

test -x "$core_runtime/bin/omarchy-system-stats"
for helper in \
  omarchy-audio-output-set-default \
  omarchy-bluetooth-device \
  omarchy-monitor-state \
  omarchy-network-status \
  omarchy-powerprofiles-list \
  omarchy-weather-status \
  omarchy-clipboard-paste-text; do
  assert_absent "$core_runtime/bin/$helper"
done

run_registry_policy() {
  local root=$1 expected=$2 name=$3 config_file=${4:-}
  local harness="$test_root/$name.qml"
  local qml_root="$test_root/$name"
  local config_json='{"disabledPlugins":[],"bar":{"layout":{"left":[],"center":[],"right":[]}}}'
  if [[ -n $config_file ]]; then
    config_json=$(jq -c '{disabledPlugins: (.disabledPlugins // []), bar: (.bar // {layout: {left: [], center: [], right: []}})}' "$config_file")
  fi
  mkdir -p "$qml_root"
  ln -s "$root/shell" "$qml_root/qs"
  cat > "$harness" <<EOF
import QtQuick
import Quickshell

ShellRoot {
  Loader {
    id: registryLoader
    source: "${qml_root}/qs/services/PluginRegistry.qml"
    onLoaded: {
      var registry = registryLoader.item
      registry.installedPlugins = ({
        "omarchy.audio": { kinds: ["panel"], __isFirstParty: true },
        "omarchy.bluetooth": { kinds: ["panel"], __isFirstParty: true },
        "omarchy.clipboard": { kinds: ["panel"], __isFirstParty: true },
        "omarchy.emojis": { kinds: ["panel"], __isFirstParty: true },
        "omarchy.monitor": { kinds: ["panel"], __isFirstParty: true },
        "omarchy.network": { kinds: ["panel"], __isFirstParty: true },
        "omarchy.power": { kinds: ["panel"], __isFirstParty: true },
        "omarchy.weather": { kinds: ["panel"], __isFirstParty: true }
      })
      registry.shellConfigProvider = function() {
        return ${config_json}
      }
      var expected = ${expected}
      var ids = [
        "omarchy.audio", "omarchy.bluetooth", "omarchy.clipboard", "omarchy.emojis",
        "omarchy.monitor", "omarchy.network", "omarchy.power", "omarchy.weather"
      ]
      for (var i = 0; i < ids.length; i++) {
        if (registry.isEnabled(ids[i]) !== (expected.indexOf(ids[i]) !== -1)) {
          console.log("REGISTRY_POLICY_FAIL", ids[i], registry.isEnabled(ids[i]))
          Qt.quit()
          return
        }
      }
      console.log("REGISTRY_POLICY_PASS")
      Qt.quit()
    }
  }
}
EOF
  HOME="$test_root/home-$name" XDG_RUNTIME_DIR="$test_root/runtime-$name" \
    QML2_IMPORT_PATH="$qml_root" QT_QPA_PLATFORM=offscreen \
    timeout 15s "$quickshell" -n -p "$harness" >"$test_root/$name.log" 2>&1 || true
  grep -Fq 'REGISTRY_POLICY_PASS' "$test_root/$name.log" || {
    cat "$test_root/$name.log" >&2
    exit 1
  }
}

run_registry_policy "$full_root" '["omarchy.audio", "omarchy.bluetooth", "omarchy.clipboard", "omarchy.emojis", "omarchy.monitor", "omarchy.network", "omarchy.power", "omarchy.weather"]' full "$test_root/full-shell.json"
run_registry_policy "$clipboard_root" '["omarchy.clipboard", "omarchy.emojis"]' clipboard "$test_root/full-shell.json"
run_registry_policy "$core_root" '[]' core "$test_root/full-shell.json"
run_registry_policy "$network_root" '["omarchy.network"]' network "$test_root/full-shell.json"
run_registry_policy "$bluetooth_root" '["omarchy.bluetooth"]' bluetooth "$test_root/full-shell.json"
run_registry_policy "$full_root" '["omarchy.audio", "omarchy.bluetooth", "omarchy.clipboard", "omarchy.emojis", "omarchy.monitor", "omarchy.network", "omarchy.power", "omarchy.weather"]' fresh-clipboard-full "$fresh_clipboard_config"
run_registry_policy "$full_root" '["omarchy.audio", "omarchy.bluetooth", "omarchy.clipboard", "omarchy.emojis", "omarchy.monitor", "omarchy.network", "omarchy.power", "omarchy.weather"]' fresh-core-full "$fresh_core_config"
run_registry_policy "$audio_root" '["omarchy.audio"]' fresh-audio "$fresh_audio_config"
run_registry_policy "$network_root" '["omarchy.network"]' fresh-audio-network "$fresh_audio_config"
run_registry_policy "$weather_root" '["omarchy.weather"]' fresh-clipboard-weather "$fresh_clipboard_weather_config"
run_registry_policy "$clipboard_root" '["omarchy.clipboard", "omarchy.emojis"]' customized-clipboard "$test_root/custom-shell.json"
activate "$fresh_clipboard_home" "$core_activation"
run_registry_policy "$core_root" '[]' fresh-clipboard-full-core "$fresh_clipboard_config"

run_app_library_reachability() {
  local root=$1 expected=$2 name=$3
  local test_source="$test_root/$name-root"
  local harness="$test_root/$name.qml"
  local gate="$test_source/shell/feature-gate.qml"
  local marker="$test_root/$name-hidden-entries-ran"
  cp -R -- "$root" "$test_source"
  chmod -R u+w "$test_source"
  sed -i '0,/Component.onCompleted: {/s//Component.onCompleted: { console.log("APP_LIBRARY_STARTED")/' \
    "$test_source/shell/services/AppLibrary.qml"
  cat > "$test_source/shell/services/hidden-entries.sh" <<EOF
#!/bin/sh
printf '%s\\n' ran > "\$OMANIXY_HIDDEN_MARKER"
EOF
  chmod 0555 "$test_source/shell/services/hidden-entries.sh"
  if [[ $expected == true ]]; then
    cat > "$gate" <<EOF
import QtQuick
import Quickshell

ShellRoot {
  Loader {
    source: "${test_source}/shell/services/AppLibrary.qml"
  }
}
EOF
  else
    cat > "$gate" <<'EOF'
import QtQuick
import Quickshell

ShellRoot {
  property var appLibrary: null
}
EOF
    grep -Fqx '  property AppLibrary appLibrary: null' "$test_source/shell/shell.qml"
  fi
  ln -s shell "$test_source/qs"
  cat > "$harness" <<EOF
import QtQuick
import Quickshell

ShellRoot {
  Loader {
    source: "${gate}"
  }

  Timer {
    interval: 2000
    running: true
    onTriggered: Qt.quit()
  }
}
EOF
  HOME="$test_root/$name-home" XDG_RUNTIME_DIR="$test_root/$name-runtime" \
    OMANIXY_HIDDEN_MARKER="$marker" OMARCHY_PATH="$test_source" \
    QML2_IMPORT_PATH="$test_source" QT_QPA_PLATFORM=offscreen \
    timeout 10s "$quickshell" -n -p "$harness" >"$test_root/$name.log" 2>&1 || true
  if [[ $expected == true ]]; then
    grep -Fq 'APP_LIBRARY_STARTED' "$test_root/$name.log" || {
      cat "$test_root/$name.log" >&2
      printf '%s\n' 'launcher runtime did not instantiate AppLibrary' >&2
      exit 1
    }
    test -f "$marker" || {
      cat "$test_root/$name.log" >&2
      printf '%s\n' 'launcher runtime did not execute hidden-entries.sh' >&2
      exit 1
    }
  else
    if grep -Fq 'APP_LIBRARY_STARTED' "$test_root/$name.log" || test -e "$marker"; then
      cat "$test_root/$name.log" >&2
      printf '%s\n' 'core-only shell instantiated launcher AppLibrary' >&2
      exit 1
    fi
  fi
}

run_app_library_reachability "$core_root" false core-app-library
run_app_library_reachability "$full_root" true launcher-app-library

printf '%s\n' 'feature lifecycle checks passed'
