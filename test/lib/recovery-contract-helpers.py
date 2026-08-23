# Pure validation logic for upstream/security-recovery-matrix.yaml against
# upstream/porting-matrix.yaml's security.* ledger entries, shared by
# test/security-recovery-contract.sh (real files) and
# test/lib/recovery-contract-helpers-selftest.py (synthetic adversarial
# fixtures). Kept import-free of yaml/os so the selftest can hand it plain
# dicts and a fake `path_exists` without touching disk, matching the
# discipline test/lib/recovery-check-helpers.py already uses for its own
# adversarial self-test.
import re

ENVIRONMENTS = {"hermetic", "nested-vm", "real-backend", "physical-hardware"}
STATUSES = {"passed", "unsupported-environment", "required-before-supported"}

# Matches a stable matrix case id embedded in ledger prose, e.g.
# "recovery.pam-fingerprint-backend-unavailable".
ID_RE = re.compile(r"\brecovery\.[a-z0-9][a-z0-9-]*\b")


def _check_ids(case):
    check = case.get("check")
    if isinstance(check, str):
        return [check] if check.strip() else []
    if isinstance(check, list):
        return [c for c in check if isinstance(c, str) and c.strip()]
    return []


def validate(matrix, ledger, repo_path_exists, recovery_checks):
    """Raise AssertionError on the first violation found; return None on success.

    `repo_path_exists(path)` replaces `os.path.exists(os.path.join(repo, path))`
    so fixtures never need a real filesystem. `recovery_checks` is the
    RECOVERY_CHECKS dict from recovery-check-helpers.py - the one registry
    this function cross-checks every matrix `check:` entry against, so an
    id that does not exist there, or whose registered owner does not match
    the matrix case's own surface, is rejected the same way a missing
    evidence file is.
    """
    items = matrix["items"]
    security = {item["id"]: item for item in ledger["items"] if item["id"].startswith("security.")}
    security_ids = set(security)

    seen_ids = set()
    by_id = {}
    for case in items:
        cid = case["id"]
        assert cid not in seen_ids, f"duplicate recovery matrix id: {cid}"
        seen_ids.add(cid)
        by_id[cid] = case

        assert case["surface"] in security_ids, f"{cid}: unknown surface {case['surface']!r}"
        assert case["environment"] in ENVIRONMENTS, f"{cid}: unknown environment {case['environment']!r}"
        assert case["status"] in STATUSES, f"{cid}: unknown status {case['status']!r}"
        assert case["expected_invariant"].strip(), f"{cid}: empty expected_invariant"

        check_ids = _check_ids(case)
        assert check_ids, f"{cid}: missing or empty check field"

        for check_id in check_ids:
            scenario = recovery_checks.get(check_id)
            assert scenario is not None, (
                f"{cid}: check id {check_id!r} is not registered in RECOVERY_CHECKS "
                "(unknown check id)"
            )
            assert scenario["owner"] == case["surface"], (
                f"{cid}: check id {check_id!r} is owned by {scenario['owner']!r}, "
                f"not this case's surface {case['surface']!r} (cross-surface check id)"
            )
            # A scenario id shared by coincidence (same owner, same evidence
            # file) can never stand in for a matrix case it does not itself
            # claim: e.g. two implemented, same-surface, same-evidence-file
            # scenarios must not be interchangeable just because nothing
            # else here distinguishes them.
            assert cid in scenario.get("matrix_cases", ()), (
                f"{cid}: check id {check_id!r} does not list this case in its own "
                "matrix_cases - a scenario must explicitly own every matrix case it is "
                "cited as evidence for (same-surface wrong-scenario mismatch)"
            )
            if case["status"] == "passed":
                assert scenario["implemented"], (
                    f"{cid}: status=passed cites check id {check_id!r}, which has no "
                    "implemented evidence (passed case whose check id is absent)"
                )
                assert scenario.get("evidence") == case["evidence"], (
                    f"{cid}: status=passed evidence {case['evidence']!r} does not match "
                    f"check id {check_id!r}'s own registered evidence "
                    f"{scenario.get('evidence')!r}"
                )
            else:
                assert not scenario["implemented"], (
                    f"{cid}: status={case['status']!r} cites check id {check_id!r}, which "
                    "is already implemented and passing elsewhere - promote this case to "
                    "passed instead of leaving it stale"
                )

        if case["status"] == "passed":
            assert case["evidence"] != "none", f"{cid}: passed row must cite real evidence"
            evidence_path = case["evidence"].split(" (", 1)[0].strip()
            assert repo_path_exists(evidence_path), (
                f"{cid}: evidence file {evidence_path!r} does not exist"
            )
            assert "attempted_evidence" not in case, f"{cid}: a passed row must not also carry attempted_evidence"
            assert "reason" not in case, f"{cid}: a passed row must not also carry a non-passed reason"
        else:
            assert case["evidence"] == "none", (
                f"{cid}: status={case['status']!r} rows must not cite evidence "
                "that was not actually produced"
            )
            if "attempted_evidence" in case:
                attempted = case["attempted_evidence"]
                assert attempted == "none" or (isinstance(attempted, str) and attempted.strip()), (
                    f"{cid}: attempted_evidence, if present, must be 'none' or non-empty text"
                )
                assert case.get("reason", "").strip(), (
                    f"{cid}: attempted_evidence is present but reason is missing or empty"
                )
            if "reason" in case:
                assert case["reason"].strip(), f"{cid}: reason, if present, must be non-empty"

    assert any(case["surface"] == "security.recovery" for case in items), (
        "security.recovery must be represented in the recovery matrix"
    )

    # Reverse direction of the same binding: every id a scenario's own
    # matrix_cases claims must be a real matrix case, and that case's own
    # check field must cite the scenario back - a registry entry cannot
    # unilaterally claim ownership of a case that never actually names it.
    for check_id, scenario in recovery_checks.items():
        for owned_cid in scenario.get("matrix_cases", ()):
            case = by_id.get(owned_cid)
            assert case is not None, (
                f"RECOVERY_CHECKS[{check_id!r}] matrix_cases cites unknown recovery "
                f"matrix id {owned_cid!r}"
            )
            assert check_id in _check_ids(case), (
                f"RECOVERY_CHECKS[{check_id!r}] claims matrix_cases {owned_cid!r}, but "
                f"that case's own check field does not cite {check_id!r} back"
            )

    # Exact bidirectional mapping between each ledger entry's own
    # required_before_supported prose and the matrix cases it owns - never a
    # bare "some case exists for this surface" check, and never satisfiable
    # by a different entry citing the same case (that would let
    # security.recovery, or any other entry, silently duplicate ownership of
    # a child surface's own gap).
    referenced_by = {}  # matrix case id -> set of ledger entry ids citing it
    for entry_id, entry in security.items():
        required_before_supported = entry["evidence"].get("required_before_supported") or []

        # Every individual bullet must carry its own stable recovery.* id -
        # not merely the joined text of the whole list. A prose-only bullet
        # sitting alongside another bullet that does cite a real id used to
        # pass (the aggregate text search would still find that other
        # bullet's id somewhere), which let untracked support-gate prose
        # accumulate silently; each bullet now stands on its own.
        referenced = set()
        for bullet in required_before_supported:
            bullet_ids = set(ID_RE.findall(bullet))
            assert bullet_ids, (
                f"{entry_id}: required_before_supported bullet has no stable recovery.* "
                f"case id: {bullet!r}"
            )
            referenced |= bullet_ids

        dead = sorted(referenced - seen_ids)
        assert not dead, f"{entry_id}: required_before_supported cites unknown recovery matrix id(s): {dead}"

        cross_surface = sorted(cid for cid in referenced if by_id[cid]["surface"] != entry_id)
        assert not cross_surface, (
            f"{entry_id}: required_before_supported cites recovery matrix id(s) owned by a "
            f"different surface: {cross_surface}"
        )

        passed_as_outstanding = sorted(cid for cid in referenced if by_id[cid]["status"] == "passed")
        assert not passed_as_outstanding, (
            f"{entry_id}: required_before_supported cites already-passed recovery matrix "
            f"id(s) as if still outstanding: {passed_as_outstanding}"
        )

        owned_outstanding = sorted(
            cid for cid, case in by_id.items()
            if case["surface"] == entry_id and case["status"] != "passed"
        )
        missing = [cid for cid in owned_outstanding if cid not in referenced]
        assert not missing, (
            f"{entry_id}: outstanding recovery matrix case(s) not referenced by id in "
            f"this entry's own required_before_supported: {missing}"
        )

        for cid in referenced:
            referenced_by.setdefault(cid, set()).add(entry_id)

    ambiguous = sorted(cid for cid, owners in referenced_by.items() if len(owners) > 1)
    assert not ambiguous, (
        f"recovery matrix id(s) referenced as outstanding by more than one ledger entry "
        f"(duplicate/ambiguous ownership): "
        f"{[(cid, sorted(referenced_by[cid])) for cid in ambiguous]}"
    )
