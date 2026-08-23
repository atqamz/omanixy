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

function_body() {
  sed -n "/function $1(/,/^  }\$/p" "$fingerprint_service_file"
}

fingerprint_policy_file="$(dirname "$fingerprint_service_file")/FingerprintPolicy.js"
policy_function_body() {
  sed -n "/^function $1(/,/^}\$/p" "$fingerprint_policy_file"
}

grep -q 'import "FingerprintPolicy.js" as FingerprintPolicy' "$fingerprint_service_file"
grep -q 'readonly property int fingerprintMaxAttempts: 5' "$fingerprint_service_file"
grep -q 'readonly property bool fingerprintExhausted: FingerprintPolicy.isExhausted(fingerprintAttempts, fingerprintMaxAttempts)' "$fingerprint_service_file"
policy_function_body isExhausted | grep -q 'attempts >= maxAttempts'
function_body startFingerprint | grep -q 'fingerprintAttempts += 1'
grep -q 'repeat: false' "$fingerprint_service_file"

begin_lock_body=$(function_body beginLock)
printf '%s\n' "$begin_lock_body" | grep -q 'resetAuthenticationState()'
printf '%s\n' "$begin_lock_body" | grep -q 'fingerprintAttempts = 0'
printf '%s\n' "$begin_lock_body" | grep -q 'fingerprintReady = false'
printf '%s\n' "$begin_lock_body" | grep -q 'queueSessionLock()'
printf '%s\n' "$begin_lock_body" | grep -qF 'Qt.callLater(function() {'
printf '%s\n' "$begin_lock_body" | grep -q 'root.refreshFingerprintStatus()'

fingerprint_ready_reset_line=$(printf '%s\n' "$begin_lock_body" | grep -n 'fingerprintReady = false' | head -1 | cut -d: -f1)
call_later_line=$(printf '%s\n' "$begin_lock_body" | grep -n 'Qt.callLater(function() {' | head -1 | cut -d: -f1)
if ((fingerprint_ready_reset_line >= call_later_line)); then
  printf '%s\n' 'beginLock must invalidate fingerprintReady synchronously, before the deferred refresh - not after' >&2
  exit 1
fi

if grep -q 'fprintd-list' "$fingerprint_service_file"; then
  printf '%s\n' 'fingerprint-enabled Service.qml still shells out to fprintd-list directly' >&2
  exit 1
fi
if grep -Fq 'bash", "-c"' "$fingerprint_service_file"; then
  printf '%s\n' 'fingerprint-enabled Service.qml still contains a bash -c shape' >&2
  exit 1
fi
grep -Fq 'command: ["omarchy-lock-fingerprint-ready"]' "$fingerprint_service_file"

grep -q 'root.fingerprintReady = FingerprintPolicy.nextReadyAfterProbe(exitCode)' "$fingerprint_service_file"
policy_function_body nextReadyAfterProbe | grep -q 'return exitCode === 0'

capability_revoked_body=$(sed -n '/onFingerprintPamConfiguredChanged/,/^  }$/p' "$fingerprint_service_file")
printf '%s\n' "$capability_revoked_body" | grep -q 'fingerprintReady = FingerprintPolicy.nextReadyAfterCapabilityRevoked()'
printf '%s\n' "$capability_revoked_body" | grep -q 'fingerprintRetryTimer.stop()'
printf '%s\n' "$capability_revoked_body" | grep -q 'fingerprintPam.abort()'
if printf '%s\n' "$capability_revoked_body" | grep -q 'finishUnlock\|lockRequested ='; then
  printf '%s\n' 'onFingerprintPamConfiguredChanged touches unlock/lock state' >&2
  exit 1
fi
policy_function_body nextReadyAfterCapabilityRevoked | grep -q 'return false'

handle_finished_body=$(function_body handleFingerprintFinished)
test "$(printf '%s\n' "$handle_finished_body" | grep -c 'finishUnlock()')" = 1
printf '%s\n' "$handle_finished_body" | grep -A5 -F 'if (result === PamResult.Success) {' | grep -q 'finishUnlock()'

printf '%s\n' "$handle_finished_body" | grep -q 'if (FingerprintPolicy.shouldFinishUnlockOnSuccess(fingerprintConfigured)) finishUnlock()'
policy_function_body shouldFinishUnlockOnSuccess | grep -q 'fingerprintConfigured === true'

printf '%s\n' "$handle_finished_body" | grep -q 'FingerprintPolicy.shouldRetryAfterFailure('
printf '%s\n' "$handle_finished_body" | grep -q 'fingerprintExhausted: fingerprintExhausted'
policy_function_body shouldRetryAfterFailure | grep -q '!opts.fingerprintExhausted'

if printf '%s\n' "$handle_finished_body" | grep -q 'failedAttempts'; then
  printf '%s\n' 'handleFingerprintFinished touches password failedAttempts' >&2
  exit 1
fi
fingerprint_error_body=$(sed -n '/id: fingerprintPam/,/^  }$/p' "$fingerprint_service_file")
if printf '%s\n' "$fingerprint_error_body" | grep -q 'failedAttempts\|passwordPam'; then
  printf '%s\n' 'fingerprintPam touches password state' >&2
  exit 1
fi
printf '%s\n' "$fingerprint_error_body" | grep -q 'FingerprintPolicy.shouldRetryAfterFailure('
printf '%s\n' "$fingerprint_error_body" | grep -q 'fingerprintExhausted: root.fingerprintExhausted'

password_failure_body=$(function_body handlePasswordFailure)
if printf '%s\n' "$password_failure_body" | grep -qE 'fingerprintAttempts *='; then
  printf '%s\n' 'handlePasswordFailure touches the fingerprint attempt budget' >&2
  exit 1
fi
printf '%s\n' "$password_failure_body" | grep -q 'startFingerprint()'

start_fingerprint_body=$(function_body startFingerprint)
printf '%s\n' "$start_fingerprint_body" | grep -q 'if (!FingerprintPolicy.canStartFingerprint({'
printf '%s\n' "$start_fingerprint_body" | grep -q 'authenticatingPassword: authenticatingPassword,'
printf '%s\n' "$start_fingerprint_body" | grep -q 'fingerprintExhausted: fingerprintExhausted,'
policy_function_body canStartFingerprint | grep -q 'if (opts.authenticatingPassword || opts.fingerprintExhausted) return false'

submit_password_body=$(function_body submitPassword)
printf '%s\n' "$submit_password_body" | grep -q 'fingerprintRetryTimer.stop()'
printf '%s\n' "$submit_password_body" | grep -q 'fingerprintPam.abort()'

if grep -q 'fingerprint PAM stays armed for the whole lock' "$fingerprint_service_file"; then
  printf '%s\n' 'stale fingerprint blank-timer comment survived in the fingerprint-enabled build' >&2
  exit 1
fi

for field in fingerprintEnabled fingerprintReady fingerprintAuthenticating fingerprintAttempts fingerprintAttemptsRemaining fingerprintExhausted; do
  grep -q "$field:" "$fingerprint_service_file"
done

test "$(grep -c 'PamContext {' "$fingerprint_service_file")" = 2
grep -q 'omarchy-lock-password' "$fingerprint_service_file"
grep -q 'omarchy-lock-fingerprint' "$fingerprint_service_file"

test "$(grep -c 'PamContext {' "$disabled_service_file")" = 1
if grep -q 'fingerprintMaxAttempts' "$disabled_service_file"; then
  printf '%s\n' 'fingerprint-disabled Service.qml unexpectedly contains fingerprint budget state' >&2
  exit 1
fi

test "$standalone_fingerprint_lock_disabled_ok" = false
test "$standalone_fingerprint_lock_enabled_ok" = false
test "$integrated_off_off_ok" = false
test "$integrated_on_off_ok" = false
test "$integrated_off_on_ok" = false
test "$integrated_on_on_ok" = true
test "$integrated_on_on_hm_disabled_ok" = true

printf '%s\n' 'security lock fingerprint checks passed'
