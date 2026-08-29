import re


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

RECOVERY_CHECKS = {
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
    "polkit.stress-large-scale": _scenario(
        "security.polkit-agent", set(), "none",
        {"recovery.polkit-stress-large-scale"}, implemented=False,
    ),
    "polkit.nested-compositor": _scenario(
        "security.polkit-agent", set(), "none",
        {"recovery.polkit-nested-compositor"}, implemented=False,
    ),
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
    "notifications.named-daemon-breadth": _scenario(
        "security.notification-daemon", set(), "none",
        {"recovery.notifications-named-daemon-breadth"}, implemented=False,
    ),

    "lock.nested-compositor": _scenario(
        "security.lock", set(), "none", {"recovery.lock-nested-compositor"}, implemented=False,
    ),
    "idle.nested-compositor": _scenario(
        "security.idle", set(), "none", {"recovery.idle-nested-compositor"}, implemented=False,
    ),
    "idle.real-external-owner": _scenario(
        "security.idle", set(), "none", {"recovery.idle-real-external-owner"}, implemented=False,
    ),

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


def parse_measurements(output):
    measurements = {}
    for line in output.splitlines():
        if not line.startswith("MEASURE "):
            continue
        match = re.fullmatch(r"MEASURE (\S+)(?: (.*))?", line)
        if match is None:
            raise CheckAssertionError(f"malformed MEASURE line: {line}")
        name, fields = match.groups()
        values = {}
        fields = fields or ""
        sequence = re.search(r"(?:^| )sequence=(.*)$", fields)
        scalar_fields = fields[:sequence.start()] if sequence else fields
        for field in re.finditer(r"(?:^| )([\w-]+)=([^ ]*)", scalar_fields):
            key, value = field.groups()
            if key in values:
                raise CheckAssertionError(f"duplicate MEASURE field {key!r}: {line}")
            values[key] = value
        if sequence:
            values["sequence"] = sequence.group(1)
        measurements.setdefault(name, []).append(values)
    return measurements


def assert_measurements(output, expected):
    actual = parse_measurements(output)
    if actual != expected:
        raise CheckAssertionError(
            f"unexpected MEASURE output:\nexpected: {expected!r}\nactual: {actual!r}"
        )


def assert_checks(output, required):
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
    scenario = RECOVERY_CHECKS.get(scenario_id)
    if scenario is None:
        raise CheckAssertionError(f"unknown RECOVERY_CHECKS scenario id: {scenario_id!r}")
    if not scenario["implemented"]:
        raise CheckAssertionError(
            f"RECOVERY_CHECKS scenario {scenario_id!r} is not implemented (no real "
            "evidence exists) - no VM test may assert against it"
        )
    assert_checks(output, scenario["checks"])
