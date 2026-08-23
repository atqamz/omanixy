#!/usr/bin/env bash
set -euo pipefail

service_file=${1:?generated omarchy-lock-fingerprint PAM service text required}
toplevel_forced_ok=${2:?toplevel evaluation result required}
dbus_registered=${3:?services.dbus.packages membership result required}
systemd_registered=${4:?systemd.packages membership result required}
environment_registered=${5:?environment.systemPackages membership result required}
declared_runtime_inputs=${6:?custom-package declaredRuntimeInputs json required}
custom_package_path=${7:?custom fprintd package store path required}
default_package_path=${8:?default pkgs.fprintd store path required}

test "$toplevel_forced_ok" = true
test "$dbus_registered" = true
test "$systemd_registered" = true
test "$environment_registered" = true

if [[ "$custom_package_path" == "$default_package_path" ]]; then
  printf '%s\n' 'custom fprintd package fixture did not actually change store path' >&2
  exit 1
fi

grep -qF "$custom_package_path/lib/security/pam_fprintd.so" "$service_file"
if grep -qF "$default_package_path/lib/security/pam_fprintd.so" "$service_file"; then
  printf '%s\n' 'omarchy-lock-fingerprint PAM service references the default fprintd package alongside the custom one' >&2
  exit 1
fi

if ! jq -e --arg p "$custom_package_path" 'any(.[]; startswith($p))' "$declared_runtime_inputs" >/dev/null; then
  printf '%s\n' 'declaredRuntimeInputs does not contain the custom fprintd package' >&2
  exit 1
fi
if jq -e --arg p "$default_package_path" 'any(.[]; startswith($p))' "$declared_runtime_inputs" >/dev/null; then
  printf '%s\n' 'declaredRuntimeInputs contains the default fprintd package alongside the custom one' >&2
  exit 1
fi

printf '%s\n' 'security pam fingerprint custom package checks passed'
