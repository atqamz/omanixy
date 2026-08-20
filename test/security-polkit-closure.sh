#!/usr/bin/env bash
set -euo pipefail

polkit_runtime=${1:?polkit-enabled runtime package required}
polkit_closure_paths=${2:?polkit-enabled closure store paths required}
polkit_compat_bin=${3:?polkit-enabled compatibility bin required}
disabled_compat_bin=${4:?polkit-disabled compatibility bin required}
polkit_compat_root=${5:?polkit-enabled compatibility root required}

# Focused security.polkit.agent closure check, separate from the
# presentation-feature runtime-closure check: proves the polkit-agent
# capability pulls in nothing beyond what the selected Quickshell package
# itself already links against, and that the runtime/source-tree contents
# are exactly what Layer 5 owns - no lock, fingerprint, idle, or
# notification surface dragged in alongside it.
grep -Fxq "$polkit_runtime" "$polkit_closure_paths"

if grep -Ei 'fprintd' "$polkit_closure_paths"; then
  printf '%s\n' 'fprintd reachable from the polkit-agent-enabled runtime closure' >&2
  exit 1
fi

# Unlike security.lock (which adds omarchy-hyprland-session-locked), the
# adapted polkit agent needs no compat-bin executable at all: the bin/
# listing must be byte-identical, not merely "one new helper".
diff -u \
  <(find "$disabled_compat_bin/bin" -mindepth 1 -maxdepth 1 -printf '%f\n' | sort) \
  <(find "$polkit_compat_bin/bin" -mindepth 1 -maxdepth 1 -printf '%f\n' | sort)

test -f "$polkit_compat_root/shell/plugins/polkit/manifest.json"
test -f "$polkit_compat_root/shell/plugins/polkit/PolkitAgent.qml"
test -f "$polkit_compat_root/shell/plugins/polkit/PolkitModel.js"

test ! -e "$polkit_compat_root/shell/plugins/lock"
test ! -e "$polkit_compat_root/shell/plugins/services/idle"
test ! -e "$polkit_compat_root/shell/plugins/notifications"

printf '%s\n' 'security polkit closure invariants passed'
