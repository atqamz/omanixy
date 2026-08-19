#!/usr/bin/env bash
set -euo pipefail

policy_file=${1:?FingerprintPolicy.js path required}

# This drives the real FingerprintPolicy.js exports directly (via require),
# not a disconnected reimplementation of its rules - a change to the real
# state machine that breaks one of these sequences fails this test, not a
# copy of it.
node - "$policy_file" <<'NODE'
const policy = require(process.argv[2]);

function expect(actual, expected, description) {
  if (actual !== expected) {
    throw new Error(`${description}: expected ${expected}, got ${actual}`);
  }
}

// isConfigured: capability AND readiness, both required.
expect(policy.isConfigured(true, true), true, "isConfigured(pam, ready) both true");
expect(policy.isConfigured(true, false), false, "isConfigured pam-only");
expect(policy.isConfigured(false, true), false, "isConfigured ready-only");
expect(policy.isConfigured(false, false), false, "isConfigured neither");

// isExhausted: strictly a >= comparison, not >.
expect(policy.isExhausted(0, 5), false, "isExhausted below budget");
expect(policy.isExhausted(4, 5), false, "isExhausted one below budget");
expect(policy.isExhausted(5, 5), true, "isExhausted at budget");
expect(policy.isExhausted(6, 5), true, "isExhausted past budget");

// nextReadyAfterProbe: only exit code 0 is a positive answer - both a
// negative (1) and an indeterminate (2, or any other leaked code) answer
// fail closed to not-ready.
expect(policy.nextReadyAfterProbe(0), true, "nextReadyAfterProbe(0)");
expect(policy.nextReadyAfterProbe(1), false, "nextReadyAfterProbe(1)");
expect(policy.nextReadyAfterProbe(2), false, "nextReadyAfterProbe(2)");
expect(policy.nextReadyAfterProbe(137), false, "nextReadyAfterProbe(leaked signal code)");

// nextReadyAfterCapabilityRevoked: unconditionally false, no arguments
// can make it otherwise.
expect(policy.nextReadyAfterCapabilityRevoked(), false, "nextReadyAfterCapabilityRevoked");

// canStartFingerprint: a fully permissive baseline, then one flipped guard
// at a time - every single guard must independently veto a start.
const permissive = {
  lockRequested: true,
  sessionSecure: true,
  fingerprintConfigured: true,
  authenticatingPassword: false,
  fingerprintExhausted: false,
  fingerprintPamActive: false,
  fingerprintAuthenticating: false,
};
expect(policy.canStartFingerprint(permissive), true, "canStartFingerprint fully permissive baseline");
for (const [flip, value] of [
  ["lockRequested", false],
  ["sessionSecure", false],
  ["fingerprintConfigured", false],
  ["authenticatingPassword", true],
  ["fingerprintExhausted", true],
  ["fingerprintPamActive", true],
  ["fingerprintAuthenticating", true],
]) {
  const opts = { ...permissive, [flip]: value };
  expect(policy.canStartFingerprint(opts), false, `canStartFingerprint vetoed by ${flip}=${value}`);
}

// shouldFinishUnlockOnSuccess: strict === true, not merely truthy - a
// stale non-boolean capability snapshot must not accidentally unlock.
expect(policy.shouldFinishUnlockOnSuccess(true), true, "shouldFinishUnlockOnSuccess configured");
expect(policy.shouldFinishUnlockOnSuccess(false), false, "shouldFinishUnlockOnSuccess not configured");
expect(policy.shouldFinishUnlockOnSuccess(undefined), false, "shouldFinishUnlockOnSuccess undefined");
expect(policy.shouldFinishUnlockOnSuccess(1), false, "shouldFinishUnlockOnSuccess truthy non-boolean");

// shouldRetryAfterFailure: configured AND neither mid-password-auth nor
// budget-exhausted.
const retryPermissive = { fingerprintConfigured: true, authenticatingPassword: false, fingerprintExhausted: false };
expect(policy.shouldRetryAfterFailure(retryPermissive), true, "shouldRetryAfterFailure permissive baseline");
expect(
  policy.shouldRetryAfterFailure({ ...retryPermissive, fingerprintConfigured: false }),
  false,
  "shouldRetryAfterFailure vetoed by fingerprintConfigured=false"
);
expect(
  policy.shouldRetryAfterFailure({ ...retryPermissive, authenticatingPassword: true }),
  false,
  "shouldRetryAfterFailure vetoed by authenticatingPassword=true"
);
expect(
  policy.shouldRetryAfterFailure({ ...retryPermissive, fingerprintExhausted: true }),
  false,
  "shouldRetryAfterFailure vetoed by fingerprintExhausted=true"
);

// Event-sequence: a full simulated lock lifecycle, mirroring the real
// scripts/patch-lock-service call sites end to end, not just each
// function in isolation.
const maxAttempts = 5;
let fingerprintAttempts = 0;
let fingerprintReady = false;
let fingerprintPamActive = false;
let fingerprintAuthenticating = false;
let fingerprintConfigured = false;
const pamConfigured = true;

// beginLock: budget resets, nothing is ready yet.
fingerprintAttempts = 0;
expect(policy.isExhausted(fingerprintAttempts, maxAttempts), false, "sequence: fresh lock is not exhausted");

// The readiness probe comes back indeterminate first (daemon still
// starting) - must fail closed, never optimistically ready.
fingerprintReady = policy.nextReadyAfterProbe(2);
expect(fingerprintReady, false, "sequence: indeterminate probe leaves fingerprintReady false");
fingerprintConfigured = policy.isConfigured(pamConfigured, fingerprintReady);
expect(
  policy.canStartFingerprint({
    lockRequested: true,
    sessionSecure: true,
    fingerprintConfigured,
    authenticatingPassword: false,
    fingerprintExhausted: policy.isExhausted(fingerprintAttempts, maxAttempts),
    fingerprintPamActive,
    fingerprintAuthenticating,
  }),
  false,
  "sequence: cannot start before capability is configured"
);

// The probe resolves positively - now a start is legitimate.
fingerprintReady = policy.nextReadyAfterProbe(0);
fingerprintConfigured = policy.isConfigured(pamConfigured, fingerprintReady);
expect(fingerprintConfigured, true, "sequence: ready probe plus pam capability configures fingerprint");
expect(
  policy.canStartFingerprint({
    lockRequested: true,
    sessionSecure: true,
    fingerprintConfigured,
    authenticatingPassword: false,
    fingerprintExhausted: policy.isExhausted(fingerprintAttempts, maxAttempts),
    fingerprintPamActive,
    fingerprintAuthenticating,
  }),
  true,
  "sequence: start is legitimate once configured and idle"
);

// startFingerprint fires: budget consumed, conversation now in flight -
// a concurrent start attempt must be vetoed while it is.
fingerprintAttempts += 1;
fingerprintAuthenticating = true;
fingerprintPamActive = true;
expect(
  policy.canStartFingerprint({
    lockRequested: true,
    sessionSecure: true,
    fingerprintConfigured,
    authenticatingPassword: false,
    fingerprintExhausted: policy.isExhausted(fingerprintAttempts, maxAttempts),
    fingerprintPamActive,
    fingerprintAuthenticating,
  }),
  false,
  "sequence: a second start is vetoed while one is already in flight"
);

// It fails, and budget is not yet exhausted - a retry is scheduled.
fingerprintAuthenticating = false;
fingerprintPamActive = false;
expect(
  policy.shouldRetryAfterFailure({
    fingerprintConfigured,
    authenticatingPassword: false,
    fingerprintExhausted: policy.isExhausted(fingerprintAttempts, maxAttempts),
  }),
  true,
  "sequence: first failure retries"
);

// Drive failures until the budget is exhausted.
while (!policy.isExhausted(fingerprintAttempts, maxAttempts)) {
  fingerprintAttempts += 1;
}
expect(fingerprintAttempts, maxAttempts, "sequence: attempts landed exactly on the budget");
expect(
  policy.shouldRetryAfterFailure({
    fingerprintConfigured,
    authenticatingPassword: false,
    fingerprintExhausted: policy.isExhausted(fingerprintAttempts, maxAttempts),
  }),
  false,
  "sequence: exhausted budget stops retrying even though still configured"
);
expect(
  policy.canStartFingerprint({
    lockRequested: true,
    sessionSecure: true,
    fingerprintConfigured,
    authenticatingPassword: false,
    fingerprintExhausted: policy.isExhausted(fingerprintAttempts, maxAttempts),
    fingerprintPamActive,
    fingerprintAuthenticating,
  }),
  false,
  "sequence: exhausted budget also blocks starting a fresh conversation"
);

// The user starts typing their password mid-lock - fingerprint must
// stand aside even if it still had budget left.
expect(
  policy.canStartFingerprint({
    lockRequested: true,
    sessionSecure: true,
    fingerprintConfigured,
    authenticatingPassword: true,
    fingerprintExhausted: false,
    fingerprintPamActive: false,
    fingerprintAuthenticating: false,
  }),
  false,
  "sequence: password authentication in progress vetoes a fingerprint start"
);

// Capability is revoked mid-conversation (e.g. the PAM service file
// disappears) while a success result is already in flight - the success
// callback must read the revoked state, not the state captured when the
// conversation began, and must fail closed instead of unlocking.
fingerprintReady = policy.nextReadyAfterCapabilityRevoked();
fingerprintConfigured = policy.isConfigured(pamConfigured, fingerprintReady);
expect(fingerprintConfigured, false, "sequence: capability revocation deconfigures fingerprint");
expect(
  policy.shouldFinishUnlockOnSuccess(fingerprintConfigured),
  false,
  "sequence: a stale success after revocation must not finish the unlock"
);

// A lock screen that is not yet secure (e.g. mid-animation) never starts
// fingerprint, regardless of every other flag being permissive.
expect(
  policy.canStartFingerprint({ ...permissive, sessionSecure: false }),
  false,
  "sequence: an insecure session never starts fingerprint"
);

// Once lock is no longer requested (already unlocked), no start follows
// even if every other flag is still permissive from the prior session.
expect(
  policy.canStartFingerprint({ ...permissive, lockRequested: false }),
  false,
  "sequence: an unlocked session never starts fingerprint"
);

console.log("security lock fingerprint behavioral state machine checks passed");
NODE
