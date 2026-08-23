function isConfigured(pamConfigured, ready) {
  return pamConfigured === true && ready === true
}

function isExhausted(attempts, maxAttempts) {
  return attempts >= maxAttempts
}

function nextReadyAfterProbe(exitCode) {
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
