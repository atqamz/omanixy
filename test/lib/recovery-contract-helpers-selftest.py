#!/usr/bin/env python3
import copy
import sys

path = sys.argv[1]
ns = {}
with open(path, encoding="utf-8") as f:
    exec(compile(f.read(), path, "exec"), ns)
validate = ns["validate"]

RECOVERY_CHECKS = {
    "surfacea.scenario1": {
        "owner": "security.surface-a", "checks": frozenset({"x"}), "implemented": True,
        "evidence": "test/fixture.sh", "matrix_cases": frozenset({"recovery.a-passed"}),
    },
    "surfacea.scenario2": {
        "owner": "security.surface-a", "checks": frozenset({"z"}), "implemented": True,
        "evidence": "test/fixture.sh", "matrix_cases": frozenset({"recovery.a-passed-2"}),
    },
    "surfacea.placeholder": {
        "owner": "security.surface-a", "checks": frozenset(), "implemented": False,
        "evidence": "none", "matrix_cases": frozenset({"recovery.a-hw"}),
    },
    "surfaceb.scenario1": {
        "owner": "security.surface-b", "checks": frozenset({"y"}), "implemented": True,
        "evidence": "test/fixture.sh", "matrix_cases": frozenset({"recovery.b-passed"}),
    },
    "core.placeholder": {
        "owner": "security.recovery", "checks": frozenset(), "implemented": False,
        "evidence": "none", "matrix_cases": frozenset({"recovery.core"}),
    },
}

LEDGER = {
    "items": [
        {"id": "security.surface-a", "evidence": {"required_before_supported": ["recovery.a-hw needs real hardware, see recovery.a-hw"]}},
        {"id": "security.surface-b", "evidence": {"required_before_supported": []}},
        {"id": "security.recovery", "evidence": {"required_before_supported": ["recovery.core needs real hardware"]}},
    ]
}

MATRIX = {
    "items": [
        {
            "id": "recovery.a-passed", "surface": "security.surface-a", "environment": "nested-vm",
            "status": "passed", "evidence": "test/fixture.sh", "check": "surfacea.scenario1",
            "expected_invariant": "inv",
        },
        {
            "id": "recovery.a-hw", "surface": "security.surface-a", "environment": "physical-hardware",
            "status": "required-before-supported", "evidence": "none", "check": "surfacea.placeholder",
            "expected_invariant": "inv",
        },
        {
            "id": "recovery.b-passed", "surface": "security.surface-b", "environment": "nested-vm",
            "status": "passed", "evidence": "test/fixture.sh", "check": "surfaceb.scenario1",
            "expected_invariant": "inv",
        },
        {
            "id": "recovery.core", "surface": "security.recovery", "environment": "physical-hardware",
            "status": "required-before-supported", "evidence": "none", "check": "core.placeholder",
            "expected_invariant": "inv",
        },
        {
            "id": "recovery.a-passed-2", "surface": "security.surface-a", "environment": "nested-vm",
            "status": "passed", "evidence": "test/fixture.sh", "check": "surfacea.scenario2",
            "expected_invariant": "inv",
        },
    ]
}


def repo_path_exists(path):
    return path == "test/fixture.sh"


def expect_pass(matrix, ledger):
    validate(matrix, ledger, repo_path_exists, RECOVERY_CHECKS)


def expect_fail(matrix, ledger, why):
    try:
        validate(matrix, ledger, repo_path_exists, RECOVERY_CHECKS)
    except AssertionError:
        return
    raise AssertionError(f"expected validate() to reject case: {why}")


expect_pass(copy.deepcopy(MATRIX), copy.deepcopy(LEDGER))


m = copy.deepcopy(LEDGER)
m["items"][0]["evidence"]["required_before_supported"] = ["needs real hardware, no id here"]
expect_fail(copy.deepcopy(MATRIX), m, "required_before_supported bullet with no recovery id")

m = copy.deepcopy(LEDGER)
m["items"][0]["evidence"]["required_before_supported"].append("recovery.does-not-exist also needed")
expect_fail(copy.deepcopy(MATRIX), m, "required_before_supported cites an unknown matrix id")

m = copy.deepcopy(LEDGER)
m["items"][1]["evidence"]["required_before_supported"] = ["recovery.a-hw cited from the wrong surface"]
expect_fail(copy.deepcopy(MATRIX), m, "required_before_supported cites a cross-surface matrix id")

m = copy.deepcopy(LEDGER)
m["items"][0]["evidence"]["required_before_supported"].append("recovery.a-passed still pending??")
expect_fail(copy.deepcopy(MATRIX), m, "required_before_supported cites an already-passed matrix id")

m = copy.deepcopy(LEDGER)
m["items"][0]["evidence"]["required_before_supported"] = []
expect_fail(copy.deepcopy(MATRIX), m, "outstanding matrix case owned by this surface never referenced")

mx = copy.deepcopy(MATRIX)
mx["items"].append(copy.deepcopy(mx["items"][0]))
expect_fail(mx, copy.deepcopy(LEDGER), "duplicate recovery matrix id")

m = copy.deepcopy(LEDGER)
m["items"][2]["evidence"]["required_before_supported"].append("recovery.a-hw duplicated here too")
expect_fail(copy.deepcopy(MATRIX), m, "security.recovery duplicating a child surface's own gap")


mx = copy.deepcopy(MATRIX)
mx["items"][0]["check"] = ""
expect_fail(mx, copy.deepcopy(LEDGER), "empty check field")

mx = copy.deepcopy(MATRIX)
del mx["items"][0]["check"]
expect_fail(mx, copy.deepcopy(LEDGER), "missing check field")

mx = copy.deepcopy(MATRIX)
mx["items"][0]["check"] = "imaginary-check"
expect_fail(mx, copy.deepcopy(LEDGER), "check id not present in RECOVERY_CHECKS")

mx = copy.deepcopy(MATRIX)
mx["items"][0]["check"] = "surfaceb.scenario1"
expect_fail(mx, copy.deepcopy(LEDGER), "check id owned by a different surface than the case")

mx = copy.deepcopy(MATRIX)
mx["items"][0]["check"] = "surfacea.placeholder"
expect_fail(mx, copy.deepcopy(LEDGER), "passed case citing an unimplemented check id")

mx = copy.deepcopy(MATRIX)
mx["items"][1]["check"] = "surfacea.scenario1"
expect_fail(mx, copy.deepcopy(LEDGER), "non-passed case citing an already-implemented check id")

mx = copy.deepcopy(MATRIX)
mx["items"][0]["check"] = ["surfacea.scenario1"]
expect_pass(mx, copy.deepcopy(LEDGER))


mx = copy.deepcopy(MATRIX)
assert mx["items"][-1]["id"] == "recovery.a-passed-2"
mx["items"][-1]["check"] = "surfacea.scenario1"
expect_fail(mx, copy.deepcopy(LEDGER), "same-surface wrong scenario id (matrix_cases mismatch)")

checks = copy.deepcopy(RECOVERY_CHECKS)
checks["surfacea.scenario1"] = dict(checks["surfacea.scenario1"])
checks["surfacea.scenario1"]["matrix_cases"] = frozenset()
try:
    validate(copy.deepcopy(MATRIX), copy.deepcopy(LEDGER), repo_path_exists, checks)
except AssertionError:
    pass
else:
    raise AssertionError("expected validate() to reject a matrix case missing from scenario.matrix_cases")

checks = copy.deepcopy(RECOVERY_CHECKS)
checks["surfacea.scenario1"] = dict(checks["surfacea.scenario1"])
checks["surfacea.scenario1"]["matrix_cases"] = frozenset({"recovery.a-passed", "recovery.does-not-exist"})
try:
    validate(copy.deepcopy(MATRIX), copy.deepcopy(LEDGER), repo_path_exists, checks)
except AssertionError:
    pass
else:
    raise AssertionError("expected validate() to reject scenario.matrix_cases citing a nonexistent case")

mx = copy.deepcopy(MATRIX)
mx["items"][0]["evidence"] = "test/other-fixture.sh"


def repo_path_exists_with_other(path):
    return path in ("test/fixture.sh", "test/other-fixture.sh")


try:
    validate(mx, copy.deepcopy(LEDGER), repo_path_exists_with_other, copy.deepcopy(RECOVERY_CHECKS))
except AssertionError:
    pass
else:
    raise AssertionError("expected validate() to reject passed-case evidence that mismatches its scenario")


m = copy.deepcopy(LEDGER)
m["items"][0]["evidence"]["required_before_supported"] = [
    "existing gap (recovery.a-hw)",
    "another future support gap with no recovery id",
]
expect_fail(copy.deepcopy(MATRIX), m, "extra prose-only bullet alongside an otherwise-valid RBS list")

print("recovery-contract-helpers self-test: all adversarial cases behaved as expected")
