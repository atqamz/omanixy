#!/usr/bin/env bash
set -euo pipefail

all_off_ok=${1:?}
idle_on_lock_off_ok=${2:?}
idle_on_lock_on_ok=${3:?}
hypridle_conflict_ok=${4:?}
swayidle_conflict_ok=${5:?}
both_conflict_ok=${6:?}
idle_off_both_daemons_on_ok=${7:?}
idle_on_fingerprint_on_ok=${8:?}
idle_on_polkit_on_ok=${9:?}
idle_off_lock_on_ok=${10:?}

test "$all_off_ok" = true
test "$idle_on_lock_off_ok" = false
test "$idle_on_lock_on_ok" = true
test "$hypridle_conflict_ok" = false
test "$swayidle_conflict_ok" = false
test "$both_conflict_ok" = false
test "$idle_off_both_daemons_on_ok" = true
test "$idle_on_fingerprint_on_ok" = true
test "$idle_on_polkit_on_ok" = true
test "$idle_off_lock_on_ok" = true

printf '%s\n' 'idle Home Manager assertion matrix checks passed'
