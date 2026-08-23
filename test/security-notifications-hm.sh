#!/usr/bin/env bash
# Home Manager assertion matrix for
# programs.omanixy.security.notifications.daemon.enable. Unlike
# lock/fingerprint/polkit/idle, the daemon requires no NixOS pairing at all
# (pure session D-Bus ownership), so every case here is a standalone Home
# Manager evaluation - there is no integrated NixOS+Home Manager matrix to
# cross it against.
set -euo pipefail

daemon_off_ok=${1:?}
daemon_on_ok=${2:?}
mako_conflict_ok=${3:?}
dunst_conflict_ok=${4:?}
swaync_conflict_ok=${5:?}
fnott_conflict_ok=${6:?}
off_all_conflicts_on_ok=${7:?}
with_client_feature_ok=${8:?}

# 1/8: daemon off (default) - PASS (baseline, same as the zero-capability default).
test "$daemon_off_ok" = true
# 2/8: daemon on, no conflicting daemons - PASS (minimal valid daemon).
test "$daemon_on_ok" = true
# 3/8: daemon on, mako also on - FAIL (known-conflict assertion).
test "$mako_conflict_ok" = false
# 4/8: daemon on, dunst also on - FAIL (known-conflict assertion).
test "$dunst_conflict_ok" = false
# 5/8: daemon on, swaync also on - FAIL (known-conflict assertion).
test "$swaync_conflict_ok" = false
# 6/8: daemon on, fnott also on - FAIL (known-conflict assertion).
test "$fnott_conflict_ok" = false
# 7/8: daemon off, all four known daemons on - PASS (the conflict assertions
# are vacuous while the daemon itself is off; Omanixy never touches any of
# them).
test "$off_all_conflicts_on_ok" = true
# 8/8: daemon on together with the notification-send client presentation
# feature explicitly selected - PASS (independent axes).
test "$with_client_feature_ok" = true

printf '%s\n' 'notifications Home Manager assertion matrix checks passed'
