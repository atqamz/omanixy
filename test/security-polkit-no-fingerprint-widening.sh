#!/usr/bin/env bash
# Cross-layer independence: Layer 5 (polkit) must never regress or widen
# Layer 4 (fingerprint). Mirrors the discipline of
# test/security-pam-fingerprint-widening.sh, but proves the opposite
# direction - that a NEWER layer does not reach back into an OLDER one.
set -euo pipefail

repo=${1:?repository path required}
system_only_fprintd_enable=${2:?}
system_only_polkit1_fprint_auth=${3:?}
combined_fprintd_enable=${4:?}
fingerprint_only_service_file=${5:?fingerprint-only omarchy-lock-fingerprint PAM service file required}
combined_service_file=${6:?fingerprint+polkit-system omarchy-lock-fingerprint PAM service file required}

# Enabling ONLY the polkit system capability (no Layer-4 fingerprint at all)
# must not set services.fprintd.enable, and must not widen the default
# polkit-1 fprintAuth resolution - Omanixy never touches that PAM service's
# fingerprint policy, in either direction.
test "$system_only_fprintd_enable" = false
test "$system_only_polkit1_fprint_auth" = false

# With Layer-4 fingerprint ALSO enabled: services.fprintd.enable remains
# false (still only ever activated by services.dbus.packages/systemd.
# packages/environment.systemPackages registration, per Layer 4's own
# ownership contract - polkit adds nothing here), and the dedicated
# omarchy-lock-fingerprint PAM service is byte-identical whether or not
# the polkit system capability is also enabled - Layer 5 consumes whatever
# polkit-1 policy the host owns, and copies no policy between the two PAM
# services.
test "$combined_fprintd_enable" = false
diff -u "$fingerprint_only_service_file" "$combined_service_file"

# Static evidence that Layer 5 never declares, assigns, or overrides the
# polkit-1 PAM service (bare mentions of "polkit-1" in descriptive prose,
# such as Layer 4's existing fprintAuth-widening-prevention comments, are
# not the invariant here - an actual Nix reference to the service's config
# would be).
if grep -rnE 'security\.pam\.services\."?polkit-1"?' "$repo/modules"; then
  printf '%s\n' 'unexpected security.pam.services.polkit-1 reference in Omanixy NixOS/Home Manager modules' >&2
  exit 1
fi
if grep -rn 'omarchy-hw-laptop-closed' "$repo/modules" "$repo/packages/omanixy-shell/default.nix"; then
  printf '%s\n' 'unexpected laptop-lid helper reference outside the patcher removing it' >&2
  exit 1
fi

printf '%s\n' 'polkit no-fingerprint-widening checks passed'
