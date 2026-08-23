function isExhausted(attempts, maxAttempts) {
  return Number(attempts) >= Number(maxAttempts)
}

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

function classifyLockResult(exitCode, output) {
  if (exitCode !== 0) return "TRANSIENT_ERROR"

  var trimmed = String(output === undefined || output === null ? "" : output).trim()
  if (trimmed === "ok") return "ACCEPTED"
  if (trimmed === "missing-pam") return "TERMINAL_UNAVAILABLE"
  if (trimmed === "failed") return "TERMINAL_UNAVAILABLE"
  return "INDETERMINATE"
}

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
