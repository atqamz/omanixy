#!/usr/bin/env bash
set -euo pipefail

repo=${1:?repository path required}
matrix=$repo/upstream/security-recovery-matrix.yaml
ledger=$repo/upstream/porting-matrix.yaml

python=${PYTHON:-python3}
"$python" - "$matrix" "$ledger" "$repo" <<'PY'
import os
import re
import sys
import yaml

matrix_path, ledger_path, repo = sys.argv[1:4]
matrix = yaml.safe_load(open(matrix_path, encoding="utf-8"))
ledger = yaml.safe_load(open(ledger_path, encoding="utf-8"))
items = matrix["items"]

security = {item["id"]: item for item in ledger["items"] if item["id"].startswith("security.")}
security_ids = set(security)

environments = {"hermetic", "nested-vm", "real-backend", "physical-hardware"}
statuses = {"passed", "unsupported-environment", "required-before-supported"}

seen_ids = set()
by_id = {}
for case in items:
    cid = case["id"]
    assert cid not in seen_ids, f"duplicate recovery matrix id: {cid}"
    seen_ids.add(cid)
    by_id[cid] = case

    assert case["surface"] in security_ids, f"{cid}: unknown surface {case['surface']!r}"
    assert case["environment"] in environments, f"{cid}: unknown environment {case['environment']!r}"
    assert case["status"] in statuses, f"{cid}: unknown status {case['status']!r}"
    assert case["expected_invariant"].strip(), f"{cid}: empty expected_invariant"
    # Section 20: a passed claim must reduce to a concrete, named check, not
    # free prose alone - required on every row, passed or not, so a
    # not-yet-passed row states what check would still need to exist.
    assert case.get("check", "").strip(), f"{cid}: missing or empty check field"

    if case["status"] == "passed":
        assert case["evidence"] != "none", f"{cid}: passed row must cite real evidence"
        evidence_path = case["evidence"].split(" (", 1)[0].strip()
        assert os.path.exists(os.path.join(repo, evidence_path)), (
            f"{cid}: evidence file {evidence_path!r} does not exist"
        )
        # Section 22: physical-hardware is no longer schema-banned from
        # passed - it simply has no evidence in this environment today, and
        # the two assertions above (real evidence path + real check) already
        # enforce that any future passed physical-hardware row would need
        # genuine evidence, exactly like every other environment.
        assert "attempted_evidence" not in case, f"{cid}: a passed row must not also carry attempted_evidence"
        assert "reason" not in case, f"{cid}: a passed row must not also carry a non-passed reason"
    else:
        assert case["evidence"] == "none", (
            f"{cid}: status={case['status']!r} rows must not cite evidence "
            "that was not actually produced"
        )
        # Section 23: a non-passed row may durably record that a real
        # attempt was made without ever claiming passed evidence.
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

# security.recovery itself must be represented in this matrix - it is the
# entry this whole file exists to back with evidence.
assert any(case["surface"] == "security.recovery" for case in items)

# Section 21: exact bidirectional mapping between the ledger's
# required_before_supported prose and this matrix, keyed on stable
# `recovery.<slug>` ids embedded in that prose - never a bare "some case
# exists for this surface" check, which a single generic case could satisfy
# for several unrelated bullets at once.
ID_RE = re.compile(r"\brecovery\.[a-z0-9][a-z0-9-]*\b")

for entry_id, entry in security.items():
    required_before_supported = entry["evidence"].get("required_before_supported") or []
    text = "\n".join(required_before_supported)
    referenced = set(ID_RE.findall(text))

    # No dead/stale reference: every id this entry's own prose cites must
    # actually exist in the matrix.
    dead = sorted(referenced - seen_ids)
    assert not dead, f"{entry_id}: required_before_supported cites unknown recovery matrix id(s): {dead}"

    # Every non-passed matrix case surfaced by this exact entry must be
    # cited, by its stable id, in that entry's own required_before_supported
    # prose - not merely somewhere in the ledger, and not satisfied by a
    # different entry's cross-reference to it.
    owned_outstanding = sorted(
        cid for cid, case in by_id.items()
        if case["surface"] == entry_id and case["status"] != "passed"
    )
    missing = [cid for cid in owned_outstanding if cid not in referenced]
    assert not missing, (
        f"{entry_id}: outstanding recovery matrix case(s) not referenced by id in "
        f"this entry's own required_before_supported: {missing}"
    )
PY

printf '%s\n' 'security recovery contract checks passed'
