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

runtime_path() {
  sed -n 's/^export PATH="\(.*\)"$/\1/p' "$1/bin/omanixy-shell-runtime"
}

assert_absent() {
  local path=$1
  test ! -e "$path"
}

test_root=$(mktemp -d)
trap 'chmod -R u+w "$test_root" 2>/dev/null || true; rm -rf "$test_root"' EXIT

full_home="$test_root/full-home"
mkdir -p "$full_home"
HOME="$full_home" USER=omanixy-test XDG_RUNTIME_DIR="$full_home/runtime" \
  bash -c 'run() { "$@"; }; source "$1"' bash "$full_activation"
test -f "$full_home/.config/omarchy/shell.json"
cp "$full_home/.config/omarchy/shell.json" "$test_root/full-shell.json"
HOME="$full_home" USER=omanixy-test XDG_RUNTIME_DIR="$full_home/runtime" \
  bash -c 'run() { "$@"; }; source "$1"' bash "$full_activation"
cmp "$test_root/full-shell.json" "$full_home/.config/omarchy/shell.json"
HOME="$full_home" USER=omanixy-test XDG_RUNTIME_DIR="$full_home/runtime" \
  bash -c 'run() { "$@"; }; source "$1"' bash "$clipboard_activation"
cmp "$test_root/full-shell.json" "$full_home/.config/omarchy/shell.json"
jq '.bar.layout.center += [{"id": "omarchy.weather", "format": "custom"}]' \
  "$test_root/full-shell.json" > "$test_root/custom-shell.json"
cp "$test_root/custom-shell.json" "$full_home/.config/omarchy/shell.json"
HOME="$full_home" USER=omanixy-test XDG_RUNTIME_DIR="$full_home/runtime" \
  bash -c 'run() { "$@"; }; source "$1"' bash "$clipboard_activation"
cmp "$test_root/custom-shell.json" "$full_home/.config/omarchy/shell.json"
HOME="$full_home" USER=omanixy-test XDG_RUNTIME_DIR="$full_home/runtime" \
  bash -c 'run() { "$@"; }; source "$1"' bash "$full_activation"
cmp "$test_root/custom-shell.json" "$full_home/.config/omarchy/shell.json"
HOME="$full_home" USER=omanixy-test XDG_RUNTIME_DIR="$full_home/runtime" \
  bash -c 'run() { "$@"; }; source "$1"' bash "$core_activation"
cmp "$test_root/custom-shell.json" "$full_home/.config/omarchy/shell.json"
HOME="$full_home" USER=omanixy-test XDG_RUNTIME_DIR="$full_home/runtime" \
  bash -c 'run() { "$@"; }; source "$1"' bash "$clipboard_activation"
cmp "$test_root/custom-shell.json" "$full_home/.config/omarchy/shell.json"

core_home="$test_root/core-home"
mkdir -p "$core_home"
HOME="$core_home" USER=omanixy-test XDG_RUNTIME_DIR="$core_home/runtime" \
  bash -c 'run() { "$@"; }; source "$1"' bash "$full_activation"
cp "$core_home/.config/omarchy/shell.json" "$test_root/core-full-shell.json"
HOME="$core_home" USER=omanixy-test XDG_RUNTIME_DIR="$core_home/runtime" \
  bash -c 'run() { "$@"; }; source "$1"' bash "$core_activation"
cmp "$test_root/core-full-shell.json" "$core_home/.config/omarchy/shell.json"
HOME="$core_home" USER=omanixy-test XDG_RUNTIME_DIR="$core_home/runtime" \
  bash -c 'run() { "$@"; }; source "$1"' bash "$core_activation"
cmp "$test_root/core-full-shell.json" "$core_home/.config/omarchy/shell.json"

clipboard_path=$(runtime_path "$clipboard_runtime")
full_path=$(runtime_path "$full_runtime")

test -x "$full_runtime/bin/omarchy-audio-output-set-default"
test -x "$full_runtime/bin/omarchy-weather-status"
test -x "$full_runtime/bin/omarchy-network-status"
test -x "$full_runtime/bin/omarchy-monitor-state"
test -x "$full_runtime/bin/omarchy-powerprofiles-list"
test -x "$full_runtime/bin/omarchy-bluetooth-device"
PATH="$full_path" command -v pactl >/dev/null
PATH="$full_path" command -v curl >/dev/null
PATH="$full_path" command -v nmcli >/dev/null

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
for backend in pactl wpctl bluetoothctl nmcli hyprctl brightnessctl curl notify-send; do
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
  local root=$1 expected=$2 name=$3
  local harness="$test_root/$name.qml"
  local qml_root="$test_root/$name"
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
        return { disabledPlugins: [], bar: { layout: { left: [], center: [], right: [] } } }
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

run_registry_policy "$full_root" '["omarchy.audio", "omarchy.bluetooth", "omarchy.clipboard", "omarchy.emojis", "omarchy.monitor", "omarchy.network", "omarchy.power", "omarchy.weather"]' full
run_registry_policy "$clipboard_root" '["omarchy.clipboard", "omarchy.emojis"]' clipboard
run_registry_policy "$core_root" '[]' core

printf '%s\n' 'feature lifecycle checks passed'
