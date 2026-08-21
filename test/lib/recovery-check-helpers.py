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
# See test/lib/recovery-check-helpers-selftest.py for the adversarial tests
# that pin this behavior.


class CheckAssertionError(AssertionError):
    pass


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
    """
    required = set(required)
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
