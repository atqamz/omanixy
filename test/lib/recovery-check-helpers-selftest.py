#!/usr/bin/env python3
"""Adversarial self-test for test/lib/recovery-check-helpers.py.

Run as: python3 recovery-check-helpers-selftest.py <path-to-recovery-check-helpers.py>

Proves the shared CHECK-line assertion helper actually fails closed, so the
false-green failure mode it was written to prevent (missing-check-still-
passes, or a required name nobody actually registered) cannot silently move
from the VM tests into this shared parser instead.

Two of the registered check names (chosen because they belong to the
smallest scenario, "notifications.ownership-delivery") stand in for generic
"a"/"b" placeholders throughout: since assert_checks now rejects any
`required` name that is not a member of some RECOVERY_CHECKS scenario, an
arbitrary unregistered placeholder name would fail every case here for the
wrong reason.
"""
import sys

path = sys.argv[1]
ns = {}
with open(path, encoding="utf-8") as f:
    exec(compile(f.read(), path, "exec"), ns)
assert_checks = ns["assert_checks"]
CheckAssertionError = ns["CheckAssertionError"]
RECOVERY_CHECKS = ns["RECOVERY_CHECKS"]

A, B = "ownership", "delivery"
assert {A, B} == RECOVERY_CHECKS["notifications.ownership-delivery"]["checks"], (
    "selftest fixture assumption drifted from the registry - update A/B"
)


def expect_pass(output, required):
    assert_checks(output, required)


def expect_fail(output, required, why):
    try:
        assert_checks(output, required)
    except CheckAssertionError:
        return
    raise AssertionError(f"expected assert_checks to reject case: {why}")


# Happy path: exact required set, all PASS, nothing extra.
expect_pass(f"CHECK {A} PASS\nCHECK {B} PASS x=1\n", {A, B})

# DIAG and blank lines must never participate.
expect_pass(f"DIAG noise\nCHECK {A} PASS\n\nCHECK {B} PASS\n", {A, B})

# Expected PASS missing entirely.
expect_fail(f"CHECK {A} PASS\n", {A, B}, f"missing required check {B}")

# Expected check appears as FAIL.
expect_fail(f"CHECK {A} PASS\nCHECK {B} FAIL reason\n", {A, B}, "explicit FAIL")

# Duplicate contradictory PASS+FAIL for the same name.
expect_fail(
    f"CHECK {A} PASS\nCHECK {A} FAIL\n", {A}, "duplicate contradictory PASS+FAIL"
)

# Duplicate PASS+PASS for the same name (uniqueness expected).
expect_fail(f"CHECK {A} PASS\nCHECK {A} PASS\n", {A}, "duplicate PASS for a unique check")

# Unknown/malformed state word.
expect_fail(f"CHECK {A} MAYBE\n", {A}, "unknown state word")

# Missing state token entirely.
expect_fail(f"CHECK {A}\n", {A}, "missing state token")

# Zero CHECK lines at all.
expect_fail("nothing but plain log output\n", {A}, "zero CHECK lines")

# Unexpected extra CHECK name beyond the required set must also fail -
# a scenario silently emitting a name the caller didn't declare is exactly
# the kind of drift this helper exists to catch.
expect_fail(
    f"CHECK {A} PASS\nCHECK {B} PASS\n", {A}, "unexpected extra CHECK name"
)

# Optional DIAG lines interleaved with an otherwise-valid required set must
# not affect the result either way.
expect_pass(f"CHECK {A} PASS\nDIAG whatever happened\nCHECK {B} PASS\n", {A, B})

# A `required` name that is not a member of any RECOVERY_CHECKS scenario at
# all (a typo, or a check invented ad hoc at a VM test's call site instead
# of registered in the shared registry) must be rejected up front, even if
# the output happens to contain a matching CHECK line for it.
expect_fail(
    "CHECK totally-bogus-check-id PASS\n",
    {"totally-bogus-check-id"},
    "required name not present in the RECOVERY_CHECKS registry",
)
expect_fail(
    f"CHECK {A} PASS\nCHECK totally-bogus-check-id PASS\n",
    {A, "totally-bogus-check-id"},
    "one registered and one unregistered required name in the same call",
)

# Every scenario's registered check name must be unique to that scenario's
# semantics - not literally globally unique text, since several scenarios
# legitimately share a name for the same underlying meaning (e.g.
# "request-active" appears in both polkit.user-cancel and
# polkit.daemon-cancel) - but the registry must at least be internally
# well-formed: every scenario has a real owner string and a checks set.
for scenario_id, scenario in RECOVERY_CHECKS.items():
    assert isinstance(scenario.get("owner"), str) and scenario["owner"].startswith("security."), (
        f"{scenario_id}: owner must be a security.* surface id"
    )
    assert isinstance(scenario.get("checks"), frozenset), f"{scenario_id}: checks must be a frozenset"
    assert isinstance(scenario.get("implemented"), bool), f"{scenario_id}: implemented must be a bool"
    if not scenario["implemented"]:
        assert not scenario["checks"], f"{scenario_id}: unimplemented scenario must have an empty checks set"

print("recovery-check-helpers self-test: all adversarial cases behaved as expected")
