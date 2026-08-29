#!/usr/bin/env bash
set -euo pipefail

notifications_vm=${1:?notifications VM path required}
polkit_vm=${2:?polkit VM path required}
justfile=${3:?justfile path required}

grep -Fq 'echo "MEASURE burst-history-bounded history_count=$hist popup_count=$popup"' "$notifications_vm"
grep -Fq 'echo "MEASURE same-harness-reprompt exit=$p2exit prompt=$prompt_seen sequence=$sequence"' "$polkit_vm"
grep -Fq "grep 'HARNESS_EVENT' harness.log" "$polkit_vm"
grep -Fq "sed -E 's/^.*HARNESS_EVENT //'" "$polkit_vm"
grep -Fq 'nix --option max-jobs 1 flake check --show-trace --print-build-logs' "$justfile"

printf '%s\n' 'security recovery measurement output contract checks passed'
