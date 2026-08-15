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
jq -e \
  --arg adapter 'packages/omanixy-shell/compat-adapter.bash' \
  --arg tests 'test/compat-adapters.sh' \
  --arg adapter_hash "$(sha256sum "$repo/packages/omanixy-shell/compat-adapter.bash" | awk '{print $1}')" \
  '.adapter == $adapter and .adapterHash == $adapter_hash and .behavioralTests == $tests and (.helpers | type) == "object"' \
  "$manifest" >/dev/null
grep -Fq "validated_quattro_pair: true" "$metadata"
grep -Fq 'track: quattro' "$metadata"
! grep -Fq 'release:' "$metadata"
grep -Fq 'assertOneOf "omanixy supported system"' "$flake"
grep -Fq 'path: shell/shell.qml' "$matrix"
grep -Fqx '        - path: shell/plugins/' "$matrix"
grep -Fq 'path: config/omarchy/shell.json' "$matrix"
grep -Fq 'path: themes/tokyo-night/' "$matrix"
grep -Fq 'path: bin/omarchy-launch-shell' "$matrix"
grep -Fq 'consumption: reference-only' "$matrix"
grep -Fq 'consumption: build-time' "$matrix"
! rg -n 'github:basecamp/omarchy/(quattro|main|master)' "$flake"
! rg -n 'github:quickshell-mirror/quickshell/(master|main)' "$flake"
! rg -n 'pending-issue-2|validated_quattro_pair: false|runtime_pair: pending' "$metadata"
! find "$repo" -type f -name '*.qml' -print -quit | grep -q .

printf '%s\n' 'pin invariants passed'
