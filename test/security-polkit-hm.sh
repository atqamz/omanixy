#!/usr/bin/env bash
# Home Manager x NixOS assertion matrix for
# programs.omanixy.security.polkit.agent.enable, mirroring
# test/security-lock.sh's structure. All 12 cases from the Layer-5 spec;
# lock is left at its default (false) throughout the integrated cases,
# which is itself the proof that polkit needs no lock involvement (cases
# 6/11), and case 12 reuses the existing lock-on/agent-off fixture directly
# (lock enabled, polkit untouched) to prove the same independence from the
# other direction.
set -euo pipefail

standalone_agent_disabled_ok=${1:?}
standalone_agent_enabled_ok=${2:?}
integrated_off_off_ok=${3:?}
integrated_on_off_ok=${4:?}
integrated_off_on_ok=${5:?}
integrated_on_on_ok=${6:?}
integrated_on_on_hypr_conflict_ok=${7:?}
integrated_on_on_gnome_conflict_ok=${8:?}
agent_off_hypr_ok=${9:?}
agent_off_gnome_ok=${10:?}
lock_on_agent_off_ok=${11:?}

# 1/12: standalone HM, agent=false - PASS.
test "$standalone_agent_disabled_ok" = true
# 2/12: standalone HM, agent=true - FAIL (no osConfig to provision the
# paired NixOS system capability).
test "$standalone_agent_enabled_ok" = false
# 3/12: integrated, system=false, agent=false - PASS.
test "$integrated_off_off_ok" = true
# 4/12: integrated, system=true, agent=false - PASS.
test "$integrated_on_off_ok" = true
# 5/12: integrated, system=false, agent=true - FAIL (paired-capability
# assertion).
test "$integrated_off_on_ok" = false
# 6/12 (and 11/12: lock left disabled throughout this whole matrix): both
# on, no competing agent - PASS.
test "$integrated_on_on_ok" = true
# 7/12: both on, hyprpolkitagent also on - FAIL (known-conflict assertion).
test "$integrated_on_on_hypr_conflict_ok" = false
# 8/12: both on, polkit-gnome also on - FAIL (known-conflict assertion).
test "$integrated_on_on_gnome_conflict_ok" = false
# 9/12: agent off, hyprpolkitagent on - PASS (conflict assertion is vacuous
# while the Quattro agent itself is off; Omanixy never touches the other
# agent).
test "$agent_off_hypr_ok" = true
# 10/12: agent off, polkit-gnome on - PASS, same reasoning.
test "$agent_off_gnome_ok" = true
# 12/12: lock=true, polkit agent=false (reusing the existing Layer-3
# lock-on/pam-on integrated fixture unchanged) - PASS, proving lock
# enablement never requires or depends on polkit.
test "$lock_on_agent_off_ok" = true

printf '%s\n' 'polkit Home Manager assertion matrix checks passed'
