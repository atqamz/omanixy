#!/usr/bin/env bash
# Home Manager x NixOS assertion matrix for
# programs.omanixy.security.idle.enable, mirroring test/security-polkit-hm.sh's
# structure. All 10 cases from the Layer-6 spec: idle-requires-lock,
# hypridle/swayidle conflicts (both individually and together), the
# conflict assertions being vacuous while idle itself is off, and idle's
# independence from both fingerprint and polkit.
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

# 1/10: everything off - PASS (baseline).
test "$all_off_ok" = true
# 2/10: idle on, lock off - FAIL (idle requires the native lock).
test "$idle_on_lock_off_ok" = false
# 3/10: idle on, lock on, no conflicting daemons - PASS (minimal valid idle).
test "$idle_on_lock_on_ok" = true
# 4/10: idle+lock on, hypridle also on - FAIL (known-conflict assertion).
test "$hypridle_conflict_ok" = false
# 5/10: idle+lock on, swayidle also on - FAIL (known-conflict assertion).
test "$swayidle_conflict_ok" = false
# 6/10: idle+lock on, both hypridle and swayidle on - FAIL (both conflicts at once).
test "$both_conflict_ok" = false
# 7/10: idle off, hypridle and swayidle both on - PASS (the conflict
# assertions are vacuous while idle itself is off; Omanixy never touches
# either daemon).
test "$idle_off_both_daemons_on_ok" = true
# 8/10: idle+lock on, fingerprint also on - PASS (idle is independent of
# fingerprint).
test "$idle_on_fingerprint_on_ok" = true
# 9/10: idle+lock on, polkit agent also on - PASS (idle is independent of
# polkit, for the same reason).
test "$idle_on_polkit_on_ok" = true
# 10/10: lock on, idle off - PASS, proving lock enablement never requires
# or depends on idle.
test "$idle_off_lock_on_ok" = true

printf '%s\n' 'idle Home Manager assertion matrix checks passed'
