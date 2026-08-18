#!/usr/bin/env bash
set -euo pipefail

scanner=${1:?executable surface scanner script required}
service_file=${2:?patched Service.qml required}
python_bin=${3:?python3 interpreter required}

# Finding 4: the real, FINAL patched Service.qml's Process.command
# executable surface passes the fail-closed scan.
"$python_bin" "$scanner" "$service_file"

fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT

assert_rejected() {
  local name=$1 body=$2
  local file="$fixture/$name.qml"
  printf '  Process {\n    command: %s\n  }\n' "$body" >"$file"
  if "$python_bin" "$scanner" "$file" 2>"$fixture/$name.err"; then
    printf 'expected rejection for %s, scanner passed\n' "$name" >&2
    cat "$fixture/$name.err" >&2
    exit 1
  fi
}

# The directive's own named adversarial examples.
assert_rejected unknown-tool '["mystery-security-tool", "--probe"]'
assert_rejected bash-dash-c '["bash", "-c", "$payload"]'

# Additional adversarial shapes the scanner must also catch.
assert_rejected unknown-omarchy-helper '["omarchy-mystery-thing"]'
assert_rejected empty-array '[]'
assert_rejected dynamic-executable '[root.someExecutable, "-f"]'
assert_rejected timeout-dynamic-duration '["timeout", root.someDuration, "hyprctl", "dispatch", "x"]'
assert_rejected timeout-unknown-wrapped '["timeout", "3s", "curl", "https://example.com"]'
assert_rejected timeout-no-wrapped '["timeout", "3s"]'
assert_rejected bash-dash-c-reordered '["timeout", "3s", "bash", "-c", "$payload"]'

# Allowed shapes must still pass, proving the scanner is not simply
# rejecting everything.
allowed=$fixture/allowed.qml
{
  printf '  Process {\n    command: ["readlink", "-f", root.currentBackgroundLink]\n  }\n'
  printf '  Process {\n    command: ["omarchy-hyprland-session-locked"]\n  }\n'
  printf '  Process {\n    command: ["timeout", "--kill-after=1s", "3s", "hyprctl", "dispatch", "hl.dsp.dpms({ action = \\"enable\\" })"]\n  }\n'
} >"$allowed"
"$python_bin" "$scanner" "$allowed"

printf '%s\n' 'lock executable surface adversarial checks passed'
