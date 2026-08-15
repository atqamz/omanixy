#!/usr/bin/env bash
set -euo pipefail

unit=${1:?rendered service unit required}
runtime=${2:?runtime package path required}
omarchy_source=${3:?Omarchy source path required}
compatibility_root=${4:?compatibility root path required}

unit_values() {
  local key=$1
  awk -F= -v key="$key" '$1 == key { print substr($0, length(key) + 2) }' "$unit"
}

unit_has() {
  local key=$1 expected=$2
  while IFS= read -r value; do
    [[ $value == "$expected" ]] && return 0
  done < <(unit_values "$key")
  return 1
}

unit_has ExecStart "$runtime/bin/omanixy-shell-runtime"
unit_has PartOf graphical-session.target
unit_has After graphical-session.target
unit_has WantedBy graphical-session.target
unit_has StartLimitIntervalSec 60s
unit_has StartLimitBurst 5
unit_has Restart on-failure
unit_has RestartSec 2s
unit_has Environment "OMARCHY_PATH=$compatibility_root"
unit_has Environment QS_DISABLE_FILE_WATCHER=1
unit_has Environment QS_NO_RELOAD_POPUP=1
! unit_has Restart always
! unit_has ExecStart omarchy-launch-shell
! unit_has After graphical-session-pre.target

printf '%s\n' 'service unit semantics passed'
