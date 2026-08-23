#!/usr/bin/env bash
set -euo pipefail

lock_only_service_qml=${1:?lock-only shell/plugins/lock/Service.qml required}
lock_idle_service_qml=${2:?lock+idle shell/plugins/lock/Service.qml required}

# Section 10/46: Layer 6 never blanks the display and owns no DPMS/hyprctl/
# brightness/clamshell policy of its own - enabling security.idle must add
# zero code to Layer 3's own lock plugin. A byte-for-byte comparison, not a
# grep for a handful of banned tokens, so any change at all (not just the
# ones this test happened to think of) fails closed.
cmp "$lock_only_service_qml" "$lock_idle_service_qml"

printf '%s\n' 'security idle no-DPMS-widening checks passed'
