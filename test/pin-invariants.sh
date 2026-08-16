#!/usr/bin/env bash
set -euo pipefail

repo=${1:?repository path required}
flake=$repo/flake.nix
metadata=$repo/upstream/omarchy.yaml
matrix=$repo/upstream/porting-matrix.yaml
lockfile=$repo/flake.lock
manifest=$repo/upstream/compatibility-contracts.json

omarchy_revision=$(jq -er '.pins.omarchy' "$manifest")
quickshell_revision=$(jq -er '.pins.quickshell' "$manifest")
nixpkgs_revision=$(jq -er '.pins.nixpkgs' "$manifest")

grep -Fq "github:basecamp/omarchy/$omarchy_revision" "$flake"
grep -Fq "github:quickshell-mirror/quickshell/$quickshell_revision" "$flake"
grep -Fq 'nixpkgsRevision = contractSource.pins.nixpkgs' "$flake"
grep -Fq "source: github:basecamp/omarchy/$omarchy_revision" "$metadata"
grep -Fq "source: github:quickshell-mirror/quickshell/$quickshell_revision" "$metadata"
grep -Fq "source: github:NixOS/nixpkgs/$nixpkgs_revision" "$metadata"
grep -Fq "revision: $omarchy_revision" "$metadata"
grep -Fq "revision: $quickshell_revision" "$metadata"
grep -Fq "revision: $nixpkgs_revision" "$metadata"
grep -Fq "\"rev\": \"$nixpkgs_revision\"" "$lockfile"
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
grep -Fq "validated_quattro_pair: true" "$metadata"
grep -Fq 'track: quattro' "$metadata"
grep -Fq 'release:' "$metadata" && exit 1
grep -Fq 'assertOneOf "omanixy supported system"' "$flake"
grep -Fq 'path: shell/shell.qml' "$matrix"
grep -Fqx '        - path: shell/plugins/' "$matrix"
grep -Fq 'path: config/omarchy/shell.json' "$matrix"
grep -Fq 'path: themes/tokyo-night/' "$matrix"
grep -Fq 'path: bin/omarchy-launch-shell' "$matrix"
grep -Fq 'consumption: reference-only' "$matrix"
grep -Fq 'consumption: build-time' "$matrix"
rg -n 'github:basecamp/omarchy/(quattro|main|master)' "$flake" && exit 1
rg -n 'github:quickshell-mirror/quickshell/(master|main)' "$flake" && exit 1
rg -n 'pending-issue-2|validated_quattro_pair: false|runtime_pair: pending' "$metadata" && exit 1
find "$repo" -type f -name '*.qml' -print -quit | grep -q . && exit 1

printf '%s\n' 'pin invariants passed'
