#!/usr/bin/env python3
"""Adversarial self-test for test/lib/recovery-contract-helpers.py.

Run as:
  python3 recovery-contract-helpers-selftest.py <path-to-recovery-contract-helpers.py>

Proves the recovery-matrix <-> ledger contract actually fails closed against
every drift mode issue atqamz/omanixy#4's remediation identified as
previously false-open: an RBS bullet with no id, an unknown id, a
cross-surface id, a passed case cited as outstanding, an outstanding case
never cited, a duplicate matrix id, and every unregistered/mismatched/stale
check-id combination against a synthetic RECOVERY_CHECKS registry. Uses
synthetic fixtures only - never touches upstream/security-recovery-matrix.yaml
or upstream/porting-matrix.yaml, so it stays meaningful even if those files
are momentarily broken by unrelated work in progress.
"""
import copy
import sys

path = sys.argv[1]
ns = {}
with open(path, encoding="utf-8") as f:
    exec(compile(f.read(), path, "exec"), ns)
validate = ns["validate"]

RECOVERY_CHECKS = {
    "surfacea.scenario1": {"owner": "security.surface-a", "checks": frozenset({"x"}), "implemented": True},
    "surfacea.placeholder": {"owner": "security.surface-a", "checks": frozenset(), "implemented": False},
    "surfaceb.scenario1": {"owner": "security.surface-b", "checks": frozenset({"y"}), "implemented": True},
    "core.placeholder": {"owner": "security.recovery", "checks": frozenset(), "implemented": False},
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


# Baseline fixture must itself be valid, or every perturbation test below is
# meaningless (it could be failing for a reason unrelated to the one
# perturbed field).
expect_pass(copy.deepcopy(MATRIX), copy.deepcopy(LEDGER))

# --- Part F: ledger <-> matrix cross-reference exactness ---

# RBS bullet with no recovery.<id> token at all: the owning entry's
# outstanding case is then unreferenced.
m = copy.deepcopy(LEDGER)
m["items"][0]["evidence"]["required_before_supported"] = ["needs real hardware, no id here"]
expect_fail(copy.deepcopy(MATRIX), m, "required_before_supported bullet with no recovery id")

# Unknown id cited in required_before_supported.
m = copy.deepcopy(LEDGER)
m["items"][0]["evidence"]["required_before_supported"].append("recovery.does-not-exist also needed")
expect_fail(copy.deepcopy(MATRIX), m, "required_before_supported cites an unknown matrix id")

# Cross-surface id: security.surface-b cites a case owned by security.surface-a.
m = copy.deepcopy(LEDGER)
m["items"][1]["evidence"]["required_before_supported"] = ["recovery.a-hw cited from the wrong surface"]
expect_fail(copy.deepcopy(MATRIX), m, "required_before_supported cites a cross-surface matrix id")

# Passed case referenced as if still outstanding.
m = copy.deepcopy(LEDGER)
m["items"][0]["evidence"]["required_before_supported"].append("recovery.a-passed still pending??")
expect_fail(copy.deepcopy(MATRIX), m, "required_before_supported cites an already-passed matrix id")

# Non-passed case owned by this surface, never referenced anywhere.
m = copy.deepcopy(LEDGER)
m["items"][0]["evidence"]["required_before_supported"] = []
expect_fail(copy.deepcopy(MATRIX), m, "outstanding matrix case owned by this surface never referenced")

# Duplicate matrix id.
mx = copy.deepcopy(MATRIX)
mx["items"].append(copy.deepcopy(mx["items"][0]))
expect_fail(mx, copy.deepcopy(LEDGER), "duplicate recovery matrix id")

# security.recovery duplicating a child surface's own gap: security.recovery
# tries to also own recovery.a-hw (security.surface-a's own outstanding
# case) instead of leaving surface-a as its sole owner.
m = copy.deepcopy(LEDGER)
m["items"][2]["evidence"]["required_before_supported"].append("recovery.a-hw duplicated here too")
expect_fail(copy.deepcopy(MATRIX), m, "security.recovery duplicating a child surface's own gap")

# --- Part G: check field must be machine-bound, not prose ---

# Missing/empty check field.
mx = copy.deepcopy(MATRIX)
mx["items"][0]["check"] = ""
expect_fail(mx, copy.deepcopy(LEDGER), "empty check field")

mx = copy.deepcopy(MATRIX)
del mx["items"][0]["check"]
expect_fail(mx, copy.deepcopy(LEDGER), "missing check field")

# Unknown/bogus check id - "check: imaginary-check" must fail.
mx = copy.deepcopy(MATRIX)
mx["items"][0]["check"] = "imaginary-check"
expect_fail(mx, copy.deepcopy(LEDGER), "check id not present in RECOVERY_CHECKS")

# Cross-surface check id: a surface-a case citing a surface-b-owned check.
mx = copy.deepcopy(MATRIX)
mx["items"][0]["check"] = "surfaceb.scenario1"
expect_fail(mx, copy.deepcopy(LEDGER), "check id owned by a different surface than the case")

# Passed case citing a check id with no implemented evidence behind it.
mx = copy.deepcopy(MATRIX)
mx["items"][0]["check"] = "surfacea.placeholder"
expect_fail(mx, copy.deepcopy(LEDGER), "passed case citing an unimplemented check id")

# Non-passed case citing a check id that is already implemented (stale -
# this case should have been promoted to passed, not left outstanding).
mx = copy.deepcopy(MATRIX)
mx["items"][1]["check"] = "surfacea.scenario1"
expect_fail(mx, copy.deepcopy(LEDGER), "non-passed case citing an already-implemented check id")

# A structured list of check ids is accepted when every id is valid and
# correctly owned.
mx = copy.deepcopy(MATRIX)
mx["items"][0]["check"] = ["surfacea.scenario1"]
expect_pass(mx, copy.deepcopy(LEDGER))

print("recovery-contract-helpers self-test: all adversarial cases behaved as expected")
