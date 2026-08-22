#!/usr/bin/env python3
import sys

path = sys.argv[1]
ns = {}
with open(path, encoding="utf-8") as f:
    exec(compile(f.read(), path, "exec"), ns)
assert_checks = ns["assert_checks"]
assert_scenario = ns["assert_scenario"]
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


expect_pass(f"CHECK {A} PASS\nCHECK {B} PASS x=1\n", {A, B})

expect_pass(f"DIAG noise\nCHECK {A} PASS\n\nCHECK {B} PASS\n", {A, B})

expect_fail(f"CHECK {A} PASS\n", {A, B}, f"missing required check {B}")

expect_fail(f"CHECK {A} PASS\nCHECK {B} FAIL reason\n", {A, B}, "explicit FAIL")

expect_fail(
    f"CHECK {A} PASS\nCHECK {A} FAIL\n", {A}, "duplicate contradictory PASS+FAIL"
)

expect_fail(f"CHECK {A} PASS\nCHECK {A} PASS\n", {A}, "duplicate PASS for a unique check")

expect_fail(f"CHECK {A} MAYBE\n", {A}, "unknown state word")

expect_fail(f"CHECK {A}\n", {A}, "missing state token")

expect_fail("nothing but plain log output\n", {A}, "zero CHECK lines")

expect_fail(
    f"CHECK {A} PASS\nCHECK {B} PASS\n", {A}, "unexpected extra CHECK name"
)

expect_pass(f"CHECK {A} PASS\nDIAG whatever happened\nCHECK {B} PASS\n", {A, B})

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

for scenario_id, scenario in RECOVERY_CHECKS.items():
    assert isinstance(scenario.get("owner"), str) and scenario["owner"].startswith("security."), (
        f"{scenario_id}: owner must be a security.* surface id"
    )
    assert isinstance(scenario.get("checks"), frozenset), f"{scenario_id}: checks must be a frozenset"
    assert isinstance(scenario.get("implemented"), bool), f"{scenario_id}: implemented must be a bool"
    assert isinstance(scenario.get("evidence"), str) and scenario["evidence"], (
        f"{scenario_id}: evidence must be a non-empty string ('none' for a placeholder)"
    )
    assert isinstance(scenario.get("matrix_cases"), frozenset) and scenario["matrix_cases"], (
        f"{scenario_id}: matrix_cases must be a non-empty frozenset - every scenario must be "
        "tied to at least one real recovery matrix case id"
    )
    if not scenario["implemented"]:
        assert not scenario["checks"], f"{scenario_id}: unimplemented scenario must have an empty checks set"
        assert scenario["evidence"] == "none", f"{scenario_id}: unimplemented scenario must have evidence 'none'"


assert_scenario(f"CHECK {A} PASS\nCHECK {B} PASS\n", "notifications.ownership-delivery")

try:
    assert_scenario(f"CHECK {A} PASS\nCHECK {B} PASS\n", "totally-bogus-scenario-id")
except CheckAssertionError:
    pass
else:
    raise AssertionError("expected assert_scenario to reject an unknown scenario id")

for placeholder_id, placeholder in RECOVERY_CHECKS.items():
    if placeholder["implemented"]:
        continue
    try:
        assert_scenario("CHECK anything PASS\n", placeholder_id)
    except CheckAssertionError:
        pass
    else:
        raise AssertionError(
            f"expected assert_scenario to reject unimplemented scenario id {placeholder_id!r}"
        )
    break

try:
    assert_scenario(f"CHECK {A} PASS\n", "notifications.ownership-delivery")
except CheckAssertionError:
    pass
else:
    raise AssertionError("expected assert_scenario to require the scenario's full checks set")

print("recovery-check-helpers self-test: all adversarial cases behaved as expected")
