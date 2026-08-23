#!/usr/bin/env bash
set -euo pipefail

lock_only_service_qml=${1:?lock-only shell/plugins/lock/Service.qml required}
lock_idle_service_qml=${2:?lock+idle shell/plugins/lock/Service.qml required}

cmp "$lock_only_service_qml" "$lock_idle_service_qml"

printf '%s\n' 'security idle no-DPMS-widening checks passed'
