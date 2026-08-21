#!/usr/bin/env bash
set -euo pipefail

repo=${1:?repository path required}
matrix=$repo/upstream/security-recovery-matrix.yaml
ledger=$repo/upstream/porting-matrix.yaml

python=${PYTHON:-python3}
"$python" - "$matrix" "$ledger" "$repo" <<'PY'
import os
import sys
import yaml

matrix_path, ledger_path, repo = sys.argv[1:4]
matrix = yaml.safe_load(open(matrix_path, encoding="utf-8"))
ledger = yaml.safe_load(open(ledger_path, encoding="utf-8"))
items = matrix["items"]

security_ids = {item["id"] for item in ledger["items"] if item["id"].startswith("security.")}

environments = {"hermetic", "nested-vm", "real-backend", "physical-hardware"}
statuses = {"passed", "unsupported-environment", "required-before-supported"}

seen_ids = set()
for case in items:
    assert case["id"] not in seen_ids, f"duplicate recovery matrix id: {case['id']}"
    seen_ids.add(case["id"])

    assert case["surface"] in security_ids, f"{case['id']}: unknown surface {case['surface']!r}"
    assert case["environment"] in environments, f"{case['id']}: unknown environment {case['environment']!r}"
    assert case["status"] in statuses, f"{case['id']}: unknown status {case['status']!r}"
    assert case["expected_invariant"].strip(), f"{case['id']}: empty expected_invariant"

    if case["status"] == "passed":
        assert case["evidence"] != "none", f"{case['id']}: passed row must cite real evidence"
        evidence_path = case["evidence"].split(" (", 1)[0].strip()
        assert os.path.exists(os.path.join(repo, evidence_path)), (
            f"{case['id']}: evidence file {evidence_path!r} does not exist"
        )
        # Section 60: hardware/environment breadth that is genuinely
        # unavailable must never be mislabeled passed.
        assert case["environment"] != "physical-hardware", (
            f"{case['id']}: a physical-hardware case can never be status=passed"
        )
    else:
        assert case["evidence"] == "none", (
            f"{case['id']}: status={case['status']!r} rows must not cite evidence "
            "that was not actually produced"
        )

# security.recovery itself must be represented in this matrix - it is the
# entry this whole file exists to back with evidence.
assert any(case["surface"] == "security.recovery" for case in items)

# Every promoted-at-layer-8 ledger entry that still carries
# required_before_supported evidence must have at least one matching
# matrix case, so the ledger's prose can never silently drift from what
# this file actually records.
security = [item for item in ledger["items"] if item["id"] in security_ids]
for entry in security:
    required_before_supported = entry["evidence"].get("required_before_supported")
    if not required_before_supported:
        continue
    matching = [case for case in items if case["surface"] == entry["id"]]
    assert matching, f"{entry['id']}: has required_before_supported but no recovery matrix case"
PY

printf '%s\n' 'security recovery contract checks passed'
