#!/usr/bin/env bash
set -euo pipefail

repo=${1:?repository path required}
matrix=$repo/upstream/security-recovery-matrix.yaml
ledger=$repo/upstream/porting-matrix.yaml
check_helpers=$repo/test/lib/recovery-check-helpers.py
contract_helpers=$repo/test/lib/recovery-contract-helpers.py

python=${PYTHON:-python3}
"$python" - "$matrix" "$ledger" "$repo" "$check_helpers" "$contract_helpers" <<'PY'
import os
import sys
import yaml

matrix_path, ledger_path, repo, check_helpers_path, contract_helpers_path = sys.argv[1:6]
matrix = yaml.safe_load(open(matrix_path, encoding="utf-8"))
ledger = yaml.safe_load(open(ledger_path, encoding="utf-8"))

check_ns = {}
with open(check_helpers_path, encoding="utf-8") as f:
    exec(compile(f.read(), check_helpers_path, "exec"), check_ns)
recovery_checks = check_ns["RECOVERY_CHECKS"]

contract_ns = {}
with open(contract_helpers_path, encoding="utf-8") as f:
    exec(compile(f.read(), contract_helpers_path, "exec"), contract_ns)
validate = contract_ns["validate"]


def repo_path_exists(path):
    return os.path.exists(os.path.join(repo, path))


validate(matrix, ledger, repo_path_exists, recovery_checks)
PY

printf '%s\n' 'security recovery contract checks passed'
