#!/usr/bin/env bash
set -euo pipefail

core_polkit_compat_bin=${1:?core+polkit compatibility bin required}
core_compat_bin=${2:?core-only compatibility bin required}
core_closure_paths=${3:?core-only closure store paths required}
core_polkit_closure_paths=${4:?core+polkit closure store paths required}
core_declared_runtime_inputs=${5:?core-only declared runtime inputs json required}
core_polkit_declared_runtime_inputs=${6:?core+polkit declared runtime inputs json required}

# Parallels test/security-lock-core-only.sh: programs.omanixy.security.
# polkit.agent must not widen the dependency surface of a core-only build.
# Unlike security.lock, the adapted polkit agent needs no compat helper at
# all (patch-polkit-agent removes the only external Process the pinned
# source had), so the bin/ delta here is expected to be exactly empty -
# stronger than the lock case, not merely "one new helper and nothing else".
jq -e '.selectedFeatures == ["core"] and .selectedCapabilities == ["core-runtime"]' \
  "$core_polkit_compat_bin/feature-surface.json" >/dev/null
jq -e '.selectedFeatures == ["core"] and .selectedCapabilities == ["core-runtime"]' \
  "$core_compat_bin/feature-surface.json" >/dev/null

diff -u \
  <(find "$core_compat_bin/bin" -mindepth 1 -maxdepth 1 -printf '%f\n' | sort) \
  <(find "$core_polkit_compat_bin/bin" -mindepth 1 -maxdepth 1 -printf '%f\n' | sort)

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
  omarchy-hyprland-session-locked omarchy-lock-fingerprint-ready \
  ; do
  if [[ -e "$core_polkit_compat_bin/bin/$helper" ]]; then
    printf 'core+polkit build unexpectedly packages helper %s\n' "$helper" >&2
    exit 1
  fi
done

# Declared-input-level proof: exact equality, not merely "no new package
# name" - achievable here (unlike a hypothetical capability that genuinely
# needs a new package) because polkit rides entirely on what the selected
# Quickshell package itself already links against.
diff -u \
  <(jq -S . "$core_declared_runtime_inputs") \
  <(jq -S . "$core_polkit_declared_runtime_inputs")

# Closure-level proof: turning on security.polkit.agent against a core-only
# build must not widen the dependency surface at all.
strip_hashes() {
  sed -E 's#^/nix/store/[a-z0-9]{32}-##' "$1" | sort -u
}

new_names=$(comm -13 <(strip_hashes "$core_closure_paths") <(strip_hashes "$core_polkit_closure_paths"))
if [[ -n "$new_names" ]]; then
  printf 'security.polkit.agent widens the core-only closure with new package(s):\n%s\n' "$new_names" >&2
  exit 1
fi

printf '%s\n' 'security polkit core-only independence checks passed'
