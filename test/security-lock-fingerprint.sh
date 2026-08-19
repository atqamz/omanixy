#!/usr/bin/env bash
set -euo pipefail

fingerprint_service_file=${1:?fingerprint-enabled patched Service.qml required}
disabled_service_file=${2:?fingerprint-disabled patched Service.qml required}
standalone_fingerprint_lock_disabled_ok=${3:?standalone lock-disabled/fingerprint-enabled evaluation result required}
standalone_fingerprint_lock_enabled_ok=${4:?standalone lock-enabled/fingerprint-enabled evaluation result required}
integrated_off_off_ok=${5:?integrated pam-password-off/pam-fingerprint-off evaluation result required}
integrated_on_off_ok=${6:?integrated pam-password-on/pam-fingerprint-off evaluation result required}
integrated_off_on_ok=${7:?integrated pam-password-off/pam-fingerprint-on evaluation result required}
integrated_on_on_ok=${8:?integrated pam-password-on/pam-fingerprint-on evaluation result required}
integrated_on_on_hm_disabled_ok=${9:?integrated both-on/hm-fingerprint-disabled evaluation result required}

# Every function this script inspects closes at the same 2-space indent it
# opens at (all are direct properties of the root Item), so a range up to
# the first "^  }$" after the function's `function name(` line extracts
# exactly that function's body and nothing past it.
function_body() {
  sed -n "/function $1(/,/^  }\$/p" "$fingerprint_service_file"
}

# Bounded state machine: a finite per-lock-acquisition budget, a
# non-repeating retry timer, and a budget reset tied only to beginLock -
# never to a screen change, DPMS event, or password failure.
grep -q 'readonly property int fingerprintMaxAttempts: 5' "$fingerprint_service_file"
grep -q 'readonly property bool fingerprintExhausted: fingerprintAttempts >= fingerprintMaxAttempts' "$fingerprint_service_file"
function_body beginLock | grep -q 'fingerprintAttempts = 0'
function_body startFingerprint | grep -q 'fingerprintAttempts += 1'
grep -q 'repeat: false' "$fingerprint_service_file"

# The upstream fingerprintCheckProc's bash -c/fprintd-list/grep probe must
# never be reintroduced; the audited, argument-free readiness adapter
# replaces it, invoked as direct argv.
if grep -q 'fprintd-list' "$fingerprint_service_file"; then
  printf '%s\n' 'fingerprint-enabled Service.qml still shells out to fprintd-list directly' >&2
  exit 1
fi
if grep -Fq 'bash", "-c"' "$fingerprint_service_file"; then
  printf '%s\n' 'fingerprint-enabled Service.qml still contains a bash -c shape' >&2
  exit 1
fi
grep -Fq 'command: ["omarchy-lock-fingerprint-ready"]' "$fingerprint_service_file"

# Fingerprint failure/exhaustion/error must never call finishUnlock(): the
# only call in handleFingerprintFinished is the line right after the
# PamResult.Success check, and there is exactly one call in the function.
handle_finished_body=$(function_body handleFingerprintFinished)
test "$(printf '%s\n' "$handle_finished_body" | grep -c 'finishUnlock()')" = 1
printf '%s\n' "$handle_finished_body" | grep -A1 -F 'if (result === PamResult.Success) {' | grep -q 'finishUnlock()'

# The retry timer's own interval is not what bounds it - the retry restart on
# both a failed attempt and a PAM error must be guarded by fingerprintExhausted,
# which is what actually stops the finite-attempt budget from becoming an
# unbounded retry loop.
printf '%s\n' "$handle_finished_body" | grep -q '!fingerprintExhausted'

# Fingerprint failure/exhaustion/error must never touch password state:
# neither handleFingerprintFinished nor the fingerprintPam onError handler
# may reference failedAttempts or passwordPam.
if printf '%s\n' "$handle_finished_body" | grep -q 'failedAttempts'; then
  printf '%s\n' 'handleFingerprintFinished touches password failedAttempts' >&2
  exit 1
fi
fingerprint_error_body=$(sed -n '/id: fingerprintPam/,/^  }$/p' "$fingerprint_service_file")
if printf '%s\n' "$fingerprint_error_body" | grep -q 'failedAttempts\|passwordPam'; then
  printf '%s\n' 'fingerprintPam touches password state' >&2
  exit 1
fi
printf '%s\n' "$fingerprint_error_body" | grep -q '!root.fingerprintExhausted'

# handlePasswordFailure must never refill the fingerprint budget - it may
# only resume scheduling via startFingerprint(), which applies its own
# exhaustion/in-flight guards.
password_failure_body=$(function_body handlePasswordFailure)
if printf '%s\n' "$password_failure_body" | grep -qE 'fingerprintAttempts *='; then
  printf '%s\n' 'handlePasswordFailure touches the fingerprint attempt budget' >&2
  exit 1
fi
printf '%s\n' "$password_failure_body" | grep -q 'startFingerprint()'

# startFingerprint itself must refuse once exhausted or while a password
# check is in flight, before ever starting a new PAM conversation.
start_fingerprint_body=$(function_body startFingerprint)
printf '%s\n' "$start_fingerprint_body" | grep -q 'if (authenticatingPassword || fingerprintExhausted) return'

# Password submission stops fingerprint scheduling and aborts any in-flight
# conversation before starting its own PAM conversation.
submit_password_body=$(function_body submitPassword)
printf '%s\n' "$submit_password_body" | grep -q 'fingerprintRetryTimer.stop()'
printf '%s\n' "$submit_password_body" | grep -q 'fingerprintPam.abort()'

# idleBlankTimer stays authenticatingPassword-only; the stale fingerprint
# comment from the pinned upstream source must not survive.
if grep -q 'fingerprint PAM stays armed for the whole lock' "$fingerprint_service_file"; then
  printf '%s\n' 'stale fingerprint blank-timer comment survived in the fingerprint-enabled build' >&2
  exit 1
fi

# status() carries the required fields, and never anything more revealing
# than a bounded attempt counter/booleans - no biometric or PAM content.
for field in fingerprintEnabled fingerprintReady fingerprintAuthenticating fingerprintAttempts fingerprintAttemptsRemaining fingerprintExhausted; do
  grep -q "$field:" "$fingerprint_service_file"
done

# Exactly two PamContexts (password + fingerprint) when fingerprint is on.
test "$(grep -c 'PamContext {' "$fingerprint_service_file")" = 2
grep -q 'omarchy-lock-password' "$fingerprint_service_file"
grep -q 'omarchy-lock-fingerprint' "$fingerprint_service_file"

# The fingerprint-disabled build (security-lock.sh's own fixture) is
# untouched by any of this - re-asserted here as a cross-check that the two
# patch-lock-service modes are genuinely independent, not just individually
# self-consistent.
test "$(grep -c 'PamContext {' "$disabled_service_file")" = 1
if grep -q 'fingerprintMaxAttempts' "$disabled_service_file"; then
  printf '%s\n' 'fingerprint-disabled Service.qml unexpectedly contains fingerprint budget state' >&2
  exit 1
fi

# Fingerprint HM assertion matrix (7 scenarios; A/B are standalone, C-G are
# the integrated NixOS + Home Manager crossing of the paired pam.password/
# pam.fingerprint options and the Home Manager option itself).
test "$standalone_fingerprint_lock_disabled_ok" = false  # A
test "$standalone_fingerprint_lock_enabled_ok" = false   # B
test "$integrated_off_off_ok" = false                    # C
test "$integrated_on_off_ok" = false                     # D
test "$integrated_off_on_ok" = false                     # E
test "$integrated_on_on_ok" = true                        # F
test "$integrated_on_on_hm_disabled_ok" = true            # G

printf '%s\n' 'security lock fingerprint checks passed'
