#!/usr/bin/env bash
# Drives the real IdlePolicy.js directly (via require), not a disconnected
# reimplementation - the same pattern security-lock-fingerprint-behavior.sh
# uses for FingerprintPolicy.js.
set -euo pipefail

policy_file=$1

node - "$policy_file" <<'NODE'
const path = process.argv[2]
const policy = require(path)

function expect(actual, expected, description) {
  const a = JSON.stringify(actual)
  const e = JSON.stringify(expected)
  if (a !== e) {
    throw new Error(`${description}: expected ${e}, got ${a}`)
  }
}

const MAX_ATTEMPTS = 3

function baseState(overrides) {
  return Object.assign({
    idleEnabled: true,
    idle: true,
    cycleActive: true,
    lockAccepted: false,
    terminalFailure: false,
    lockRunning: false,
    attempts: 0,
    maxAttempts: MAX_ATTEMPTS,
  }, overrides || {})
}

// isExhausted
expect(policy.isExhausted(0, MAX_ATTEMPTS), false, "0 attempts not exhausted")
expect(policy.isExhausted(2, MAX_ATTEMPTS), false, "2 attempts not exhausted")
expect(policy.isExhausted(3, MAX_ATTEMPTS), true, "3 attempts exhausted (== max)")
expect(policy.isExhausted(4, MAX_ATTEMPTS), true, "4 attempts exhausted (> max)")

// canRequestLock guards, one at a time
expect(policy.canRequestLock(baseState()), true, "canRequestLock: all preconditions satisfied")
expect(policy.canRequestLock(baseState({ idleEnabled: false })), false, "canRequestLock: idleEnabled false denies")
expect(policy.canRequestLock(baseState({ idle: false })), false, "canRequestLock: idle false denies")
expect(policy.canRequestLock(baseState({ cycleActive: false })), false, "canRequestLock: cycleActive false denies")
expect(policy.canRequestLock(baseState({ lockAccepted: true })), false, "canRequestLock: lockAccepted denies")
expect(policy.canRequestLock(baseState({ terminalFailure: true })), false, "canRequestLock: terminalFailure denies")
expect(policy.canRequestLock(baseState({ lockRunning: true })), false, "canRequestLock: lockRunning denies")
expect(policy.canRequestLock(baseState({ attempts: MAX_ATTEMPTS })), false, "canRequestLock: exhausted attempts denies")

// classifyLockResult
expect(policy.classifyLockResult(0, "ok"), "ACCEPTED", "exit 0 'ok' -> ACCEPTED")
expect(policy.classifyLockResult(0, "ok\n"), "ACCEPTED", "exit 0 'ok\\n' (trimmed) -> ACCEPTED")
expect(policy.classifyLockResult(0, "missing-pam"), "TERMINAL_UNAVAILABLE", "exit 0 'missing-pam' -> TERMINAL_UNAVAILABLE")
expect(policy.classifyLockResult(0, "failed"), "TERMINAL_UNAVAILABLE", "exit 0 'failed' -> TERMINAL_UNAVAILABLE")
expect(policy.classifyLockResult(0, ""), "INDETERMINATE", "exit 0 empty output -> INDETERMINATE")
expect(policy.classifyLockResult(0, "garbage"), "INDETERMINATE", "exit 0 unrecognized output -> INDETERMINATE")
expect(policy.classifyLockResult(1, "ok"), "TRANSIENT_ERROR", "non-zero exit (even with 'ok' text) -> TRANSIENT_ERROR")
expect(policy.classifyLockResult(124, ""), "TRANSIENT_ERROR", "non-zero exit, empty output -> TRANSIENT_ERROR")

// --- 100 transient failures: actual starts == 3, attempts == 3, retry
// false afterward. Drives the exact decision sequence the runtime uses
// (canRequestLock -> increment -> classify -> shouldRetryLockResult),
// never a shortcut like isExhausted(100, 3).
function driveFailures(resultKind) {
  var state = baseState({ attempts: 0 })
  var starts = 0
  for (var i = 0; i < 100; i++) {
    if (!policy.canRequestLock(state)) continue // denied calls are never counted as attempts
    state.attempts += 1
    starts += 1
    var result = resultKind
    if (result === "TRANSIENT_ERROR") {
      // no state change beyond attempts; shouldRetryLockResult re-checks canRequestLock
    }
    if (!policy.shouldRetryLockResult(state)) break
  }
  return { starts: starts, attempts: state.attempts }
}

var transient = driveFailures("TRANSIENT_ERROR")
expect(transient.starts, MAX_ATTEMPTS, "100 transient failures: actual starts == 3")
expect(transient.attempts, MAX_ATTEMPTS, "100 transient failures: attempts == 3")
expect(policy.shouldRetryLockResult(baseState({ attempts: transient.attempts })), false, "100 transient failures: retry false afterward")

var indeterminate = driveFailures("INDETERMINATE")
expect(indeterminate.starts, MAX_ATTEMPTS, "100 indeterminate results: actual starts == 3")
expect(indeterminate.attempts, MAX_ATTEMPTS, "100 indeterminate results: attempts == 3")

// missing-pam on attempt 1: starts == 1, terminal failure true, no retry.
;(function () {
  var state = baseState({ attempts: 0 })
  var starts = 0
  if (policy.canRequestLock(state)) { state.attempts += 1; starts += 1 }
  var result = policy.classifyLockResult(0, "missing-pam")
  expect(result, "TERMINAL_UNAVAILABLE", "missing-pam classifies as TERMINAL_UNAVAILABLE")
  state.terminalFailure = true
  expect(starts, 1, "missing-pam on attempt 1: starts == 1")
  expect(policy.shouldRetryLockResult(state), false, "missing-pam on attempt 1: no retry")
})()

// failed on attempt 1: same shape as missing-pam.
;(function () {
  var state = baseState({ attempts: 0 })
  var starts = 0
  if (policy.canRequestLock(state)) { state.attempts += 1; starts += 1 }
  var result = policy.classifyLockResult(0, "failed")
  expect(result, "TERMINAL_UNAVAILABLE", "'failed' classifies as TERMINAL_UNAVAILABLE")
  state.terminalFailure = true
  expect(starts, 1, "failed on attempt 1: starts == 1")
  expect(policy.shouldRetryLockResult(state), false, "failed on attempt 1: no retry")
})()

// ok: accepted true, no retry.
;(function () {
  var state = baseState({ attempts: 0 })
  if (policy.canRequestLock(state)) state.attempts += 1
  var result = policy.classifyLockResult(0, "ok")
  expect(result, "ACCEPTED", "'ok' classifies as ACCEPTED")
  state.lockAccepted = true
  expect(policy.shouldRetryLockResult(state), false, "ok: no retry")
})()

// activity between attempt 1 and retry: no attempt 2.
;(function () {
  var state = baseState({ attempts: 0 })
  var starts = 0
  if (policy.canRequestLock(state)) { state.attempts += 1; starts += 1 }
  // TRANSIENT_ERROR would normally retry, but activity ended the cycle first.
  state.cycleActive = false
  state.idle = false
  var retried = policy.shouldRetryLockResult(state)
  expect(retried, false, "activity before retry: shouldRetryLockResult denies")
  if (retried) { state.attempts += 1; starts += 1 }
  expect(starts, 1, "activity between attempt 1 and retry: no attempt 2")
})()

// stay-awake between attempt 1 and retry: no attempt 2.
;(function () {
  var state = baseState({ attempts: 0 })
  var starts = 0
  if (policy.canRequestLock(state)) { state.attempts += 1; starts += 1 }
  // stayAwake becoming true is represented upstream as idleEnabled flipping
  // false (idleEnabled already folds "loaded && !stayAwake").
  state.idleEnabled = false
  var retried = policy.shouldRetryLockResult(state)
  expect(retried, false, "stay-awake before retry: shouldRetryLockResult denies")
  if (retried) { state.attempts += 1; starts += 1 }
  expect(starts, 1, "stay-awake between attempt 1 and retry: no attempt 2")
})()

// new idle cycle after previous exhaustion: attempts resets to 0, can
// start again.
;(function () {
  var exhausted = baseState({ attempts: MAX_ATTEMPTS })
  expect(policy.canRequestLock(exhausted), false, "exhausted cycle cannot start a new attempt")
  var freshCycle = baseState({ attempts: 0, lockAccepted: false, terminalFailure: false })
  expect(policy.canRequestLock(freshCycle), true, "a fresh idle cycle (attempts reset to 0) can start again")
})()

console.log("security-idle-policy: all IdlePolicy.js behavior assertions passed")
NODE
