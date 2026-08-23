function isConfigured(pamConfigured, ready) {
  return pamConfigured === true && ready === true
}

function isExhausted(attempts, maxAttempts) {
  return attempts >= maxAttempts
}

function nextReadyAfterProbe(exitCode) {
  // 0/1 are resolved answers, 2 is "cannot determine" - both a negative
  // answer and an indeterminate one fail closed to not-ready, so a stale
  // fingerprintReady = true never survives an indeterminate probe.
  return exitCode === 0
}

function nextReadyAfterCapabilityRevoked() {
  return false
}

function canStartFingerprint(opts) {
  if (!opts.lockRequested || !opts.sessionSecure) return false
  if (!opts.fingerprintConfigured) return false
  if (opts.authenticatingPassword || opts.fingerprintExhausted) return false
  if (opts.fingerprintPamActive || opts.fingerprintAuthenticating) return false
  return true
}

function shouldFinishUnlockOnSuccess(fingerprintConfigured) {
  // A success callback can arrive after capability/readiness was revoked
  // mid-conversation - fingerprintConfigured must be read at callback time,
  // not captured when the conversation started, so this stays fail-closed.
  return fingerprintConfigured === true
}

function shouldRetryAfterFailure(opts) {
  return opts.fingerprintConfigured === true && !opts.authenticatingPassword && !opts.fingerprintExhausted
}

if (typeof module !== "undefined") {
  module.exports = {
    isConfigured,
    isExhausted,
    nextReadyAfterProbe,
    nextReadyAfterCapabilityRevoked,
    canStartFingerprint,
    shouldFinishUnlockOnSuccess,
    shouldRetryAfterFailure,
  }
}
