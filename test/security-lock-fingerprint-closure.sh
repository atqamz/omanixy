#!/usr/bin/env bash
set -euo pipefail

lock_closure_paths=${1:?fingerprint-disabled lock closure store paths required}
lock_fingerprint_closure_paths=${2:?fingerprint-enabled lock closure store paths required}
declared_runtime_inputs=${3:?fingerprint-disabled declared runtime inputs json required}
fingerprint_declared_runtime_inputs=${4:?fingerprint-enabled declared runtime inputs json required}
lock_compat_bin=${5:?fingerprint-disabled compatibility bin required}
lock_fingerprint_compat_bin=${6:?fingerprint-enabled compatibility bin required}

# Declared-input-level proof: turning on the fingerprint capability widens
# packages/omanixy-shell/default.nix's own runtimeInputs list by exactly
# pkgs.fprintd, the one narrow, documented exception to selectedCapabilities
# otherwise deriving purely from `features`. Not a general capability - a
# single named exception.
new_declared=$(diff <(jq -S . "$declared_runtime_inputs") <(jq -S . "$fingerprint_declared_runtime_inputs") || true)
if [[ -z "$new_declared" ]]; then
  printf '%s\n' 'expected fingerprint to widen declaredRuntimeInputs; found no difference' >&2
  exit 1
fi
if ! grep -q 'fprintd' <<<"$new_declared"; then
  printf 'declaredRuntimeInputs widened by something other than fprintd:\n%s\n' "$new_declared" >&2
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
