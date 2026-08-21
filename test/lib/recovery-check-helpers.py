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
#   - each VM test's `assert_scenario(out, scenario_id)` call, which resolves
#     this registry's own exact "checks" set for that scenario id - a caller
#     can never substitute an arbitrary subset;
#   - upstream/security-recovery-matrix.yaml's `check:` field, which names a
#     scenario id (or a list of them) from this registry instead of free
#     prose a typo could silently corrupt, and which must itself appear in
#     that scenario's own "matrix_cases" set below - a scenario id shared by
#     coincidence (same owner, same evidence file) can never stand in for a
#     matrix case it does not actually own;
#   - test/security-recovery-contract.sh (via recovery-contract-helpers.py),
#     which rejects any matrix `check:` entry that is not a real key here, or
#     whose registered owner/evidence/matrix_cases membership does not match
#     the matrix case's own surface/evidence/id.
#
# Each entry's "evidence" names the one VM test file whose driver script
# actually emits that scenario's CHECK lines ("none" for an implemented=False
# placeholder, which emits none at all). "matrix_cases" is the exact,
# closed set of upstream/security-recovery-matrix.yaml row ids this scenario
# is legitimate evidence for - never merely "some case with the same owner",
# since two scenarios can share both an owner and an evidence file while
# meaning entirely different things.
#
# See test/lib/recovery-check-helpers-selftest.py for the adversarial tests
# that pin this behavior.


class CheckAssertionError(AssertionError):
    pass


def _scenario(owner, checks, evidence, matrix_cases, implemented=True):
    return {
        "owner": owner,
        "checks": frozenset(checks),
        "evidence": evidence,
        "matrix_cases": frozenset(matrix_cases),
        "implemented": implemented,
    }


PAM_VM = "test/security-recovery-pam-vm.nix"
POLKIT_VM = "test/security-recovery-polkit-vm.nix"
NOTIFICATIONS_VM = "test/security-recovery-notifications-vm.nix"
CROSS_FEATURE_VM = "test/security-recovery-cross-feature-vm.nix"

# Every entry below is either:
#   - implemented=True: a real VM scenario that emits `CHECK <name> PASS|FAIL`
#     lines for every name in "checks", validated live against a real
#     backend by an `assert_scenario` call in the owning .nix test; or
#   - implemented=False: a documented placeholder for a scenario that would
#     need real hardware/environment/scale this flake cannot provide today
#     (no "checks" are ever emitted for these, "evidence" is "none", and a
#     "passed" matrix row may never cite one).
RECOVERY_CHECKS = {
    # --- security.pam-password (test/security-recovery-pam-vm.nix, `machine`) ---
    "pam-password.live-conversation": _scenario(
        "security.pam-password",
        {"correct-password-success", "wrong-password-failure"},
        PAM_VM,
        {"recovery.pam-live-conversation"},
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
        PAM_VM,
        {"recovery.pam-repeated-failure"},
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
        PAM_VM,
        {"recovery.pam-cancel"},
    ),
    "pam-password.missing-service": _scenario(
        "security.pam-password",
        {"service-absent", "not-ordinary-failure", "start-failed-distinct"},
        PAM_VM,
        {"recovery.pam-missing-service"},
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
        PAM_VM,
        {"recovery.pam-fingerprint-no-device"},
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
        PAM_VM,
        {"recovery.pam-fingerprint-backend-unavailable"},
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
        PAM_VM,
        {"recovery.pam-fingerprint-backend-recovery"},
    ),
    # Section 2 remediation: "stress-log-quiescent" used to check only that
    # no Quickshell harness process remained, which is a process-count fact,
    # not log/journal quiescence. It is replaced by two real signals: a real
    # fprintd.service journal event count bounded proportionally to the
    # 20-attempt stimulus (stress-backend-log-bound), and that same count
    # re-measured after a short no-stimulus window and required to be
    # unchanged (stress-backend-log-quiescent) - genuine quiescence, measured
    # against the real backend's own journal, not inferred from process
    # absence. stress-no-quickshell-process and stress-no-fprintd-process
    # keep the process-level facts as their own, separately named, checks.
    "fingerprint.backend-stress": _scenario(
        "security.pam-fingerprint",
        {
            "stress-20-attempts-completed",
            "stress-zero-success",
            "stress-no-runaway-retry",
            "stress-backend-log-bound",
            "stress-backend-log-quiescent",
            "stress-no-quickshell-process",
            "stress-no-fprintd-process",
            "password-still-works-after-stress",
        },
        PAM_VM,
        {"recovery.pam-fingerprint-backend-stress"},
    ),
    "fingerprint.enrolled-hardware": _scenario(
        "security.pam-fingerprint", set(), "none",
        {"recovery.pam-fingerprint-enrolled-hardware"}, implemented=False,
    ),
    "fingerprint.tod-driver": _scenario(
        "security.pam-fingerprint", set(), "none",
        {"recovery.pam-fingerprint-tod-driver"}, implemented=False,
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
        PAM_VM,
        {"recovery.systemd-restart-bound"},
    ),

    # --- security.polkit-agent (test/security-recovery-polkit-vm.nix) ---
    "polkit.register": _scenario(
        "security.polkit-agent",
        {"rival-absent", "polkitd-active", "registered", "single-registration-event", "harness-alive"},
        POLKIT_VM,
        {"recovery.polkit-real-registration"},
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
        POLKIT_VM,
        {"recovery.polkit-real-authentication"},
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
        POLKIT_VM,
        {"recovery.polkit-cancellation"},
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
        POLKIT_VM,
        {"recovery.polkit-cancellation"},
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
        POLKIT_VM,
        {"recovery.polkit-runtime-collision"},
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
        POLKIT_VM,
        {"recovery.polkit-stress-finite"},
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
        POLKIT_VM,
        {"recovery.polkit-daemon-restart"},
    ),
    # Section 5 remediation: real evidence already proved a finite 20-cycle
    # stress bounded and non-growing (polkit.stress above); a larger-scale
    # (hundreds-of-cycles) repeat remains an explicit, machine-tracked
    # required-before-supported gap rather than untracked prose.
    "polkit.stress-large-scale": _scenario(
        "security.polkit-agent", set(), "none",
        {"recovery.polkit-stress-large-scale"}, implemented=False,
    ),
    "polkit.nested-compositor": _scenario(
        "security.polkit-agent", set(), "none",
        {"recovery.polkit-nested-compositor"}, implemented=False,
    ),
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
        CROSS_FEATURE_VM,
        {"recovery.polkit-crash-midauth"},
    ),

    # --- security.notification-daemon (test/security-recovery-notifications-vm.nix) ---
    "notifications.ownership-delivery": _scenario(
        "security.notification-daemon", {"ownership", "delivery"},
        NOTIFICATIONS_VM, {"recovery.notifications-real-ownership"},
    ),
    "notifications.replace-action-close": _scenario(
        "security.notification-daemon",
        {"replace-identity", "replace-content", "default-action", "close-roundtrip"},
        NOTIFICATIONS_VM,
        {"recovery.notifications-replacement-action-close"},
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
        NOTIFICATIONS_VM,
        {"recovery.notifications-dnd-persistence"},
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
        NOTIFICATIONS_VM,
        {"recovery.notifications-unknown-owner-collision"},
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
        NOTIFICATIONS_VM,
        {"recovery.notifications-burst"},
    ),
    "notifications.session-phase1": _scenario(
        "security.notification-daemon", {"session-phase1-ownership", "session-phase1-delivery"},
        NOTIFICATIONS_VM, {"recovery.notifications-session-bus-lifecycle"},
    ),
    "notifications.session-phase2": _scenario(
        "security.notification-daemon", {"session-phase2-ownership", "session-phase2-delivery"},
        NOTIFICATIONS_VM, {"recovery.notifications-session-bus-lifecycle"},
    ),
    # Section 1 remediation: "dunst-owns-name" now requires proving the real
    # D-Bus unique owner's GetConnectionUnixProcessID result equals dunst's
    # own PID (plus a /proc/<pid>/exe identity cross-check), not merely that
    # some owner exists. "dunst-owns-name-pid-stable" and
    # "quattro-reclaims-name-pid" are new, explicitly-named checks proving
    # owner-PID identity is stable while Quattro runs alongside dunst, and
    # that the post-reclaim owner is genuinely the Quattro harness PID (and
    # not merely a different-looking owner string).
    "notifications.known-daemon-collision": _scenario(
        "security.notification-daemon",
        {
            "xvfb-display-ready",
            "dunst-started",
            "dunst-owns-name",
            "quattro-did-not-steal-name",
            "dunst-owns-name-pid-stable",
            "dunst-alive-during-collision",
            "quattro-alive-during-collision",
            "test-terminates-dunst",
            "quattro-reclaims-name",
            "quattro-reclaims-name-pid",
            "post-reclaim-delivery",
        },
        NOTIFICATIONS_VM,
        {"recovery.notifications-known-daemon-collision"},
    ),
    "notifications.monitor-hotplug": _scenario(
        "security.notification-daemon", set(), "none",
        {"recovery.notifications-monitor-hotplug"}, implemented=False,
    ),
    # Section 5 remediation: mako/swaync/fnott are wlr-layer-shell-only and
    # remain blocked by the same live-Wayland-compositor unavailability as
    # recovery.lock-nested-compositor, distinct from dunst's already-proved
    # X11-backed collision above and from monitor-hotplug's own presentation
    # gap - each now its own explicit, machine-tracked case rather than
    # untracked prose.
    "notifications.named-daemon-breadth": _scenario(
        "security.notification-daemon", set(), "none",
        {"recovery.notifications-named-daemon-breadth"}, implemented=False,
    ),

    # --- security.lock / security.idle nested-compositor placeholders ---
    "lock.nested-compositor": _scenario(
        "security.lock", set(), "none", {"recovery.lock-nested-compositor"}, implemented=False,
    ),
    "idle.nested-compositor": _scenario(
        "security.idle", set(), "none", {"recovery.idle-nested-compositor"}, implemented=False,
    ),
    # Section 5 remediation: a real declarative idle-owner conflict
    # (hypridle/swayidle actually running) is blocked by the same live
    # Wayland connection Quickshell's own IdleMonitor cannot reach in this
    # environment, distinct from the already-proven Home Manager assertion
    # matrix (a build-time, non-live proof) and now its own explicit case.
    "idle.real-external-owner": _scenario(
        "security.idle", set(), "none", {"recovery.idle-real-external-owner"}, implemented=False,
    ),

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
        CROSS_FEATURE_VM,
        {"recovery.cross-feature-boot"},
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
        CROSS_FEATURE_VM,
        {"recovery.cross-feature-crash"},
    ),
    "suspend-resume.cycle": _scenario(
        "security.recovery", set(), "none", {"recovery.suspend-resume"}, implemented=False,
    ),
    "lid.hardware": _scenario(
        "security.recovery", set(), "none", {"recovery.lid-hardware"}, implemented=False,
    ),
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

    Low-level and testable on its own, but production VM call sites use
    `assert_scenario` instead, which binds this call to one exact,
    registered scenario identity rather than letting a caller assemble an
    arbitrary subset of registered names.
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


def assert_scenario(output, scenario_id):
    """Fail closed unless `scenario_id` names a real, implemented
    RECOVERY_CHECKS entry, then assert `output` against exactly that
    scenario's own registered "checks" set.

    This is the only entry point production VM call sites may use: unlike
    `assert_checks`, a caller cannot assemble or narrow an arbitrary subset
    of registered names - it names one scenario identity and gets that
    scenario's exact, full required set back, resolved from the registry
    itself. An unknown scenario id, or one whose registry entry is
    `implemented=False` (a documented placeholder with no real evidence),
    is rejected before any output is even parsed.
    """
    scenario = RECOVERY_CHECKS.get(scenario_id)
    if scenario is None:
        raise CheckAssertionError(f"unknown RECOVERY_CHECKS scenario id: {scenario_id!r}")
    if not scenario["implemented"]:
        raise CheckAssertionError(
            f"RECOVERY_CHECKS scenario {scenario_id!r} is not implemented (no real "
            "evidence exists) - no VM test may assert against it"
        )
    assert_checks(output, scenario["checks"])
