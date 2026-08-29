#!/usr/bin/env bash
set -euo pipefail

weather_runtime=${1:?weather runtime path required}
bluetooth_runtime=${2:?bluetooth runtime path required}
audio_runtime=${3:?audio runtime path required}
launcher_runtime=${4:?launcher runtime path required}
screenshot_runtime=${5:?screenshot runtime path required}
core_runtime=${6:?core runtime path required}
monitor_runtime=${7:?monitor runtime path required}

runtime_path() {
  sed -n 's/^export PATH="\(.*\)"$/\1/p' "$1/bin/omanixy-shell-runtime"
}

weather_path=$(runtime_path "$weather_runtime")
test -x "$weather_runtime/bin/omarchy-weather-status"
test -x "$weather_runtime/bin/omarchy-notification-send"
PATH="$weather_path" command -v curl >/dev/null
PATH="$weather_path" command -v notify-send >/dev/null
test ! -x "$weather_runtime/bin/omarchy-network-status"
test ! -x "$weather_runtime/bin/omarchy-audio-output-set-default"

weather_state=$(mktemp -d)
weather_bin=""
weather_script=""
trap 'rm -rf "$weather_state" "$weather_bin"; rm -f "$weather_script"' EXIT
mkdir -p "$weather_state/omarchy/settings"
printf '%s\n' '{"name":"Jakarta"}' > "$weather_state/omarchy/settings/weather.json"
weather_bin=$(mktemp -d)
printf '%s\n' '#!/bin/sh' 'printf "%s\\n" "12°C|5 km/h"' > "$weather_bin/curl"
chmod 0555 "$weather_bin/curl"
weather_script=$(mktemp)
sed "s|^export PATH=\"|export PATH=\"$weather_bin:|" \
  "$weather_runtime/bin/omarchy-weather-status" > "$weather_script"
chmod 0555 "$weather_script"
if ! COMPAT_ADAPTER_NAME=omarchy-weather-status XDG_STATE_HOME="$weather_state" \
  "$weather_script" > "$weather_state/status"; then
  printf '%s\n' 'weather status could not read the selected weather feature state' >&2
  exit 1
fi
grep -Fq 'Jakarta' "$weather_state/status"

bluetooth_path=$(runtime_path "$bluetooth_runtime")
test -x "$bluetooth_runtime/bin/omarchy-bluetooth-device"
test -x "$bluetooth_runtime/bin/omarchy-audio-output-set-default"
PATH="$bluetooth_path" command -v pactl >/dev/null
test ! -x "$bluetooth_runtime/bin/omarchy-network-status"

audio_path=$(runtime_path "$audio_runtime")
test -x "$audio_runtime/bin/omarchy-audio-output-set-default"
test ! -x "$audio_runtime/bin/omarchy-bluetooth-device"
test ! -x "$audio_runtime/bin/omarchy-notification-send"
PATH="$audio_path" command -v wpctl >/dev/null

launcher_path=$(runtime_path "$launcher_runtime")
test -x "$launcher_runtime/bin/omarchy-remove-launcher-entry"
PATH="$launcher_path" command -v uwsm-app >/dev/null
PATH="$launcher_path" command -v xdg-terminal-exec >/dev/null
PATH="$launcher_path" command -v foot >/dev/null
test ! -x "$launcher_runtime/bin/omarchy-network-status"

screenshot_path=$(runtime_path "$screenshot_runtime")
test -x "$screenshot_runtime/bin/omarchy-capture-screenshot"
test -x "$screenshot_runtime/bin/omarchy-notification-send"
PATH="$screenshot_path" command -v grim >/dev/null
PATH="$screenshot_path" command -v fc-match >/dev/null
PATH="$screenshot_path" command -v wl-copy >/dev/null
PATH="$screenshot_path" command -v notify-send >/dev/null
test ! -x "$screenshot_runtime/bin/omarchy-weather-status"

monitor_path=$(runtime_path "$monitor_runtime")
test -x "$monitor_runtime/bin/omarchy-monitor-state"
test -x "$monitor_runtime/bin/omarchy-hyprland-monitor-scaling"
test -x "$monitor_runtime/bin/omarchy-brightness-display"
test ! -x "$monitor_runtime/bin/omarchy-capture-screenshot"
PATH="$monitor_path" command -v brightnessctl >/dev/null
PATH="$monitor_path" command -v hyprctl >/dev/null

monitor_error=$(mktemp)
for helper in omarchy-monitor-state omarchy-hyprland-monitor-scaling; do
  if "$monitor_runtime/bin/$helper" >/dev/null 2>"$monitor_error"; then
    printf '%s\n' "$helper unexpectedly succeeded without a live compositor" >&2
    exit 1
  fi
  if grep -Fq 'required backend is unavailable' "$monitor_error"; then
    printf '%s\n' "$helper lacks a pinned backend in the monitor feature runtime" >&2
    cat "$monitor_error" >&2
    exit 1
  fi
done
rm -f "$monitor_error"

core_path=$(runtime_path "$core_runtime")
test -x "$core_runtime/bin/omarchy-system-stats"
test ! -x "$core_runtime/bin/omarchy-network-status"
test ! -x "$core_runtime/bin/omarchy-remove-launcher-entry"
PATH="$core_path" command -v jq >/dev/null

printf '%s\n' 'feature dependency closure passed'
