#!/usr/bin/env bash
set -euo pipefail

core_lock_compat_bin=${1:?core+lock compatibility bin required}
core_compat_bin=${2:?core-only compatibility bin required}
core_closure_paths=${3:?core-only closure store paths required}
core_lock_closure_paths=${4:?core+lock closure store paths required}

# Section 11: security.lock must not widen the dependency surface of a
# core-only build. Presentation features (network, audio, bluetooth,
# weather, monitor, power, screenshot, clipboard, launcher, ...) must stay
# entirely absent whether or not the lock capability is turned on - lock
# rides entirely on core-runtime (hyprctl/jq), the same capability core
# already requires.
jq -e '.selectedFeatures == ["core"] and .selectedCapabilities == ["core-runtime"]' \
  "$core_lock_compat_bin/feature-surface.json" >/dev/null
jq -e '.selectedFeatures == ["core"] and .selectedCapabilities == ["core-runtime"]' \
  "$core_compat_bin/feature-surface.json" >/dev/null

test -L "$core_lock_compat_bin/bin/omarchy-hyprland-session-locked"
test ! -e "$core_compat_bin/bin/omarchy-hyprland-session-locked"

# The lock capability adds exactly one binary to the core-only compat bin:
# the stranded-lock helper. Nothing presentation-related appears alongside it.
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

# Closure-level proof: turning on security.lock against a core-only build
# must not widen the dependency surface at all. A hardcoded list of
# presentation-package name patterns is the wrong tool here - core-runtime
# (via hyprland/systemd) already unconditionally pulls in things like
# pipewire, bluez, libnotify and uwsm with no Omanixy feature or capability
# selecting them, so any such list either drifts out of sync with the real
# baseline or asserts something false about core-only itself. Instead,
# compare the two closures directly by package name (store hash stripped):
# turning security.lock on must add zero new package names.
strip_hashes() {
  sed -E 's#^/nix/store/[a-z0-9]{32}-##' "$1" | sort -u
}

new_names=$(comm -13 <(strip_hashes "$core_closure_paths") <(strip_hashes "$core_lock_closure_paths"))
if [[ -n "$new_names" ]]; then
  printf 'security.lock widens the core-only closure with new package(s):\n%s\n' "$new_names" >&2
  exit 1
fi

printf '%s\n' 'security lock core-only independence checks passed'
