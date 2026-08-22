#!/usr/bin/env bash
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

test "$standalone_agent_disabled_ok" = true
test "$standalone_agent_enabled_ok" = false
test "$integrated_off_off_ok" = true
test "$integrated_on_off_ok" = true
test "$integrated_off_on_ok" = false
test "$integrated_on_on_ok" = true
test "$integrated_on_on_hypr_conflict_ok" = false
test "$integrated_on_on_gnome_conflict_ok" = false
test "$agent_off_hypr_ok" = true
test "$agent_off_gnome_ok" = true
test "$lock_on_agent_off_ok" = true

printf '%s\n' 'polkit Home Manager assertion matrix checks passed'
