#!/usr/bin/env bash
set -euo pipefail

repo=${1:?repository path required}
flake=$repo/flake.nix
metadata=$repo/upstream/omarchy.yaml

omarchy_revision=f0020448ca87329199de7cb12f2015ebc4a3e5e7
quickshell_revision=28771c7c74b42e20afca0b1b63980cb46515537c

grep -Fq "github:basecamp/omarchy/$omarchy_revision" "$flake"
grep -Fq "github:quickshell-mirror/quickshell/$quickshell_revision" "$flake"
grep -Fq "source: github:basecamp/omarchy/$omarchy_revision" "$metadata"
grep -Fq "source: github:quickshell-mirror/quickshell/$quickshell_revision" "$metadata"
grep -Fq "revision: $omarchy_revision" "$metadata"
grep -Fq "revision: $quickshell_revision" "$metadata"
grep -Fq "validated_quattro_pair: true" "$metadata"
! rg -n 'github:basecamp/omarchy/(quattro|main|master)' "$flake"
! rg -n 'github:quickshell-mirror/quickshell/(master|main)' "$flake"
! rg -n 'pending-issue-2|validated_quattro_pair: false|runtime_pair: pending' "$metadata"
! find "$repo" -type f -name '*.qml' -print -quit | grep -q .

printf '%s\n' 'pin invariants passed'
