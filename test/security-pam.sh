#!/usr/bin/env bash
set -euo pipefail

repo=${1:?repository path required}
service_file=${2:?generated pam.d/omarchy-lock-password file required}
disabled_has_password=${3:?disabled-config password-service presence required}
disabled_has_fingerprint=${4:?disabled-config fingerprint-service presence required}
enabled_has_fingerprint=${5:?enabled-config fingerprint-service presence required}
enabled_polkit=${6:?enabled-config polkit-enable value required}
disabled_polkit=${7:?disabled-config polkit-enable value required}

# A. disabled default: the module must create no PAM service at all.
test "$disabled_has_password" = false
test "$disabled_has_fingerprint" = false

# B/D/E/F/G. enabled: exactly the auth-only password service, nothing else.
test "$enabled_has_fingerprint" = false
# I. the module reference is an absolute nix-store path, never a bare
# module name - there is no FHS /lib/security/ on NixOS.
grep -qE '^auth required /nix/store/[^[:space:]]+/lib/security/pam_unix\.so$' "$service_file"
if grep -q 'nullok' "$service_file"; then
  printf '%s\n' 'generated omarchy-lock-password service contains nullok' >&2
  exit 1
fi
if grep -q 'pam_permit\.so' "$service_file"; then
  printf '%s\n' 'generated omarchy-lock-password service contains pam_permit.so' >&2
  exit 1
fi
if grep -q 'pam_fprintd\.so' "$service_file"; then
  printf '%s\n' 'generated omarchy-lock-password service contains pam_fprintd.so' >&2
  exit 1
fi
if grep -qE '^(account|session|password)[[:space:]]' "$service_file"; then
  printf '%s\n' 'generated omarchy-lock-password service contains an unrelated PAM phase' >&2
  exit 1
fi

# L. the generated service is exactly the one auth line - nothing else got
# concatenated in, and nothing was dropped.
non_blank_lines=$(grep -cve '^[[:space:]]*$' "$service_file")
test "$non_blank_lines" = 1

# Enabling the password capability must not enable polkit either.
test "$enabled_polkit" = false
test "$disabled_polkit" = false

# H. no imperative writer of /etc/pam.d anywhere in Omanixy's own code -
# the file must only ever be produced by security.pam.services.*.text.
if rg -n '(sudo|as_root)\s+(tee|cp|install)\s.*pam\.d|pam\.d.*\b(tee|cp|install)\b' \
  "$repo/modules" "$repo/packages" "$repo/scripts"; then
  printf '%s\n' 'imperative /etc/pam.d write found outside security.pam.services' >&2
  exit 1
fi

# J/K. Home Manager owns no PAM declaration and does not import the NixOS
# security module; the NixOS module owns no Home Manager / desktop option.
if rg -n 'modules/nixos|nixosModules' "$repo/modules/home"; then
  printf '%s\n' 'Home Manager module references the NixOS security module' >&2
  exit 1
fi
if rg -n 'home-manager|programs\.omanixy\.(enable|features|shell)|services\.xserver|programs\.hyprland' \
  "$repo/modules/nixos"; then
  printf '%s\n' 'NixOS security module reaches into Home Manager or desktop-session ownership' >&2
  exit 1
fi

printf '%s\n' 'security pam checks passed'
