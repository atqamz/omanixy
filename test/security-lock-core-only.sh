#!/usr/bin/env bash
set -euo pipefail

core_lock_compat_bin=${1:?core+lock compatibility bin required}
core_compat_bin=${2:?core-only compatibility bin required}
core_closure_paths=${3:?core-only closure store paths required}
core_lock_closure_paths=${4:?core+lock closure store paths required}
core_declared_runtime_inputs=${5:?core-only declared runtime inputs json required}
core_lock_declared_runtime_inputs=${6:?core+lock declared runtime inputs json required}

jq -e '.selectedFeatures == ["core"] and .selectedCapabilities == ["core-runtime"]' \
  "$core_lock_compat_bin/feature-surface.json" >/dev/null
jq -e '.selectedFeatures == ["core"] and .selectedCapabilities == ["core-runtime"]' \
  "$core_compat_bin/feature-surface.json" >/dev/null

test -L "$core_lock_compat_bin/bin/omarchy-hyprland-session-locked"
test ! -e "$core_compat_bin/bin/omarchy-hyprland-session-locked"

diff -u \
  <(find "$core_compat_bin/bin" -mindepth 1 -maxdepth 1 -printf '%f\n' | sort) \
  <(find "$core_lock_compat_bin/bin" -mindepth 1 -maxdepth 1 -printf '%f\n' | sort | grep -Fxv omarchy-hyprland-session-locked)

for helper in \
  omarchy-weather-location omarchy-weather-status omarchy-notification-send \
  omarchy-audio-output-set-default omarchy-audio-input-set-default \
  omarchy-audio-output-sink omarchy-audio-sink-availability \
  omarchy-network-status omarchy-network-qr omarchy-network-password \
  omarchy-network-band omarchy-dns omarchy-bluetooth-device omarchy-bluetooth-power \
  omarchy-battery-status omarchy-powerprofiles-list omarchy-powerprofiles-set \
  omarchy-monitor-state omarchy-hyprland-monitor-scaling \
  omarchy-clipboard-paste-text omarchy-clipboard-paste-file omarchy-clipboard-open \
  omarchy-menu-emoji-insert omarchy-capture-screenshot omarchy-remove-launcher-entry \
  ; do
  if [[ -e "$core_lock_compat_bin/bin/$helper" ]]; then
    printf 'core+lock build unexpectedly packages presentation helper %s\n' "$helper" >&2
    exit 1
  fi
done

diff -u \
  <(jq -S . "$core_declared_runtime_inputs") \
  <(jq -S . "$core_lock_declared_runtime_inputs")

strip_hashes() {
  sed -E 's#^/nix/store/[a-z0-9]{32}-##' "$1" | sort -u
}

new_names=$(comm -13 <(strip_hashes "$core_closure_paths") <(strip_hashes "$core_lock_closure_paths"))
if [[ -n "$new_names" ]]; then
  printf 'security.lock widens the core-only closure with new package(s):\n%s\n' "$new_names" >&2
  exit 1
fi

printf '%s\n' 'security lock core-only independence checks passed'
