#!/usr/bin/env bash
set -euo pipefail

repo=${1:?repository path required}
flake=$repo/flake.nix
metadata=$repo/upstream/omarchy.yaml
matrix=$repo/upstream/porting-matrix.yaml
lockfile=$repo/flake.lock

omarchy_revision=f0020448ca87329199de7cb12f2015ebc4a3e5e7
quickshell_revision=28771c7c74b42e20afca0b1b63980cb46515537c
nixpkgs_revision=241313f4e8e508cb9b13278c2b0fa25b9ca27163

grep -Fq "github:basecamp/omarchy/$omarchy_revision" "$flake"
grep -Fq "github:quickshell-mirror/quickshell/$quickshell_revision" "$flake"
grep -Fq "nixpkgsRevision = \"$nixpkgs_revision\"" "$flake"
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
