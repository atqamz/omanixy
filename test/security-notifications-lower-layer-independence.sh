#!/usr/bin/env bash
set -euo pipefail

all_security_lock_qml=${1:?lock Service.qml (all capabilities on) required}
all_security_fingerprint_js=${2:?FingerprintPolicy.js (all capabilities on) required}
all_security_polkit_qml=${3:?PolkitAgent.qml (all capabilities on) required}
all_security_idle_js=${4:?IdleModel.js (all capabilities on) required}
no_daemon_lock_qml=${5:?lock Service.qml (daemon off, rest on) required}
no_daemon_fingerprint_js=${6:?FingerprintPolicy.js (daemon off, rest on) required}
no_daemon_polkit_qml=${7:?PolkitAgent.qml (daemon off, rest on) required}
no_daemon_idle_js=${8:?IdleModel.js (daemon off, rest on) required}

cmp "$no_daemon_lock_qml" "$all_security_lock_qml"
cmp "$no_daemon_fingerprint_js" "$all_security_fingerprint_js"
cmp "$no_daemon_polkit_qml" "$all_security_polkit_qml"
cmp "$no_daemon_idle_js" "$all_security_idle_js"

printf '%s\n' 'security notifications lower-layer independence checks passed'
