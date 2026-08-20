function isExhausted(attempts, maxAttempts) {
  return Number(attempts) >= Number(maxAttempts)
}

// state: { idleEnabled, idle, cycleActive, lockAccepted, terminalFailure,
//          lockRunning, attempts, maxAttempts }
//
// idleEnabled already folds "stay-awake state loaded" and "stayAwake ==
// false" into one derived flag (see Service.qml), so this policy does not
// need to re-derive either from raw state.
function canRequestLock(state) {
  if (!state.idleEnabled) return false
  if (!state.idle) return false
  if (!state.cycleActive) return false
  if (state.lockAccepted) return false
  if (state.terminalFailure) return false
  if (state.lockRunning) return false
  if (isExhausted(state.attempts, state.maxAttempts)) return false
  return true
}

// Layer-3's native lock IPC ("omanixy-shell lock lock") returns exactly
// "ok" | "missing-pam" | "failed" on stdout with exit code 0; any other
// exit code is an IPC-level failure (the shell not running/responding, or
// the wrapper's own bounded timeout), and any exit-0 output outside that
// three-way contract is unrecognized rather than a text-parsed shape.
function classifyLockResult(exitCode, output) {
  if (exitCode !== 0) return "TRANSIENT_ERROR"

  var trimmed = String(output === undefined || output === null ? "" : output).trim()
  if (trimmed === "ok") return "ACCEPTED"
  if (trimmed === "missing-pam") return "TERMINAL_UNAVAILABLE"
  if (trimmed === "failed") return "TERMINAL_UNAVAILABLE"
  return "INDETERMINATE"
}

// Only TRANSIENT_ERROR/INDETERMINATE results are ever meaningful to ask
// this about - callers must not invoke it after an ACCEPTED or
// TERMINAL_UNAVAILABLE classification, both of which end the idle cycle's
// lock attempts outright. The retry preconditions are otherwise identical
// to the initial-request preconditions: the same idle/enabled/cycle/budget
// state must still hold at retry time as at request time.
function shouldRetryLockResult(state) {
  return canRequestLock(state)
}

if (typeof module !== "undefined") {
  module.exports = {
    isExhausted: isExhausted,
    canRequestLock: canRequestLock,
    classifyLockResult: classifyLockResult,
    shouldRetryLockResult: shouldRetryLockResult
  }
}
