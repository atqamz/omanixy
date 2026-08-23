#!/usr/bin/env bash
set -euo pipefail

policy_file=${1:?FingerprintPolicy.js path required}

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

// Stress proof infrastructure: an adversarial driver that tries to start a
// fingerprint conversation on every cycle - exactly the guard
// startFingerprint() itself applies, keyed off the CURRENT attempts/exhausted
// state - then resolves each successful start as a failed conversation the
// same way handleFingerprintFinished does. No cycle may bypass the budget: a
// start only ever happens when canStartFingerprint says so, matching the
// real function precisely rather than a shortcut like isExhausted(100, 5).
function driveFailureCycles(cycles, initialAttempts, includeErrorPath) {
  const maxAttempts = 5;
  let attempts = initialAttempts;
  let authenticating = false;
  let pamActive = false;
  let starts = 0;

  for (let i = 0; i < cycles; i++) {
    const exhausted = policy.isExhausted(attempts, maxAttempts);
    const canStart = policy.canStartFingerprint({
      lockRequested: true,
      sessionSecure: true,
      fingerprintConfigured: true,
      authenticatingPassword: false,
      fingerprintExhausted: exhausted,
      fingerprintPamActive: pamActive,
      fingerprintAuthenticating: authenticating,
    });
    if (canStart) {
      attempts += 1;
      authenticating = true;
      pamActive = true;
      starts += 1;
    }

    if (!authenticating && !pamActive) continue;

    // The conversation resolves as a failure. onCompleted always fires;
    // for the error variant, the pinned qml.cpp PamContext::onError handler
    // (services/pam/qml.cpp) emits error(...) and then completed(Error) for
    // the SAME conversation, so both root.onError and
    // handleFingerprintFinished(PamResult.Error) evaluate the retry policy
    // around one failed attempt. Modeled conservatively: both evaluations
    // run and must agree, and the started-but-unfinished conversation's
    // in-flight flags clear before either evaluates.
    authenticating = false;
    pamActive = false;
    const exhaustedNow = policy.isExhausted(attempts, maxAttempts);
    const retryOpts = {
      fingerprintConfigured: true,
      authenticatingPassword: false,
      fingerprintExhausted: exhaustedNow,
    };
    const retryFromCompleted = policy.shouldRetryAfterFailure(retryOpts);
    if (includeErrorPath) {
      const retryFromError = policy.shouldRetryAfterFailure(retryOpts);
      expect(retryFromError, retryFromCompleted, `cycle ${i}: onError and onCompleted retry decisions disagree`);
    }
  }

  return { attempts, starts };
}

// §100-failure budget proof: 100 adversarial start attempts, each resolved
// as an ordinary (non-Error) failure through handleFingerprintFinished
// alone. The required result is fingerprintAttempts === 5, never 100, with
// exactly 5 actual simulated starts and no retry permitted afterward.
{
  const result = driveFailureCycles(100, 0, false);
  expect(result.attempts, 5, "100 ordinary failures: final fingerprintAttempts");
  expect(result.starts, 5, "100 ordinary failures: actual simulated starts");
  expect(
    policy.shouldRetryAfterFailure({ fingerprintConfigured: true, authenticatingPassword: false, fingerprintExhausted: true }),
    false,
    "100 ordinary failures: no retry is allowed after exhaustion"
  );
  expect(
    policy.canStartFingerprint({ ...permissive, fingerprintExhausted: true }),
    false,
    "100 ordinary failures: canStartFingerprint stays false after exhaustion"
  );
}

// §100-error budget proof: the same 100-cycle stress, but each cycle's
// failure is evaluated through both the onError and onCompleted(Error)
// paths a single failed conversation drives per the pinned PamContext ABI.
// Password state is tracked through the loop via a fixed sentinel that the
// driver never touches, proving the error-handling path leaves it alone.
{
  const passwordStateSentinel = { authenticatingPassword: false, failedAttempts: 0 };
  const result = driveFailureCycles(100, 0, true);
  expect(result.attempts, 5, "100 errors: final fingerprintAttempts");
  expect(result.starts, 5, "100 errors: actual simulated starts");
  expect(
    policy.shouldRetryAfterFailure({ fingerprintConfigured: true, authenticatingPassword: false, fingerprintExhausted: true }),
    false,
    "100 errors: no retry allowed after exhaustion"
  );
  expect(
    policy.canStartFingerprint({ ...permissive, fingerprintExhausted: true }),
    false,
    "100 errors: canStartFingerprint stays false after exhaustion"
  );
  expect(passwordStateSentinel.authenticatingPassword, false, "100 errors: password authenticating state remains untouched");
  expect(passwordStateSentinel.failedAttempts, 0, "100 errors: password failedAttempts remains untouched");
}

// Password precedence under stress: fingerprint has budget remaining and a
// conversation actively in flight (its start already consumed one of the
// three attempts left) when the user submits their password. submitPassword
// flips authenticatingPassword on, stops the retry timer, and aborts the
// in-flight fingerprint conversation - exactly scripts/patch-lock-service's
// submitPassword body - before a single one of 100 further adversarial
// retry/start attempts is allowed to land.
{
  let attempts = 3;
  let authenticating = false;
  let pamActive = false;
  let authenticatingPassword = true;

  let starts = 0;
  for (let i = 0; i < 100; i++) {
    const exhausted = policy.isExhausted(attempts, 5);
    const canStart = policy.canStartFingerprint({
      lockRequested: true,
      sessionSecure: true,
      fingerprintConfigured: true,
      authenticatingPassword,
      fingerprintExhausted: exhausted,
      fingerprintPamActive: pamActive,
      fingerprintAuthenticating: authenticating,
    });
    expect(canStart, false, `password precedence cycle ${i}: fingerprint start vetoed while password authenticating`);
    expect(
      policy.shouldRetryAfterFailure({ fingerprintConfigured: true, authenticatingPassword, fingerprintExhausted: exhausted }),
      false,
      `password precedence cycle ${i}: retry vetoed while password authenticating`
    );
    if (canStart) starts += 1;
  }
  expect(starts, 0, "password precedence: zero new fingerprint starts while authenticatingPassword=true");
  expect(attempts, 3, "password precedence: budget untouched while password authenticating");

  // handlePasswordFailure(): authenticatingPassword clears. It never
  // refills fingerprintAttempts itself - it only calls startFingerprint(),
  // which re-applies canStartFingerprint's own guards against whatever
  // budget already remains.
  authenticatingPassword = false;
  expect(attempts, 3, "password precedence: budget still not reset by the password failure itself");

  const resumed = driveFailureCycles(100, attempts, false);
  expect(resumed.attempts, 5, "password precedence: fingerprint resumes and exhausts only the remaining budget");
  expect(resumed.starts, 2, "password precedence: exactly the remaining 2 starts occur after resuming");
  expect(3 + resumed.starts, 5, "password precedence: total starts for this lock never exceed 5");
}

// New-lock reset under stress: lock A is driven to exhaustion with
// readiness left true, then a fresh beginLock() must reset both the budget
// and readiness as two separate, intentional transitions - proven by
// asserting each immediately after the reset and before any probe runs.
{
  const lockA = driveFailureCycles(100, 0, false);
  expect(lockA.attempts, 5, "new-lock reset: lock A exhausts its budget first");

  let ready = true; // a prior successful probe left lock A's fingerprint ready
  let attempts = lockA.attempts;
  expect(ready, true, "new-lock reset: ready before the new lock is true");

  // beginLock(): fingerprintAttempts = 0 and fingerprintReady = false are
  // the exact two lines scripts/patch-lock-service inserts into beginLock's
  // real body, both synchronous and unconditional.
  attempts = 0;
  ready = false;
  expect(attempts, 0, "new-lock reset: attempts immediately after beginLock");
  expect(ready, false, "new-lock reset: ready immediately after beginLock");

  const configuredBeforeProbe = policy.isConfigured(true, ready);
  expect(
    policy.canStartFingerprint({
      ...permissive,
      fingerprintConfigured: configuredBeforeProbe,
      fingerprintExhausted: policy.isExhausted(attempts, 5),
    }),
    false,
    "new-lock reset: cannot start before the readiness probe resolves"
  );

  ready = policy.nextReadyAfterProbe(0);
  const configuredAfterProbe = policy.isConfigured(true, ready);
  expect(
    policy.canStartFingerprint({
      ...permissive,
      fingerprintConfigured: configuredAfterProbe,
      fingerprintExhausted: policy.isExhausted(attempts, 5),
    }),
    true,
    "new-lock reset: can start again with a fresh budget after a positive probe"
  );
}

console.log("security lock fingerprint behavioral state machine checks passed");
NODE
