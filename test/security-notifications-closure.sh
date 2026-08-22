#!/usr/bin/env bash
set -euo pipefail

core_compat_bin=${1:?core-only compatibility bin required}
core_notification_daemon_compat_bin=${2:?core+notification-daemon compatibility bin required}
core_closure_paths=${3:?core-only closure store paths required}
core_notification_daemon_closure_paths=${4:?core+notification-daemon closure store paths required}
core_declared_runtime_inputs=${5:?core-only declared runtime inputs json required}
core_notification_daemon_declared_runtime_inputs=${6:?core+notification-daemon declared runtime inputs json required}
core_expected_changed=${7:?core-only expected-changed self derivations list required}
core_notification_daemon_expected_changed=${8:?core+notification-daemon expected-changed self derivations list required}

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT


diff -u \
  <(find "$core_compat_bin/bin" -mindepth 1 -maxdepth 1 -printf '%f\n' | sort) \
  <(find "$core_notification_daemon_compat_bin/bin" -mindepth 1 -maxdepth 1 -printf '%f\n' | sort | grep -Fxv omanixy-notification-state)
test -L "$core_notification_daemon_compat_bin/bin/omanixy-notification-state"
test ! -e "$core_compat_bin/bin/omanixy-notification-state"

for helper in \
  omarchy-hyprland-session-locked omarchy-lock-fingerprint-ready \
  omanixy-idle-state omarchy-notification-send \
  ; do
  if [[ -e "$core_notification_daemon_compat_bin/bin/$helper" ]]; then
    printf 'core+notification-daemon build unexpectedly packages helper %s\n' "$helper" >&2
    exit 1
  fi
done
if grep -Eiq 'alacritty|ghostty|kitty|foot' "$core_notification_daemon_closure_paths"; then
  printf '%s\n' 'a terminal emulator is unexpectedly reachable from the core+notification-daemon closure' >&2
  exit 1
fi
if grep -Eiq 'fprintd|^/nix/store/[a-z0-9]+-mako-|^/nix/store/[a-z0-9]+-dunst-|^/nix/store/[a-z0-9]+-swaync-|^/nix/store/[a-z0-9]+-fnott-' "$core_notification_daemon_closure_paths"; then
  printf '%s\n' 'fprintd or a known conflicting notification daemon package is unexpectedly reachable from the core+notification-daemon closure' >&2
  exit 1
fi

diff -u \
  <(jq -S . "$core_declared_runtime_inputs") \
  <(jq -S . "$core_notification_daemon_declared_runtime_inputs")

comm -13 <(sort "$core_closure_paths") <(sort "$core_notification_daemon_closure_paths") >"$work/new-paths"
comm -23 <(sort "$core_closure_paths") <(sort "$core_notification_daemon_closure_paths") >"$work/removed-paths"

unexpected_new=$(comm -23 <(sort "$work/new-paths") <(sort "$core_notification_daemon_expected_changed"))
if [[ -n "$unexpected_new" ]]; then
  printf 'security.notifications.daemon.enable adds unexpected new store path(s) to the core-only closure:\n%s\n' "$unexpected_new" >&2
  exit 1
fi

unexpected_removed=$(comm -23 <(sort "$work/removed-paths") <(sort "$core_expected_changed"))
if [[ -n "$unexpected_removed" ]]; then
  printf 'security.notifications.daemon.enable removes unexpected store path(s) from the core-only closure:\n%s\n' "$unexpected_removed" >&2
  exit 1
fi

comm -23 <(sort "$core_closure_paths") <(sort "$core_expected_changed") >"$work/core-external"
comm -23 <(sort "$core_notification_daemon_closure_paths") <(sort "$core_notification_daemon_expected_changed") >"$work/core-notification-daemon-external"
diff -u "$work/core-external" "$work/core-notification-daemon-external"

printf '%s\n' 'security notifications closure independence checks passed'
