#!/usr/bin/env bash
set -euo pipefail

owned_service_file=${1:?plain-enabled generated pam.d/omarchy-lock-password file required}
owned_enable=${2:?plain-enabled resolved enable value required}
owned_toplevel_forced=${3:?plain-enabled config.system.build.toplevel eval result required}
adversarial_toplevel_forced=${4:?composition-adversarial config.system.build.toplevel eval result required}
enable_conflict_service_file=${5:?enable-conflict generated pam.d/omarchy-lock-password file required}
enable_conflict_enable=${6:?enable-conflict resolved enable value required}
enable_conflict_toplevel_forced=${7:?enable-conflict config.system.build.toplevel eval result required}
strong_conflict_service_file=${8:?strong-conflict generated pam.d/omarchy-lock-password file required}
strong_conflict_toplevel_forced=${9:?strong-conflict config.system.build.toplevel eval result required}

# F. Capability truth: whenever the Omanixy option is enabled in a config
# with no ownership conflict, the resolved service is actually enabled with
# the exact expected text, and forcing config.system.build.toplevel (the
# only attribute that runs NixOS assertion checking) does not misfire.
test "$owned_enable" = true
test "$owned_toplevel_forced" = true

# C, re-checked through the assertion path: an ordinary normal-priority
# competing `text` definition must not trip the capability-truth assertion
# either - the composition test already proves the file is byte-identical.
test "$adversarial_toplevel_forced" = true

# D. An ordinary normal-priority competing `enable = false` must not
# suppress the service: Omanixy still owns the enabled state, and the
# generated file is byte-identical to the plain enabled build.
test "$enable_conflict_enable" = true
test "$enable_conflict_toplevel_forced" = true
if ! diff -u "$owned_service_file" "$enable_conflict_service_file"; then
  printf '%s\n' 'a normal-priority enable = false altered the generated omarchy-lock-password PAM service' >&2
  exit 1
fi
non_blank_lines=$(grep -cve '^[[:space:]]*$' "$enable_conflict_service_file")
test "$non_blank_lines" = 1

# E. A strong, equal-priority conflict on `text` (another lib.mkForce) must
# fail closed rather than silently compose. nixpkgs' `lines` type merges
# same-priority definitions by concatenation instead of raising a conflict
# on its own - the second check below proves that danger is real - so the
# Omanixy module's own assertion is what must fail config.system.build.
# toplevel's evaluation here.
test "$strong_conflict_toplevel_forced" = false
if ! grep -q 'pam_permit\.so' "$strong_conflict_service_file"; then
  printf '%s\n' 'expected the strong-conflict fixture to prove a silent lines-merge; found none' >&2
  exit 1
fi

printf '%s\n' 'security pam capability checks passed'
