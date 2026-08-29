#!/usr/bin/env bash
set -euo pipefail

repo_root=${1:?repository root required}
justfile=${2:?justfile path required}

python3 - "$repo_root" <<'PY'
import sys

helpers_path = f"{sys.argv[1]}/test/lib/recovery-check-helpers.py"
helpers = {}
with open(helpers_path, encoding="utf-8") as file:
    exec(compile(file.read(), helpers_path, "exec"), helpers)
assert_measurements = helpers["assert_measurements"]

assert_measurements(
    """MEASURE burst-history-bounded history_count=10 popup_count=0
MEASURE same-harness-reprompt exit=0 prompt=yes sequence=isRegisteredChanged true;isActiveChanged true;authenticationRequestStarted;isResponseRequiredChanged true prompt=;authenticationRequestStarted;isResponseRequiredChanged true prompt=;isResponseRequiredChanged false prompt=Password: ;isActiveChanged false;authenticationSucceeded
""",
    {
        "burst-history-bounded": [{"history_count": "10", "popup_count": "0"}],
        "same-harness-reprompt": [{
            "exit": "0",
            "prompt": "yes",
            "sequence": "isRegisteredChanged true;isActiveChanged true;authenticationRequestStarted;isResponseRequiredChanged true prompt=;authenticationRequestStarted;isResponseRequiredChanged true prompt=;isResponseRequiredChanged false prompt=Password: ;isActiveChanged false;authenticationSucceeded",
        }],
    },
)
PY

check_command=$(just --justfile "$justfile" --dry-run check 2>&1 | python3 -c 'import sys; print(next(sys.stdin).rstrip())')
[ "$check_command" = 'nix --option max-jobs 1 flake check --show-trace --print-build-logs' ]

printf '%s\n' 'security recovery measurement output contract checks passed'
