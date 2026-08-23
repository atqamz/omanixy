#!/usr/bin/env bash
set -euo pipefail

repo=${1:?repository path required}
service_file=${2:?generated pam.d/omarchy-lock-fingerprint file required}
enabled_has_password=${3:?enabled-config password-service presence required}
enabled_polkit=${4:?enabled-config polkit-enable value required}

# The disabled-default and "enabling one service does not create the other"
# directions are already covered by test/security-pam.sh's own
# disabledHasFingerprintService/enabledHasFingerprintService checks against
# the password fixtures; this file covers the mirror image plus the
# fingerprint-specific line shape.
test "$enabled_has_password" = false
test "$enabled_polkit" = false

# The module reference is an absolute nix-store path, sourced from the
# resolved services.fprintd.package - never a bare module name.
grep -qE '^auth required /nix/store/[^[:space:]]+/lib/security/pam_fprintd\.so$' "$service_file"
if grep -q 'nullok' "$service_file"; then
  printf '%s\n' 'generated omarchy-lock-fingerprint service contains nullok' >&2
  exit 1
fi
if grep -q 'pam_permit\.so' "$service_file"; then
  printf '%s\n' 'generated omarchy-lock-fingerprint service contains pam_permit.so' >&2
  exit 1
fi
if grep -q 'pam_unix\.so' "$service_file"; then
  printf '%s\n' 'generated omarchy-lock-fingerprint service contains pam_unix.so' >&2
  exit 1
fi
if grep -qE '^(account|session|password)[[:space:]]' "$service_file"; then
  printf '%s\n' 'generated omarchy-lock-fingerprint service contains an unrelated PAM phase' >&2
  exit 1
fi

non_blank_lines=$(grep -cve '^[[:space:]]*$' "$service_file")
test "$non_blank_lines" = 1

if ! bash "$repo/test/lib/no-imperative-pam-write.sh" \
  "$repo/modules" "$repo/packages" "$repo/scripts"; then
  printf '%s\n' 'imperative /etc/pam.d write found outside security.pam.services' >&2
  exit 1
fi

printf '%s\n' 'security pam fingerprint checks passed'
