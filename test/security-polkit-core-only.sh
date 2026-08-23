#!/usr/bin/env bash
set -euo pipefail

core_polkit_compat_bin=${1:?core+polkit compatibility bin required}
core_compat_bin=${2:?core-only compatibility bin required}
core_closure_paths=${3:?core-only closure store paths required}
core_polkit_closure_paths=${4:?core+polkit closure store paths required}
core_declared_runtime_inputs=${5:?core-only declared runtime inputs json required}
core_polkit_declared_runtime_inputs=${6:?core+polkit declared runtime inputs json required}
core_expected_changed=${7:?core-only expected-changed self derivations list required}
core_polkit_expected_changed=${8:?core+polkit expected-changed self derivations list required}

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

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

# Raw store-path closure proof. Unlike a hash-stripped package-NAME
# comparison (which only proves no new package name appears anywhere, and
# would silently accept a same-named-but-differently-built external
# dependency, or a byte-for-byte content change disguised as "the same
# package"), this compares the actual store paths in each closure directly.
#
# The Omanixy-owned compatibility root, and everything that references its
# store path in its own build (ipc, compatAdapter, the runtime script, the
# compatibility bin, and the final package itself), are EXPECTED to change
# identity, because the compatibility root's contents genuinely differ
# (the polkit plugin becomes reachable). Passing their exact store paths in
# - rather than filtering by an /^omanixy-/ name pattern - means only that
# specific, named, reviewed set of self-derivations is allowed to differ;
# anything else that changed identity would show up as an unexpected
# difference below and fail this check.
comm -13 <(sort "$core_closure_paths") <(sort "$core_polkit_closure_paths") >"$work/new-paths"
comm -23 <(sort "$core_closure_paths") <(sort "$core_polkit_closure_paths") >"$work/removed-paths"

unexpected_new=$(comm -23 <(sort "$work/new-paths") <(sort "$core_polkit_expected_changed"))
if [[ -n "$unexpected_new" ]]; then
  printf 'security.polkit.agent adds unexpected new store path(s) to the core-only closure:\n%s\n' "$unexpected_new" >&2
  exit 1
fi

unexpected_removed=$(comm -23 <(sort "$work/removed-paths") <(sort "$core_expected_changed"))
if [[ -n "$unexpected_removed" ]]; then
  printf 'security.polkit.agent removes unexpected store path(s) from the core-only closure:\n%s\n' "$unexpected_removed" >&2
  exit 1
fi

# After excluding ONLY the explicitly-expected-changed Omanixy self
# derivations, every remaining (i.e. external) store path must be
# byte-identical between the two closures - not merely same-named.
comm -23 <(sort "$core_closure_paths") <(sort "$core_expected_changed") >"$work/core-external"
comm -23 <(sort "$core_polkit_closure_paths") <(sort "$core_polkit_expected_changed") >"$work/core-polkit-external"
diff -u "$work/core-external" "$work/core-polkit-external"

printf '%s\n' 'security polkit core-only independence checks passed'
