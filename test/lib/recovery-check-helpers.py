# Shared `CHECK <name> PASS|FAIL ...` line parser/assertion for the Layer 8
# (security-recovery) NixOS VM test scripts. Spliced verbatim into each VM
# test's Python `testScript` via `builtins.readFile` (a plain source read, not
# an import-from-derivation, so it never breaks `nix flake check --no-build`).
#
# This exists because "no CHECK line said FAIL" is not sufficient evidence
# that a scenario actually exercised what it claims: a driver script that
# silently skips a step never emits its CHECK line at all, and the old
# absence-of-FAIL-only assertion would still pass. `assert_checks` instead
# requires the exact named set of PASS checks a scenario is supposed to
# produce - a missing name is as much a failure as an explicit FAIL line.
#
# RECOVERY_CHECKS below is the one canonical registry of named recovery
# scenarios shared by three otherwise-independent places that would
# otherwise drift apart silently:
#   - each VM test's `assert_checks(out, RECOVERY_CHECKS[scenario_id]["checks"])`
#     call, which used to hand-type its own required-set literal;
#   - upstream/security-recovery-matrix.yaml's `check:` field, which now
#     names a scenario id (or a list of them) from this registry instead of
#     free prose a typo could silently corrupt;
#   - test/security-recovery-contract.sh (via recovery-contract-helpers.py),
#     which rejects any matrix `check:` entry that is not a real key here, or
#     whose registered owner does not match the matrix case's own surface.
#
# See test/lib/recovery-check-helpers-selftest.py for the adversarial tests
# that pin this behavior.


class CheckAssertionError(AssertionError):
    pass


def _scenario(owner, checks, implemented=True):
    return {"owner": owner, "checks": frozenset(checks), "implemented": implemented}


# Every entry below is either:
#   - implemented=True: a real VM scenario that emits `CHECK <name> PASS|FAIL`
#     lines for every name in "checks", validated live against a real
#     backend by an `assert_checks` call in the owning .nix test; or
#   - implemented=False: a documented placeholder for a scenario that would
#     need real hardware/environment this flake cannot provide today (no
#     "checks" are ever emitted for these; a "passed" matrix row may never
#     cite one).
RECOVERY_CHECKS = {
    # --- security.pam-password (test/security-recovery-pam-vm.nix, `machine`) ---
    "pam-password.live-conversation": _scenario(
        "security.pam-password", {"correct-password-success", "wrong-password-failure"}
    ),
    "pam-password.repeated-failure": _scenario(
        "security.pam-password",
        {
            "repeat-final-success",
            "attempt-count-bound",
            "event-volume-bound",
            "helper-no-growth-immediate",
            "helper-no-growth-after-wait",
        },
    ),
    "pam-password.cancel": _scenario(
        "security.pam-password",
        {
            "abort-event",
            "not-success",
            "not-ordinary-failure",
            "aborted-active-false",
            "bounded-elapsed",
            "no-orphan-process",
        },
    ),
    "pam-password.missing-service": _scenario(
        "security.pam-password",
        {"service-absent", "not-ordinary-failure", "start-failed-distinct"},
    ),

    # --- security.pam-fingerprint (test/security-recovery-pam-vm.nix, `fingerprintMachine`) ---
    "fingerprint.no-device": _scenario(
        "security.pam-fingerprint",
        {
            "pam-service-exists",
            "fprintd-enable-false",
            "dbus-activation-surface-exists",
            "backend-activated",
            "manager-responds",
            "get-devices-empty",
            "fingerprint-never-success",
            "fingerprint-bounded",
            "password-still-works",
        },
    ),
    "fingerprint.backend-unavailable": _scenario(
        "security.pam-fingerprint",
        {
            "backend-genuinely-unavailable",
            "fingerprint-never-success",
            "fingerprint-bounded-failure",
            "no-runaway-retry",
            "password-still-works",
        },
    ),
    "fingerprint.backend-recovery": _scenario(
        "security.pam-fingerprint",
        {
            "backend-restored",
            "manager-responds-again",
            "get-devices-empty-again",
            "fingerprint-bounded-again",
            "password-still-works-again",
        },
    ),
    "fingerprint.backend-stress": _scenario(
        "security.pam-fingerprint",
        {
            "stress-20-attempts-completed",
            "stress-zero-success",
            "stress-no-runaway-retry",
            "stress-single-process",
            "stress-log-bound",
            "stress-log-quiescent",
            "password-still-works-after-stress",
        },
    ),
    "fingerprint.enrolled-hardware": _scenario(
        "security.pam-fingerprint", set(), implemented=False
    ),
    "fingerprint.tod-driver": _scenario(
        "security.pam-fingerprint", set(), implemented=False
    ),

    # --- security.recovery: shell service crash-loop bound (pam-vm.nix, `machine`) ---
    "shell-restart.crash-loop-bound": _scenario(
        "security.recovery",
        {
            "crash-loop-bounded",
            "start-limit-hit",
            "restart-count-bounded",
            "reset-failed-succeeds",
            "fresh-start-accepted",
        },
    ),

    # --- security.polkit-agent (test/security-recovery-polkit-vm.nix) ---
    "polkit.register": _scenario(
        "security.polkit-agent",
        {"rival-absent", "polkitd-active", "registered", "single-registration-event", "harness-alive"},
    ),
    "polkit.auth": _scenario(
        "security.polkit-agent",
        {
            "agent-registered",
            "request-created",
            "wrong-password-failure",
            "reprompt-after-failure",
            "pkcheck-exit-zero",
            "correct-password-success",
            "flow-inactive-after",
        },
    ),
    "polkit.user-cancel": _scenario(
        "security.polkit-agent",
        {
            "request-active",
            "user-cancel-invoked",
            "requester-bounded",
            "flow-inactive-after-cancel",
            "no-stale-prompt",
            "harness-alive-after-cancel",
        },
    ),
    "polkit.daemon-cancel": _scenario(
        "security.polkit-agent",
        {
            "request-active",
            "daemon-cancel-stimulus",
            "flow-inactive-after-daemon-cancel",
            "no-stale-request",
            "no-shell-restart",
        },
    ),
    "polkit.collision": _scenario(
        "security.polkit-agent",
        {
            "rival-registered",
            "quattro-not-registered",
            "rival-remains-registered",
            "no-retry-while-rival-present",
            "test-terminates-rival",
            "quattro-remains-unregistered-after-rival-gone",
            "fresh-quattro-registers",
        },
    ),
    "polkit.stress": _scenario(
        "security.polkit-agent",
        {
            "stress-20-cycles-completed",
            "stress-single-harness-process",
            "stress-log-bound",
            "stress-no-continued-growth",
            "stress-final-correct-auth",
        },
    ),
    "polkit.daemon-restart": _scenario(
        "security.polkit-agent",
        {
            "request-active-before-restart",
            "inflight-requester-bounded",
            "same-harness-reprompt",
            "fresh-harness-registers",
            "fresh-harness-auth-success",
        },
    ),
    "polkit.nested-compositor": _scenario("security.polkit-agent", set(), implemented=False),
    # Same underlying scenario as "cross-feature.crash" below (both are
    # produced by one assert_checks call in
    # test/security-recovery-cross-feature-vm.nix's `crash` scenario); this
    # id names only the polkit-owned subset of that scenario's checks, for
    # recovery.polkit-crash-midauth, whose surface is security.polkit-agent
    # rather than security.recovery.
    "polkit.crash-midauth": _scenario(
        "security.polkit-agent",
        {
            "crash-polkit-inflight",
            "crash-polkit-client-bounded",
            "crash-polkit-fresh-registration",
            "crash-polkit-fresh-auth",
        },
    ),

    # --- security.notification-daemon (test/security-recovery-notifications-vm.nix) ---
    "notifications.ownership-delivery": _scenario(
        "security.notification-daemon", {"ownership", "delivery"}
    ),
    "notifications.replace-action-close": _scenario(
        "security.notification-daemon",
        {"replace-identity", "replace-content", "default-action", "close-roundtrip"},
    ),
    "notifications.dnd-restart": _scenario(
        "security.notification-daemon",
        {
            "dnd-on",
            "dnd-suppressed",
            "dnd-recorded-in-history",
            "dnd-settings-flushed",
            "dnd-restart-persisted",
        },
    ),
    "notifications.collision-reclaim": _scenario(
        "security.notification-daemon",
        {
            "stub-owns-name",
            "harness-did-not-steal-name",
            "harness-survives-collision",
            "harness-did-not-receive-during-collision",
            "reclaim-succeeded",
            "reclaim-no-restart",
            "reclaim-functional",
        },
    ),
    "notifications.burst": _scenario(
        "security.notification-daemon",
        {
            "burst-received-all",
            "burst-no-crash",
            "burst-history-bounded",
            "burst-responsive-after",
            "burst-log-bound",
            "burst-log-quiescent",
        },
    ),
    "notifications.session-phase1": _scenario(
        "security.notification-daemon", {"session-phase1-ownership", "session-phase1-delivery"}
    ),
    "notifications.session-phase2": _scenario(
        "security.notification-daemon", {"session-phase2-ownership", "session-phase2-delivery"}
    ),
    "notifications.known-daemon-collision": _scenario(
        "security.notification-daemon",
        {
            "xvfb-display-ready",
            "dunst-started",
            "dunst-owns-name",
            "quattro-did-not-steal-name",
            "dunst-alive-during-collision",
            "quattro-alive-during-collision",
            "test-terminates-dunst",
            "quattro-reclaims-name",
            "post-reclaim-delivery",
        },
    ),
    "notifications.monitor-hotplug": _scenario(
        "security.notification-daemon", set(), implemented=False
    ),

    # --- security.lock / security.idle nested-compositor placeholders ---
    "lock.nested-compositor": _scenario("security.lock", set(), implemented=False),
    "idle.nested-compositor": _scenario("security.idle", set(), implemented=False),

    # --- security.recovery: cross-feature + hardware placeholders ---
    "cross-feature.boot": _scenario(
        "security.recovery",
        {
            "boot-ready",
            "polkit-registration",
            "notifications-ownership",
            "pam-conversation",
            "polkit-authentication",
            "notifications-delivery",
            "single-process",
        },
    ),
    "cross-feature.crash": _scenario(
        "security.recovery",
        {
            "crash-setup",
            "crash-pam-inflight",
            "crash-polkit-inflight",
            "crash-notification-live",
            "crash-polkit-client-bounded",
            "crash-no-orphan-process",
            "crash-no-helper-leak",
            "crash-polkit-fresh-registration",
            "crash-polkit-fresh-auth",
            "crash-pam-fresh",
            "crash-notification-restored",
            "crash-notification-action-not-resurrected",
        },
    ),
    "suspend-resume.cycle": _scenario("security.recovery", set(), implemented=False),
    "lid.hardware": _scenario("security.recovery", set(), implemented=False),
}


def parse_checks(output):
    """Return {name: [states...]} for every `CHECK <name> <state> ...` line.

    Only lines that start with "CHECK " are considered; anything else
    (including "DIAG ..." lines) is ignored. Malformed lines (missing a
    name/state, or a state other than PASS/FAIL) are recorded under the
    sentinel key "" so callers can detect and reject them explicitly rather
    than silently dropping them.
    """
    seen = {}
    for line in output.splitlines():
        if not line.startswith("CHECK "):
            continue
        parts = line.split(None, 3)
        if len(parts) < 3 or parts[2] not in ("PASS", "FAIL"):
            seen.setdefault("", []).append(line)
            continue
        name = parts[1]
        seen.setdefault(name, []).append(parts[2])
    return seen


def assert_checks(output, required):
    """Fail closed unless `output` contains exactly one PASS for every name
    in `required`, and nothing else: no FAIL, no malformed line, no
    duplicate/contradictory report for any name, and no unexpected extra
    check name (an unrequested CHECK name is exactly as much a sign the
    scenario drifted from what this call documents as a missing one).

    `required` must itself be a subset of some RECOVERY_CHECKS entry's
    "checks" set - a caller passing a name that was never registered (a
    typo, or a check invented ad hoc at the call site instead of in the
    shared registry) is rejected the same way a missing or failed check is,
    so the registry cannot silently drift from what call sites actually
    require.
    """
    required = set(required)
    registered_names = set()
    for scenario in RECOVERY_CHECKS.values():
        registered_names |= scenario["checks"]

    unregistered = required - registered_names
    if unregistered:
        raise CheckAssertionError(
            f"required CHECK name(s) not present in any RECOVERY_CHECKS scenario: "
            f"{sorted(unregistered)}"
        )

    seen = parse_checks(output)
    errors = []

    malformed = seen.pop("", None)
    if malformed:
        errors.append("malformed CHECK line(s): " + " | ".join(malformed))

    for name, states in seen.items():
        fails = [s for s in states if s == "FAIL"]
        if fails:
            errors.append(f"CHECK {name!r} reported FAIL ({len(fails)}x)")
        if len(states) > 1:
            errors.append(f"CHECK {name!r} reported more than once: {states}")

    missing = sorted(required - set(seen))
    if missing:
        errors.append(f"missing required CHECK(s): {missing}")

    unexpected = sorted(set(seen) - required)
    if unexpected:
        errors.append(f"unexpected CHECK name(s) not in the required set: {unexpected}")

    if errors:
        raise CheckAssertionError(
            "\n".join(errors) + "\n\nfull output:\n" + output
        )
