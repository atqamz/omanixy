#!/usr/bin/env bash
set -euo pipefail

lock_idle_compat_bin=${1:?lock+idle compatibility bin required}
lock_compat_bin=${2:?lock-only compatibility bin required}
lock_closure_paths=${3:?lock-only closure store paths required}
lock_idle_closure_paths=${4:?lock+idle closure store paths required}
lock_declared_runtime_inputs=${5:?lock-only declared runtime inputs json required}
lock_idle_declared_runtime_inputs=${6:?lock+idle declared runtime inputs json required}
lock_expected_changed=${7:?lock-only expected-changed self derivations list required}
lock_idle_expected_changed=${8:?lock+idle expected-changed self derivations list required}

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT


diff -u \
  <(find "$lock_compat_bin/bin" -mindepth 1 -maxdepth 1 -printf '%f\n' | sort) \
  <(find "$lock_idle_compat_bin/bin" -mindepth 1 -maxdepth 1 -printf '%f\n' | sort | grep -Fxv omanixy-idle-state)
test -L "$lock_idle_compat_bin/bin/omanixy-idle-state"
test ! -e "$lock_compat_bin/bin/omanixy-idle-state"

for helper in \
  ttfx socat omarchy-launch-screensaver omarchy-screensaver \
  omarchy-lock-fingerprint-ready omarchy-notification-send \
  ; do
  if [[ -e "$lock_idle_compat_bin/bin/$helper" ]]; then
    printf 'lock+idle build unexpectedly packages helper %s\n' "$helper" >&2
    exit 1
  fi
done
if grep -Eiq 'alacritty|ghostty|kitty|foot' "$lock_idle_closure_paths"; then
  printf '%s\n' 'a terminal emulator is unexpectedly reachable from the lock+idle closure' >&2
  exit 1
fi
if grep -Eiq 'fprintd|notification-daemon' "$lock_idle_closure_paths"; then
  printf '%s\n' 'fprintd/notification-daemon is unexpectedly reachable from the lock+idle closure' >&2
  exit 1
fi

diff -u \
  <(jq -S . "$lock_declared_runtime_inputs") \
  <(jq -S . "$lock_idle_declared_runtime_inputs")

comm -13 <(sort "$lock_closure_paths") <(sort "$lock_idle_closure_paths") >"$work/new-paths"
comm -23 <(sort "$lock_closure_paths") <(sort "$lock_idle_closure_paths") >"$work/removed-paths"

unexpected_new=$(comm -23 <(sort "$work/new-paths") <(sort "$lock_idle_expected_changed"))
if [[ -n "$unexpected_new" ]]; then
  printf 'security.idle.enable adds unexpected new store path(s) to the lock-only closure:\n%s\n' "$unexpected_new" >&2
  exit 1
fi

unexpected_removed=$(comm -23 <(sort "$work/removed-paths") <(sort "$lock_expected_changed"))
if [[ -n "$unexpected_removed" ]]; then
  printf 'security.idle.enable removes unexpected store path(s) from the lock-only closure:\n%s\n' "$unexpected_removed" >&2
  exit 1
fi

comm -23 <(sort "$lock_closure_paths") <(sort "$lock_expected_changed") >"$work/lock-external"
comm -23 <(sort "$lock_idle_closure_paths") <(sort "$lock_idle_expected_changed") >"$work/lock-idle-external"
diff -u "$work/lock-external" "$work/lock-idle-external"

printf '%s\n' 'security idle closure independence checks passed'
