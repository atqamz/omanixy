#!/usr/bin/env bash
set -euo pipefail

scanner=${1:?executable surface scanner script required}
service_file=${2:?fingerprint-enabled patched Service.qml required}
python_bin=${3:?python3 interpreter required}
scripts_dir=${4:?scripts directory (for source_discovery) required}

export PYTHONPATH="$scripts_dir"

scan_output=$("$python_bin" "$scanner" --fingerprint enabled "$service_file" 2>&1)
printf '%s\n' "$scan_output" >&2
grep -q '5 command bindings passed' <<<"$scan_output"
grep -Fq 'omarchy-lock-fingerprint-ready (allowed-direct)' <<<"$scan_output"

disabled_err=$(mktemp)
trap 'rm -f "$disabled_err"' EXIT
if "$python_bin" "$scanner" --fingerprint disabled "$service_file" 2>"$disabled_err"; then
  printf '%s\n' 'the disabled executable-surface profile unexpectedly accepted the fingerprint-enabled source' >&2
  exit 1
fi
grep -Fq 'omarchy-lock-fingerprint-ready' "$disabled_err"

printf '%s\n' 'lock fingerprint executable surface checks passed'
