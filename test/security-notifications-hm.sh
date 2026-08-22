#!/usr/bin/env bash
set -euo pipefail

daemon_off_ok=${1:?}
daemon_on_ok=${2:?}
mako_conflict_ok=${3:?}
dunst_conflict_ok=${4:?}
swaync_conflict_ok=${5:?}
fnott_conflict_ok=${6:?}
off_all_conflicts_on_ok=${7:?}
with_client_feature_ok=${8:?}

test "$daemon_off_ok" = true
test "$daemon_on_ok" = true
test "$mako_conflict_ok" = false
test "$dunst_conflict_ok" = false
test "$swaync_conflict_ok" = false
test "$fnott_conflict_ok" = false
test "$off_all_conflicts_on_ok" = true
test "$with_client_feature_ok" = true

printf '%s\n' 'notifications Home Manager assertion matrix checks passed'
