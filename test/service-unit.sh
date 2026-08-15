#!/usr/bin/env bash
set -euo pipefail

unit=${1:?rendered service unit required}
runtime=${2:?runtime package path required}
omarchy_source=${3:?Omarchy source path required}
compatibility_root=${4:?compatibility root path required}

grep -Fqx "ExecStart=$runtime/bin/omanixy-shell-runtime" "$unit"
grep -Fqx 'PartOf=graphical-session.target' "$unit"
grep -Fqx 'After=graphical-session.target' "$unit"
grep -Fqx 'WantedBy=graphical-session.target' "$unit"
grep -Fqx 'StartLimitIntervalSec=60s' "$unit"
grep -Fqx 'StartLimitBurst=5' "$unit"
grep -Fqx 'Restart=on-failure' "$unit"
grep -Fqx 'RestartSec=2s' "$unit"
grep -Fqx "Environment=OMARCHY_PATH=$compatibility_root" "$unit"
grep -Fqx 'Environment=QS_DISABLE_FILE_WATCHER=1' "$unit"
grep -Fqx 'Environment=QS_NO_RELOAD_POPUP=1' "$unit"
! grep -Fq 'Restart=always' "$unit"
! grep -Fq 'omarchy-launch-shell' "$unit"
! grep -Fq 'After=graphical-session-pre.target' "$unit"

printf '%s\n' 'service unit semantics passed'
