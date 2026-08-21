#!/usr/bin/env bash
set -euo pipefail

repo=${1:?repository path required}
acceptance=$repo/upstream/issue-4-acceptance.yaml
matrix=$repo/upstream/security-recovery-matrix.yaml
flake=$repo/flake.nix

python=${PYTHON:-python3}
"$python" - "$acceptance" "$matrix" "$flake" "$repo" <<'PY'
import os
import sys
import yaml

acceptance_path, matrix_path, flake_path, repo = sys.argv[1:5]
acceptance = yaml.safe_load(open(acceptance_path, encoding="utf-8"))
matrix = yaml.safe_load(open(matrix_path, encoding="utf-8"))
flake_text = open(flake_path, encoding="utf-8").read()

matrix_by_id = {case["id"]: case for case in matrix["items"]}
statuses = {"satisfied", "experimental-boundary"}

seen_ids = set()
for item in acceptance["items"]:
    iid = item["id"]
    assert iid not in seen_ids, f"duplicate acceptance id: {iid}"
    seen_ids.add(iid)
    assert item["description"].strip(), f"{iid}: empty description"
    assert item["status"] in statuses, f"{iid}: unknown status {item['status']!r}"

    if item["status"] == "satisfied":
        tests = item.get("tests")
        assert tests, f"{iid}: status=satisfied requires at least one test/evidence path"
        assert "matrix_case" not in item, f"{iid}: satisfied rows must not also cite a matrix_case boundary"
        for path in tests:
            full = os.path.join(repo, path)
            assert os.path.exists(full), f"{iid}: evidence path {path!r} does not exist"
            # Every cited test file (other than the justfile itself, which
            # is the top-level gate rather than a check target) must
            # actually be wired into the flake's own check set - never a
            # file that merely exists but nothing ever runs.
            if path not in ("justfile",):
                basename = os.path.basename(path)
                assert basename in flake_text, (
                    f"{iid}: evidence file {path!r} is not referenced anywhere in flake.nix - "
                    "a checked-looking state must not imply a test that nothing ever runs"
                )
    else:
        assert "tests" not in item, f"{iid}: experimental-boundary rows must not also claim satisfied test evidence"
        case_id = item.get("matrix_case")
        assert case_id, f"{iid}: status=experimental-boundary requires a matrix_case reference"
        case = matrix_by_id.get(case_id)
        assert case is not None, f"{iid}: matrix_case {case_id!r} does not exist in the recovery matrix"
        assert case["status"] != "passed", (
            f"{iid}: matrix_case {case_id!r} is status=passed - an experimental-boundary acceptance row "
            "must never point at a case that was actually proven; that combination would imply a test "
            "happened for a criterion this file claims is still a boundary"
        )

required_ids = {
    "no-imperative-pam-mutation",
    "declarative-required-pam",
    "lock-polkit-independent",
    "native-lock-experimental-default-false",
    "consumer-external-lock-path-valid",
    "no-fingerprint-system-works",
    "fingerprint-optional-bounded",
    "no-competing-polkit-owner-enabled",
    "no-competing-idle-owner-enabled",
    "no-competing-notification-daemon-enabled",
    "suspend-resume-monitor-dpms-status",
    "crash-restart-while-locked-status",
    "no-broad-sudo-setuid",
    "third-party-qml-trust-documented",
    "explicit-compatibility-matrix",
    "required-final-validation-gates",
}
missing = sorted(required_ids - seen_ids)
assert not missing, f"missing required issue #4 acceptance criteria: {missing}"
PY

printf '%s\n' 'issue #4 acceptance mapping checks passed'
