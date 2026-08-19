#!/usr/bin/env bash
set -euo pipefail

scanner=${1:?executable surface scanner script required}
service_file=${2:?patched Service.qml required}
python_bin=${3:?python3 interpreter required}
scripts_dir=${4:?scripts directory (for source_discovery) required}

export PYTHONPATH="$scripts_dir"

# Finding 4: the real, FINAL patched Service.qml's Process.command
# executable surface passes the fail-closed scan.
"$python_bin" "$scanner" "$service_file"

fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT

assert_rejected_raw() {
  local name=$1 content=$2
  local file="$fixture/$name.qml"
  printf '%s\n' "$content" >"$file"
  if "$python_bin" "$scanner" "$file" 2>"$fixture/$name.err"; then
    printf 'expected rejection for %s, scanner passed\n' "$name" >&2
    cat "$fixture/$name.err" >&2
    exit 1
  fi
}

assert_allowed_raw() {
  local name=$1 content=$2
  local file="$fixture/$name.qml"
  printf '%s\n' "$content" >"$file"
  "$python_bin" "$scanner" "$file"
}

assert_rejected() {
  local name=$1 body=$2
  assert_rejected_raw "$name" "$(printf '  Process {\n    command: %s\n  }\n' "$body")"
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

# Section 8: the fail-closed scanner must also survive shapes that only a
# whole-source, multiline-aware, comment-immune parser can catch - a
# per-line single-array regex would silently pass every one of these.

assert_rejected_raw unknown-multiline-command '
Process {
  command: [
    "mystery-security-tool",
    "--probe"
  ]
}'

assert_allowed_raw allowed-multiline-command '
Process {
  command: [
    "readlink",
    "-f",
    root.currentBackgroundLink
  ]
}'

assert_rejected_raw multiline-bash-dash-c '
Process {
  command: [
    "bash",
    "-c",
    "rm -rf /"
  ]
}'

assert_rejected_raw multiline-dynamic-executable '
Process {
  command: [
    root.someExecutable,
    "-f"
  ]
}'

# Non-array declarative binding: the property is not "[...]" at all.
assert_rejected_raw dynamic-property-binding '
Process {
  command: root.runtimeCommand
}'

# Non-array declarative binding to a function/expression result.
assert_rejected_raw dynamic-function-binding '
Process {
  command: buildCommand()
}'

assert_rejected_raw unknown-omarchy-helper-multiline '
Process {
  command: [
    "omarchy-mystery-security-helper"
  ]
}'

assert_allowed_raw timeout-allowed-multiline '
Process {
  command: [
    "timeout",
    "--kill-after=1s",
    "3s",
    "hyprctl",
    "dispatch",
    "hl.dsp.dpms({ action = \"enable\" })"
  ]
}'

assert_rejected_raw timeout-unknown-wrapped-multiline '
Process {
  command: [
    "timeout",
    "3s",
    "curl",
    "https://evil.example"
  ]
}'

# A comment containing an allowed-looking command must not satisfy the
# audit, and must not mask a real unknown command elsewhere in the file.
assert_rejected_raw comment-only-fake-command-plus-real-unknown '
Process {
  // command: ["readlink", "-f", "/etc/hostname"]
  command: [
    "mystery-security-tool",
    "--probe"
  ]
}'

# A block comment wrapping an allowed-looking command must not satisfy the
# audit either, with a real unknown command alongside it.
assert_rejected_raw block-comment-fake-command-plus-real-unknown '
Process {
  /* command: ["readlink", "-f", "/etc/hostname"] */
  command: [
    "mystery-security-tool",
    "--probe"
  ]
}'

# Procedural `.command =` mutation of an already-declared Process is not
# used anywhere in the current lock plugin (verified against the real
# generated Service.qml above), but the scanner must not let a future
# regression introduce one silently - it goes through the exact same
# array-binding validation as a declarative `command:` property.
assert_rejected_raw procedural-command-assignment-unknown '
Process {
  id: lockProc
}
Component.onCompleted: {
  lockProc.command = ["mystery-security-tool"]
}'

# A procedural assignment to an allowed executable must still pass, proving
# the procedural path is validated by the same allowlist, not rejected
# outright just for being an assignment.
assert_allowed_raw procedural-command-assignment-allowed '
Process {
  id: lockProc
}
Component.onCompleted: {
  lockProc.command = ["readlink", "-f", root.currentBackgroundLink]
}'

# A dynamic trailing argument containing a string literal with an unbalanced
# "(" / ")" inside it must not desync the tokenizer's bracket-depth tracking
# and hide a real bash -c pair inside the resulting merged token.
assert_rejected_raw dynamic-argument-embedded-brackets-does-not-hide-bash-c '
Process {
  command: [
    "readlink",
    root.buildArg("x)"),
    "bash",
    "-c",
    root.payload
  ]
}'

# The same embedded-bracket shape must still be recognized as three separate
# trailing tokens (not corrupt token boundaries) when nothing dangerous
# follows it, so an allowed executable with such an argument still passes.
assert_allowed_raw dynamic-argument-embedded-brackets-allowed '
Process {
  command: [
    "readlink",
    root.buildArg("x)"),
    "-f"
  ]
}'

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
