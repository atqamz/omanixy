#!/usr/bin/env bash
set -euo pipefail

service_file=${1:?generated omarchy-lock-fingerprint PAM service text required}
toplevel_forced_ok=${2:?toplevel evaluation result required}
package_path=${3:?resolved services.fprintd.package store path required}
expected_package_path=${4:?expected TOD-aware fprintd package store path required}
env_value=${5:?resolved fprintd.service FP_TOD_DRIVERS_DIR value required}
expected_env_value=${6:?expected FP_TOD_DRIVERS_DIR value required}
driver_path=${7:?TOD driver package store path required}

test "$toplevel_forced_ok" = true

# services.fprintd.package's own default already resolves to the TOD-aware
# daemon when services.fprintd.tod.enable is set - independent of
# services.fprintd.enable, and therefore already carried by the plain
# registration this capability performs with no widening needed.
test "$package_path" = "$expected_package_path"

# The one environment variable this capability mirrors from upstream's own
# services.fprintd.enable-gated block resolves to the selected driver's
# real path, not a placeholder or an empty value.
test -n "$env_value"
test "$env_value" = "$expected_env_value"
grep -qF "$driver_path" <<<"$env_value"

# The generated PAM service still references the TOD-aware package, not a
# stale plain default.
grep -qF "$package_path/lib/security/pam_fprintd.so" "$service_file"

printf '%s\n' 'security pam fingerprint TOD checks passed'
