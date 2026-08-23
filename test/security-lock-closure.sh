#!/usr/bin/env bash
set -euo pipefail

lock_runtime=${1:?lock-enabled runtime package required}
lock_closure_paths=${2:?lock-enabled closure store paths required}
lock_compat_bin=${3:?lock-enabled compatibility bin required}
disabled_compat_bin=${4:?lock-disabled compatibility bin required}

grep -Fxq "$lock_runtime" "$lock_closure_paths"

if grep -Ei 'fprintd' "$lock_closure_paths"; then
  printf '%s\n' 'fprintd reachable from the lock-enabled runtime closure' >&2
  exit 1
fi

diff -u \
  <(find "$disabled_compat_bin/bin" -mindepth 1 -maxdepth 1 -printf '%f\n' | sort) \
  <(find "$lock_compat_bin/bin" -mindepth 1 -maxdepth 1 -printf '%f\n' | sort | grep -Fxv omarchy-hyprland-session-locked)

test -L "$lock_compat_bin/bin/omarchy-hyprland-session-locked"

printf '%s\n' 'security lock closure invariants passed'
