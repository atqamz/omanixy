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

# Like assert_rejected_raw, but also asserts the rejection reason contains
# a given substring - used where the failure mode itself matters (e.g. a
# fake-only fixture must fail as "no command bindings", not for some
# unrelated reason that would also happen to reject the file).
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

# Section 2-8: shared QML/JS lexical preprocessing must be string-safe -
# command-looking text or comment markers embedded inside a quoted string
# or template literal must never satisfy or spoof command discovery, and
# must never hide a real command binding that follows them. Each case
# below is one letter (A-L) of the directive's adversarial matrix.

# A: a single-quoted-only fake command binding is the only command-looking
# text in the file - the string's content must not be counted, so the
# scanner must fail as "no bindings", not silently pass.
assert_rejected_because fake-single-quoted-only \
  'no command bindings of any shape found' \
  'property string fake: '"'"'command: ["readlink", "-f", "/tmp/not-a-real-command"]'"'"''

# B: same, but double-quoted with escaped inner quotes.
assert_rejected_because fake-double-quoted-escaped-only \
  'no command bindings of any shape found' \
  'property string fake: "command: [\"mystery-security-tool\"]"'

# C: a fake quoted command string sits next to a REAL multiline unknown
# command - the fake must not mask the real one.
assert_rejected_because fake-string-plus-real-multiline-unknown \
  'mystery-security-tool' \
  'property string fake: '"'"'command: ["readlink"]'"'"'
Process {
  command: [
    "mystery-security-tool",
    "--probe"
  ]
}'

# D: an escaped quote inside a string must not incorrectly terminate the
# lexical quote state, letting a "//" inside the remaining (still-quoted)
# text hide the REAL unknown command that follows the string.
assert_rejected_because escaped-quote-then-line-comment-then-real-unknown \
  'mystery-security-tool' \
  'property string fake: "a\" // command: [\"mystery-security-tool\"]"
command: ["mystery-security-tool"]'

# E: same, with a "/* */" block-comment marker instead of "//".
assert_rejected_because escaped-quote-then-block-comment-then-real-unknown \
  'mystery-security-tool' \
  'property string fake: "a\" /* command: [\"mystery-security-tool\"] */"
command: ["mystery-security-tool"]'

# F: a line-comment-only fake command, with no real binding anywhere in
# the file, must not count - the scanner must fail as "no bindings".
assert_rejected_because line-comment-only-fake-command \
  'no command bindings of any shape found' \
  '// command: ["readlink", "-f", "/tmp/not-a-real-command"]'

# G: same, with a block comment instead of a line comment.
assert_rejected_because block-comment-only-fake-command \
  'no command bindings of any shape found' \
  '/* command: ["readlink", "-f", "/tmp/not-a-real-command"] */'

# H and I of the original matrix (a fake command inside a backtick template
# literal, with or without a real binding alongside it) are now covered by
# the "Template literal rejection test group" below: security.lock rejects
# any live backtick template literal outright, so those two shapes are
# folded into that group's cases C and H instead of living here.

# J: an allowed real command alongside unrelated strings/comments (that
# happen to contain command-looking text) must still pass.
assert_allowed_raw allowed-command-with-unrelated-strings-and-comments '
// just a comment, nothing to see: command: ["mystery-security-tool"]
property string note: "unrelated string with command: [\"mystery-security-tool\"] inside it"
Process {
  command: ["readlink", "-f", root.currentBackgroundLink]
}'

# K: a real dynamic (non-array) command binding must still be rejected as
# dynamic even when an allowed-looking quoted fake sits alongside it.
assert_rejected_because real-dynamic-binding-with-allowed-looking-fake \
  'dynamic command: binding' \
  'property string fake: '"'"'command: ["readlink", "-f", "/tmp/x"]'"'"'
Process {
  command: root.runtimeCommand
}'

# L: a real procedural ".command =" mutation to an unknown executable must
# still be rejected even when an allowed-looking quoted fake sits alongside
# it - the fake must not launder the real, unknown procedural binding.
assert_rejected_because real-procedural-unknown-with-allowed-looking-fake \
  'mystery-security-tool' \
  'property string fake: '"'"'lockProc.command = ["readlink", "-f", "/tmp/x"]'"'"'
Process {
  id: lockProc
}
Component.onCompleted: {
  lockProc.command = ["mystery-security-tool"]
}'

# Section 9: security.lock's executable-surface scanner treats live
# backtick/template literals as categorically unsupported, not as a shape
# it partially parses. QML/JS template literals admit full ECMAScript
# grammar - regex literals in particular make "}" -> interpolation-depth
# counting unprovable without a real parser (division vs. regexp-literal
# ambiguity, character classes, escaped slashes, flags) - so rather than
# grow the shared lexer to chase that, any live template literal makes the
# whole file's executable surface unverifiable and rejects it outright. The
# real, final Service.qml (scanned above) contains no template literals at
# all, so this is strictly stricter than general QML, not a parsing gap.
#
# Malformed backtick/interpolation constructs are still caught first by the
# pre-existing UnsafeSource fail-closed path (shared with every other
# source_discovery consumer) before the categorical rejection below even
# has a chance to run.
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

# Template literal rejection test group: security.lock rejects any live
# backtick/template literal outright, regardless of what it contains - a
# backtick that survives comment-stripping and string-masking is by
# construction a live template delimiter, never a shape that gets
# discovered-and-then-validated. Letters follow the security-policy matrix.

# A: the simplest possible template literal, no interpolation at all.
assert_rejected_because plain-template-literal-rejected \
  'template literals are unsupported' \
  'property string x: `hello`'

# B: static-text-only template - this is about the backtick construct
# itself, not about interpolation.
assert_rejected_because static-only-template-literal-rejected \
  'template literals are unsupported' \
  'property string x: `static text`'

# C: a template containing only an allowed-looking command string is not
# evidence the file is safe - it is rejected the same as any other
# template literal, without even reaching discovery.
assert_rejected_because template-with-allowed-looking-command-string-rejected \
  'template literals are unsupported' \
  'property string fake: `
command: ["readlink"]
`'

# D: ordinary "${...}" interpolation - still rejected categorically.
assert_rejected_because template-with-ordinary-interpolation-rejected \
  'template literals are unsupported' \
  'property string x: `hello ${name}`'

# E: nested template/interpolation - still rejected categorically.
assert_rejected_because nested-template-interpolation-rejected \
  'template literals are unsupported' \
  'property string x: `outer ${ `inner ${value}` }`'

# F: a "}" inside a "/.../ " regex literal is not lexed as a regex by the
# shared interpolation walker, so it could otherwise be miscounted as
# closing the interpolation early and exposing whatever real code follows
# it as live. The categorical rejection makes that regex blind spot
# irrelevant: the whole file is unverifiable the moment a live backtick is
# present, so this shape can never reach "mystery-security-tool" through
# discovery in the first place.
assert_rejected_because regex-literal-brace-bypass-rejected \
  'template literals are unsupported' \
  'property string fake: `prefix ${
  /}/.test(value)
    ? (lockProc.command = ["mystery-security-tool"])
    : null
} suffix`'

# G: a regex literal using a character class and an escaped slash - a
# different ECMAScript regex shape than F, same categorical rejection.
assert_rejected_because regex-literal-character-class-bypass-rejected \
  'template literals are unsupported' \
  'property string fake: `prefix ${
  /[}\/]/.test(value)
    ? (lockProc.command = ["mystery-security-tool"])
    : null
} suffix`'

# H: a template literal sitting alongside a real, unknown ".command ="
# mutation elsewhere in the file - the categorical rejection fires before
# discovery of the real binding ever runs, so a template literal can never
# be used to distract from or launder an unrelated dangerous binding.
assert_rejected_because template-alongside-real-unknown-command-rejected \
  'template literals are unsupported' \
  'property string fake: `// command: ["readlink"]
/* command: ["readlink"] */`
command: ["mystery-security-tool"]'

# I: a literal backtick character inside an ordinary double-quoted string is
# not a template delimiter - it is masked along with the rest of the
# string's content, so it must not trigger rejection.
assert_allowed_raw backtick-inside-double-quoted-string-still-passes '
property string x: "literal ` character"
Process {
  command: ["readlink", "-f", root.currentBackgroundLink]
}'

# J: same, single-quoted.
assert_allowed_raw backtick-inside-single-quoted-string-still-passes '
property string x: '"'"'literal ` character'"'"'
Process {
  command: ["readlink", "-f", root.currentBackgroundLink]
}'

# K: a literal backtick character inside a "//" comment is removed along
# with the rest of the comment before the categorical check ever runs.
assert_allowed_raw backtick-inside-line-comment-still-passes '
// literal ` character in a line comment
Process {
  command: ["readlink", "-f", root.currentBackgroundLink]
}'

# L: same, "/* */" block comment.
assert_allowed_raw backtick-inside-block-comment-still-passes '
/* literal ` character in a block comment */
Process {
  command: ["readlink", "-f", root.currentBackgroundLink]
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
