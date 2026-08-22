#!/usr/bin/env bash
set -euo pipefail

scanner=${1:?executable surface scanner script required}
service_file=${2:?patched Service.qml required}
python_bin=${3:?python3 interpreter required}
scripts_dir=${4:?scripts directory (for source_discovery) required}

export PYTHONPATH="$scripts_dir"

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

assert_rejected_because() {
  local name=$1 needle=$2 content=$3
  local file="$fixture/$name.qml"
  printf '%s\n' "$content" >"$file"
  if "$python_bin" "$scanner" "$file" 2>"$fixture/$name.err"; then
    printf 'expected rejection for %s, scanner passed\n' "$name" >&2
    cat "$fixture/$name.err" >&2
    exit 1
  fi
  if ! grep -qF "$needle" "$fixture/$name.err"; then
    printf 'expected rejection reason %s for %s, got:\n' "$needle" "$name" >&2
    cat "$fixture/$name.err" >&2
    exit 1
  fi
}

assert_rejected unknown-tool '["mystery-security-tool", "--probe"]'
assert_rejected bash-dash-c '["bash", "-c", "$payload"]'

assert_rejected unknown-omarchy-helper '["omarchy-mystery-thing"]'
assert_rejected empty-array '[]'
assert_rejected dynamic-executable '[root.someExecutable, "-f"]'
assert_rejected timeout-dynamic-duration '["timeout", root.someDuration, "hyprctl", "dispatch", "x"]'
assert_rejected timeout-unknown-wrapped '["timeout", "3s", "curl", "https://example.com"]'
assert_rejected timeout-no-wrapped '["timeout", "3s"]'
assert_rejected bash-dash-c-reordered '["timeout", "3s", "bash", "-c", "$payload"]'


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

assert_rejected_raw dynamic-property-binding '
Process {
  command: root.runtimeCommand
}'

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

assert_rejected_raw comment-only-fake-command-plus-real-unknown '
Process {
  // command: ["readlink", "-f", "/etc/hostname"]
  command: [
    "mystery-security-tool",
    "--probe"
  ]
}'

assert_rejected_raw block-comment-fake-command-plus-real-unknown '
Process {
  /* command: ["readlink", "-f", "/etc/hostname"] */
  command: [
    "mystery-security-tool",
    "--probe"
  ]
}'

assert_rejected_raw procedural-command-assignment-unknown '
Process {
  id: lockProc
}
Component.onCompleted: {
  lockProc.command = ["mystery-security-tool"]
}'

assert_allowed_raw procedural-command-assignment-allowed '
Process {
  id: lockProc
}
Component.onCompleted: {
  lockProc.command = ["readlink", "-f", root.currentBackgroundLink]
}'

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

assert_allowed_raw dynamic-argument-embedded-brackets-allowed '
Process {
  command: [
    "readlink",
    root.buildArg("x)"),
    "-f"
  ]
}'


assert_rejected_because fake-single-quoted-only \
  'no command bindings of any shape found' \
  'property string fake: '"'"'command: ["readlink", "-f", "/tmp/not-a-real-command"]'"'"''

assert_rejected_because fake-double-quoted-escaped-only \
  'no command bindings of any shape found' \
  'property string fake: "command: [\"mystery-security-tool\"]"'

assert_rejected_because fake-string-plus-real-multiline-unknown \
  'mystery-security-tool' \
  'property string fake: '"'"'command: ["readlink"]'"'"'
Process {
  command: [
    "mystery-security-tool",
    "--probe"
  ]
}'

assert_rejected_because escaped-quote-then-line-comment-then-real-unknown \
  'mystery-security-tool' \
  'property string fake: "a\" // command: [\"mystery-security-tool\"]"
command: ["mystery-security-tool"]'

assert_rejected_because escaped-quote-then-block-comment-then-real-unknown \
  'mystery-security-tool' \
  'property string fake: "a\" /* command: [\"mystery-security-tool\"] */"
command: ["mystery-security-tool"]'

assert_rejected_because line-comment-only-fake-command \
  'no command bindings of any shape found' \
  '// command: ["readlink", "-f", "/tmp/not-a-real-command"]'

assert_rejected_because block-comment-only-fake-command \
  'no command bindings of any shape found' \
  '/* command: ["readlink", "-f", "/tmp/not-a-real-command"] */'


assert_allowed_raw allowed-command-with-unrelated-strings-and-comments '
// just a comment, nothing to see: command: ["mystery-security-tool"]
property string note: "unrelated string with command: [\"mystery-security-tool\"] inside it"
Process {
  command: ["readlink", "-f", root.currentBackgroundLink]
}'

assert_rejected_because real-dynamic-binding-with-allowed-looking-fake \
  'dynamic command: binding' \
  'property string fake: '"'"'command: ["readlink", "-f", "/tmp/x"]'"'"'
Process {
  command: root.runtimeCommand
}'

assert_rejected_because real-procedural-unknown-with-allowed-looking-fake \
  'mystery-security-tool' \
  'property string fake: '"'"'lockProc.command = ["readlink", "-f", "/tmp/x"]'"'"'
Process {
  id: lockProc
}
Component.onCompleted: {
  lockProc.command = ["mystery-security-tool"]
}'

assert_rejected_because unterminated-backtick-template-literal \
  'unsafe source' \
  'property string fake: `unterminated
command: ["mystery-security-tool"]'

assert_rejected_because unterminated-template-interpolation \
  'unsafe source' \
  'property string fake: `prefix ${ still open
command: ["mystery-security-tool"]'

assert_rejected_because unterminated-block-comment-inside-template-interpolation \
  'unsafe source' \
  'property string fake: `${
  /* never closes
  lockProc.command = ["mystery-security-tool"]
}`'


assert_rejected_because plain-template-literal-rejected \
  'template literals are unsupported' \
  'property string x: `hello`'

assert_rejected_because static-only-template-literal-rejected \
  'template literals are unsupported' \
  'property string x: `static text`'

assert_rejected_because template-with-allowed-looking-command-string-rejected \
  'template literals are unsupported' \
  'property string fake: `
command: ["readlink"]
`'

assert_rejected_because template-with-ordinary-interpolation-rejected \
  'template literals are unsupported' \
  'property string x: `hello ${name}`'

assert_rejected_because nested-template-interpolation-rejected \
  'template literals are unsupported' \
  'property string x: `outer ${ `inner ${value}` }`'

assert_rejected_because regex-literal-brace-bypass-rejected \
  'template literals are unsupported' \
  'property string fake: `prefix ${
  /}/.test(value)
    ? (lockProc.command = ["mystery-security-tool"])
    : null
} suffix`'

assert_rejected_because regex-literal-character-class-bypass-rejected \
  'template literals are unsupported' \
  'property string fake: `prefix ${
  /[}\/]/.test(value)
    ? (lockProc.command = ["mystery-security-tool"])
    : null
} suffix`'

assert_rejected_because template-alongside-real-unknown-command-rejected \
  'template literals are unsupported' \
  'property string fake: `// command: ["readlink"]
/* command: ["readlink"] */`
command: ["mystery-security-tool"]'

assert_allowed_raw backtick-inside-double-quoted-string-still-passes '
property string x: "literal ` character"
Process {
  command: ["readlink", "-f", root.currentBackgroundLink]
}'

assert_allowed_raw backtick-inside-single-quoted-string-still-passes '
property string x: '"'"'literal ` character'"'"'
Process {
  command: ["readlink", "-f", root.currentBackgroundLink]
}'

assert_allowed_raw backtick-inside-line-comment-still-passes '
// literal ` character in a line comment
Process {
  command: ["readlink", "-f", root.currentBackgroundLink]
}'

assert_allowed_raw backtick-inside-block-comment-still-passes '
/* literal ` character in a block comment */
Process {
  command: ["readlink", "-f", root.currentBackgroundLink]
}'

allowed=$fixture/allowed.qml
{
  printf '  Process {\n    command: ["readlink", "-f", root.currentBackgroundLink]\n  }\n'
  printf '  Process {\n    command: ["omarchy-hyprland-session-locked"]\n  }\n'
  printf '  Process {\n    command: ["timeout", "--kill-after=1s", "3s", "hyprctl", "dispatch", "hl.dsp.dpms({ action = \\"enable\\" })"]\n  }\n'
} >"$allowed"
"$python_bin" "$scanner" "$allowed"

printf '%s\n' 'lock executable surface adversarial checks passed'
