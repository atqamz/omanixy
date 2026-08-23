#!/usr/bin/env bash
set -euo pipefail

repo=${1:?repository path required}
system_only_fprintd_enable=${2:?}
system_only_polkit1_fprint_auth=${3:?}
combined_fprintd_enable=${4:?}
fingerprint_only_service_file=${5:?fingerprint-only omarchy-lock-fingerprint PAM service file required}
combined_service_file=${6:?fingerprint+polkit-system omarchy-lock-fingerprint PAM service file required}

test "$system_only_fprintd_enable" = false
test "$system_only_polkit1_fprint_auth" = false

test "$combined_fprintd_enable" = false
diff -u "$fingerprint_only_service_file" "$combined_service_file"

if grep -rnE 'security\.pam\.services\."?polkit-1"?' "$repo/modules"; then
  printf '%s\n' 'unexpected security.pam.services.polkit-1 reference in Omanixy NixOS/Home Manager modules' >&2
  exit 1
fi
if grep -rn 'omarchy-hw-laptop-closed' "$repo/modules" "$repo/packages/omanixy-shell/default.nix"; then
  printf '%s\n' 'unexpected laptop-lid helper reference outside the patcher removing it' >&2
  exit 1
fi

printf '%s\n' 'polkit no-fingerprint-widening checks passed'
