#!/usr/bin/env bash
set -euo pipefail

lock_closure_paths=${1:?fingerprint-disabled lock closure store paths required}
lock_fingerprint_closure_paths=${2:?fingerprint-enabled lock closure store paths required}
declared_runtime_inputs=${3:?fingerprint-disabled declared runtime inputs json required}
fingerprint_declared_runtime_inputs=${4:?fingerprint-enabled declared runtime inputs json required}
lock_compat_bin=${5:?fingerprint-disabled compatibility bin required}
lock_fingerprint_compat_bin=${6:?fingerprint-enabled compatibility bin required}
expected_fingerprint_package=${7:?expected selected fingerprint package store path required}

# Declared-input-level proof: turning on the fingerprint capability widens
# packages/omanixy-shell/default.nix's own runtimeInputs list by exactly the
# selected fingerprintPackage - for an integrated Home Manager
# configuration this is osConfig.services.fprintd.package, never an
# independently-chosen pkgs.fprintd - the one narrow, documented exception
# to selectedCapabilities otherwise deriving purely from `features`. Not a
# general capability - a single named exception. An exact set difference
# (not a substring match against the raw diff) is required, since a
# substring match would pass just as happily if the selected package was
# one of several unrelated widenings.
removed=$(jq -n --slurpfile a "$declared_runtime_inputs" --slurpfile b "$fingerprint_declared_runtime_inputs" '$a[0] - $b[0]')
added=$(jq -n --slurpfile a "$declared_runtime_inputs" --slurpfile b "$fingerprint_declared_runtime_inputs" '$b[0] - $a[0]')

if [[ "$removed" != "[]" ]]; then
  printf 'fingerprint removed declaredRuntimeInputs entries instead of only adding:\n%s\n' "$removed" >&2
  exit 1
fi

added_count=$(jq 'length' <<<"$added")
if [[ "$added_count" != 1 ]]; then
  printf 'expected fingerprint to add exactly one declaredRuntimeInputs entry, added %s:\n%s\n' "$added_count" "$added" >&2
  exit 1
fi

# Not just a basename/prefix match: the one added entry must be the exact
# selected fingerprint package store path this fixture was built with, so a
# regression that widened by some other fprintd-named derivation (or a
# same-named but differently-built one) fails this proof.
added_path=$(jq -r '.[0]' <<<"$added")
if [[ "$added_path" != "$expected_fingerprint_package" ]]; then
  printf 'the one added declaredRuntimeInputs entry does not match the selected fingerprint package:\n  added:    %s\n  expected: %s\n' "$added_path" "$expected_fingerprint_package" >&2
  exit 1
fi

# Closure-level proof, mirrored from security-lock-closure.sh: fprintd is
# absent from the fingerprint-disabled closure and present in the
# fingerprint-enabled one - the widening happens exactly when
# fingerprintEnabled flips, and only then.
if grep -Ei 'fprintd' "$lock_closure_paths"; then
  printf '%s\n' 'fprintd reachable from the fingerprint-disabled lock closure' >&2
  exit 1
fi
if ! grep -Ei 'fprintd' "$lock_fingerprint_closure_paths"; then
  printf '%s\n' 'fprintd not reachable from the fingerprint-enabled lock closure' >&2
  exit 1
fi

# The readiness adapter is packaged and reachable only in the
# fingerprint-enabled compat bin.
test -L "$lock_fingerprint_compat_bin/bin/omarchy-lock-fingerprint-ready"
test ! -e "$lock_compat_bin/bin/omarchy-lock-fingerprint-ready"

# Enabling fingerprint adds exactly one binary beyond the lock-only set.
diff -u \
  <(find "$lock_compat_bin/bin" -mindepth 1 -maxdepth 1 -printf '%f\n' | sort) \
  <(find "$lock_fingerprint_compat_bin/bin" -mindepth 1 -maxdepth 1 -printf '%f\n' | sort | grep -Fxv omarchy-lock-fingerprint-ready)

printf '%s\n' 'security lock fingerprint closure invariants passed'
