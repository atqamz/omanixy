#!/usr/bin/env bash
set -euo pipefail

repo=${1:?repository path required}

if rg -n 'does not yet implement the runtime API|selecting and testing the concrete pair|architecture contract precedes the implementation issues|will expose|later runtime work may provide' \
  "$repo/README.md" "$repo/docs" "$repo/AGENTS.md"; then
  exit 1
fi
${PYTHON:-python3} - "$repo/upstream/omarchy.yaml" <<'PY'
import sys
import yaml

data = yaml.safe_load(open(sys.argv[1], encoding="utf-8"))
assert data["policy"]["runtime_pair"]["status"] == "validated"
assert data["track"] == "quattro"
PY
test -s "$repo/LICENSE"

printf '%s\n' 'stale text checks passed'
