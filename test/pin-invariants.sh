#!/usr/bin/env bash
set -euo pipefail

repo=${1:?repository path required}
supported_systems=${2:?evaluated supported systems JSON required}
metadata=$repo/upstream/omarchy.yaml
matrix=$repo/upstream/porting-matrix.yaml
lockfile=$repo/flake.lock
manifest=$repo/upstream/compatibility-contracts.json

omarchy_revision=$(jq -er '.pins.omarchy' "$manifest")
quickshell_revision=$(jq -er '.pins.quickshell' "$manifest")
nixpkgs_revision=$(jq -er '.pins.nixpkgs' "$manifest")

jq -e \
  --arg omarchy "$omarchy_revision" \
  --arg quickshell "$quickshell_revision" \
  --arg nixpkgs "$nixpkgs_revision" \
  '
    .nodes.omarchy.locked.rev == $omarchy
    and .nodes.omarchy.original.rev == $omarchy
    and .nodes.quickshell.locked.rev == $quickshell
    and .nodes.quickshell.original.rev == $quickshell
    and .nodes.nixpkgs.locked.rev == $nixpkgs
  ' "$lockfile" >/dev/null
${PYTHON:-python3} - "$metadata" "$omarchy_revision" "$quickshell_revision" "$nixpkgs_revision" "$matrix" <<'PY'
import sys
import yaml

metadata, omarchy, quickshell, nixpkgs, matrix = sys.argv[1:]
data = yaml.safe_load(open(metadata, encoding="utf-8"))
pair = data["policy"]["runtime_pair"]
assert data["track"] == "quattro"
assert data["revision"] == omarchy
assert data["policy"]["validated_quattro_pair"] is True
assert pair["omarchy"] == {"source": f"github:basecamp/omarchy/{omarchy}", "revision": omarchy}
assert pair["quickshell"]["source"] == f"github:quickshell-mirror/quickshell/{quickshell}"
assert pair["quickshell"]["revision"] == quickshell
assert pair["quickshell"]["nixpkgs"]["source"] == f"github:NixOS/nixpkgs/{nixpkgs}"
assert pair["quickshell"]["nixpkgs"]["revision"] == nixpkgs

matrix_data = yaml.safe_load(open(matrix, encoding="utf-8"))
paths = {
    path["path"]
    for item in matrix_data["items"]
    for path in item.get("upstream", {}).get("paths", [])
}
assert {"shell/shell.qml", "shell/plugins/", "config/omarchy/shell.json", "themes/tokyo-night/", "bin/omarchy-launch-shell"} <= paths
consumption = {
    path["consumption"]
    for item in matrix_data["items"]
    for path in item.get("upstream", {}).get("paths", [])
}
assert {"reference-only", "build-time"} <= consumption
PY
adapter_hash=$( {
  first=true
  while IFS= read -r source; do
    if [[ $first == false ]]; then printf '\n'; fi
    first=false
    cat "$repo/$source"
  done < <(jq -er '.adapterSources[]' "$manifest")
} | sha256sum | awk '{print $1}')
jq -e \
  --arg adapter 'packages/omanixy-shell/compat-adapter.bash' \
  --arg tests 'test/compat-adapters.sh' \
  --arg adapter_hash "$adapter_hash" \
  '.adapter == $adapter and .adapterHash == $adapter_hash and (.adapterSources | type) == "array" and .behavioralTests == $tests and (.helpers | type) == "object"' \
  "$manifest" >/dev/null
test "$(find "$repo" -type f -name '*.qml' -print -quit)" = ""
jq -e --argjson systems "$supported_systems" '$systems == ["x86_64-linux", "aarch64-linux"]' \
  <<< '{}'

printf '%s\n' 'pin invariants passed'
