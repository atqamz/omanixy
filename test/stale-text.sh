#!/usr/bin/env bash
set -euo pipefail

repo=${1:?repository path required}

! rg -n 'does not yet implement the runtime API|selecting and testing the concrete pair|architecture contract precedes the implementation issues|will expose|later runtime work may provide' \
  "$repo/README.md" "$repo/docs" "$repo/AGENTS.md"
grep -Fq 'programs.omanixy.enable = true;' "$repo/README.md"
grep -Fq 'Issue #2 provides the first validated Quattro runtime baseline.' "$repo/docs/architecture.md"
grep -Fq 'status: validated' "$repo/upstream/omarchy.yaml"
grep -Fq 'track: quattro' "$repo/upstream/omarchy.yaml"
test -s "$repo/LICENSE"

printf '%s\n' 'stale text checks passed'
