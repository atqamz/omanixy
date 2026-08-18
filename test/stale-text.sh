#!/usr/bin/env bash
set -euo pipefail

repo=${1:?repository path required}

${PYTHON:-python3} - "$repo/upstream/omarchy.yaml" <<'PY'
import sys
import yaml

data = yaml.safe_load(open(sys.argv[1], encoding="utf-8"))
assert data["policy"]["runtime_pair"]["status"] == "validated"
assert data["policy"]["runtime_pair"]["validation"]["wayland_hyprland_smoke"] is False
assert data["track"] == "quattro"
PY
jq -e '
  .schema >= 2
  and (.pins.omarchy | type) == "string"
  and (.pins.quickshell | type) == "string"
  and (.pins.nixpkgs | type) == "string"
  and (.helpers | type) == "object"
' "$repo/upstream/compatibility-contracts.json" >/dev/null
test -s "$repo/LICENSE"

printf '%s\n' 'stale text checks passed'
