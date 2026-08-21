#!/usr/bin/env python3
"""Adversarial self-test for test/lib/recovery-check-helpers.py.

Run as: python3 recovery-check-helpers-selftest.py <path-to-recovery-check-helpers.py>

Proves the shared CHECK-line assertion helper actually fails closed, so the
false-green failure mode it was written to prevent (missing-check-still-
passes) cannot silently move from the VM tests into this shared parser
instead.
"""
import sys

path = sys.argv[1]
ns = {}
with open(path, encoding="utf-8") as f:
    exec(compile(f.read(), path, "exec"), ns)
assert_checks = ns["assert_checks"]
CheckAssertionError = ns["CheckAssertionError"]


def expect_pass(output, required):
    assert_checks(output, required)


def expect_fail(output, required, why):
    try:
        assert_checks(output, required)
    except CheckAssertionError:
        return
    raise AssertionError(f"expected assert_checks to reject case: {why}")


# Happy path: exact required set, all PASS, nothing extra.
expect_pass("CHECK a PASS\nCHECK b PASS x=1\n", {"a", "b"})

# DIAG and blank lines must never participate.
expect_pass("DIAG noise\nCHECK a PASS\n\nCHECK b PASS\n", {"a", "b"})

# Expected PASS missing entirely.
expect_fail("CHECK a PASS\n", {"a", "b"}, "missing required check b")

# Expected check appears as FAIL.
expect_fail("CHECK a PASS\nCHECK b FAIL reason\n", {"a", "b"}, "explicit FAIL")

# Duplicate contradictory PASS+FAIL for the same name.
expect_fail(
    "CHECK a PASS\nCHECK a FAIL\n", {"a"}, "duplicate contradictory PASS+FAIL"
)

# Duplicate PASS+PASS for the same name (uniqueness expected).
expect_fail("CHECK a PASS\nCHECK a PASS\n", {"a"}, "duplicate PASS for a unique check")

# Unknown/malformed state word.
expect_fail("CHECK a MAYBE\n", {"a"}, "unknown state word")

# Missing state token entirely.
expect_fail("CHECK a\n", {"a"}, "missing state token")

# Zero CHECK lines at all.
expect_fail("nothing but plain log output\n", {"a"}, "zero CHECK lines")

# Unexpected extra CHECK name beyond the required set must also fail -
# a scenario silently emitting a name the caller didn't declare is exactly
# the kind of drift this helper exists to catch.
expect_fail(
    "CHECK a PASS\nCHECK b PASS\n", {"a"}, "unexpected extra CHECK name"
)

# Optional DIAG lines interleaved with an otherwise-valid required set must
# not affect the result either way.
expect_pass("CHECK a PASS\nDIAG whatever happened\nCHECK b PASS\n", {"a", "b"})

print("recovery-check-helpers self-test: all adversarial cases behaved as expected")
