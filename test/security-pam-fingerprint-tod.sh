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

test "$package_path" = "$expected_package_path"

test -n "$env_value"
test "$env_value" = "$expected_env_value"
grep -qF "$driver_path" <<<"$env_value"

grep -qF "$package_path/lib/security/pam_fprintd.so" "$service_file"

printf '%s\n' 'security pam fingerprint TOD checks passed'
