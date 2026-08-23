#!/usr/bin/env bash
set -euo pipefail

scanner=${1:?executable surface scanner script required}
service_file=${2:?patched idle Service.qml required}
python_bin=${3:?python3 interpreter required}
scripts_dir=${4:?scripts directory (for source_discovery) required}

export PYTHONPATH="$scripts_dir"

fixture=$(mktemp -d)
trap 'chmod -R u+w "$fixture"; rm -rf "$fixture"' EXIT

# The real, final Service.qml has exactly the four allowed exact-argv
# command bindings and zero exec/execDetached/run/startDetached calls.
scan_output=$("$python_bin" "$scanner" "$service_file" 2>&1)
printf '%s\n' "$scan_output" >&2
grep -Fq '4 command binding(s) passed, 0 exec/execDetached/run/startDetached calls found' <<<"$scan_output"

assert_rejected_raw() {
  local name=$1 content=$2
  printf '%s' "$content" >"$fixture/$name.qml"
  if "$python_bin" "$scanner" "$fixture/$name.qml" >"$fixture/$name.out" 2>&1; then
    printf 'expected rejection for %s, but scanner accepted it:\n' "$name" >&2
    cat "$fixture/$name.out" >&2
    exit 1
  fi
}

assert_rejected_because() {
  local name=$1 needle=$2 content=$3
  assert_rejected_raw "$name" "$content"
  grep -qF "$needle" "$fixture/$name.out"
}

assert_accepted_raw() {
  local name=$1 content=$2
  printf '%s' "$content" >"$fixture/$name.qml"
  if ! "$python_bin" "$scanner" "$fixture/$name.qml" >"$fixture/$name.out" 2>&1; then
    printf 'expected acceptance for %s, but scanner rejected it:\n' "$name" >&2
    cat "$fixture/$name.out" >&2
    exit 1
  fi
}

# The three allowed exact-argv forms, individually and multiline.
assert_accepted_raw "allowed-lock" 'Item { Process { command: ["omanixy-shell", "lock", "lock"] } }'
assert_accepted_raw "allowed-probe" 'Item { Process { command: ["omanixy-idle-state", "probe"] } }'
assert_accepted_raw "allowed-set-awake" 'Item { Process { command: ["omanixy-idle-state", "set", "awake"] } }'
assert_accepted_raw "allowed-set-idle" 'Item { Process { command: ["omanixy-idle-state", "set", "idle"] } }'
assert_accepted_raw "allowed-multiline" 'Item { Process { command: [
  "omanixy-shell",
  "lock",
  "lock"
] } }'

assert_rejected_because "unknown-helper" "not one of the allowed exact argv forms" \
  'Item { Process { command: ["omanixy-mystery-helper"] } }'
assert_rejected_because "unknown-executable" "not one of the allowed exact argv forms" \
  'Item { Process { command: ["mystery-tool"] } }'
assert_rejected_because "bash-c" "shell interpreter reachable" \
  'Item { Process { command: ["bash", "-c", "echo hi"] } }'
assert_rejected_because "bash-lc" "shell interpreter reachable" \
  'Item { Process { command: ["bash", "-lc", "echo hi"] } }'
assert_rejected_because "dynamic-command" "dynamic command: binding" \
  'Item { Process { command: dynamicExpression } }'
assert_rejected_because "procedural-command" "not one of the allowed exact argv forms" \
  'Item { function go() { proc.command = ["mystery-tool"] } }'
assert_rejected_because "process-exec" "exec/execDetached call found" \
  'Item { Process { id: p; Component.onCompleted: p.exec(["omanixy-shell", "lock", "lock"]) } }'
assert_rejected_because "bare-exec" "exec/execDetached call found" \
  'Item { Process { Component.onCompleted: exec(["omanixy-shell", "lock", "lock"]) } }'
assert_rejected_because "quickshell-exec" "exec/execDetached call found" \
  'Item { function go() { Quickshell.exec(["omanixy-shell", "lock", "lock"]) } }'
assert_rejected_because "quickshell-execdetached" "exec/execDetached call found" \
  'Item { function go() { Quickshell.execDetached(["omanixy-shell", "lock", "lock"]) } }'
assert_rejected_because "dot-run" "run call found" \
  'Item { function go() { runner.run(["omanixy-shell", "lock", "lock"]) } }'
assert_rejected_because "multiline-bad" "shell interpreter reachable" \
  'Item { Process { command: [
  "bash",
  "-c",
  "echo hi"
] } }'
# shellcheck disable=SC2016
assert_rejected_because "template-literal" "template literals are unsupported" \
  'Item { property string note: `no process here` }'

# Comment/string false-positive safety: Process/command/exec/run-looking
# text sitting inertly in a comment or string must not itself trip the
# scanner, and a real unknown command after such fake text must still be
# caught.
assert_accepted_raw "comment-fake" 'Item {
  // Process { command: ["mystery-tool"] } exec(["x"]) runner.run(["y"])
  Process { command: ["omanixy-shell", "lock", "lock"] }
}'
assert_accepted_raw "string-fake" 'Item {
  property string note: "Process { command: [\"mystery-tool\"] } exec([\"x\"])"
  Process { command: ["omanixy-idle-state", "probe"] }
}'
assert_rejected_because "fake-comment-then-real-bad" "not one of the allowed exact argv forms" 'Item {
  // command: ["fake-not-real"]
  Process { command: ["mystery-tool"] }
}'
# The array argument here is itself an allowlisted-looking argv - proving
# that reaching a command through exec(...) is rejected even when the
# array it names would otherwise be an allowed direct binding, not merely
# when the array is also independently invalid.
assert_rejected_because "fake-string-then-real-exec" "exec/execDetached call found" 'Item {
  property string note: "exec([\"fake\"])"
  function go() { Quickshell.exec(["omanixy-shell", "lock", "lock"]) }
}'

# startDetached() bypass matrix (Section 11/12): Process.startDetached()
# launches the process's already-set command completely untracked - even
# an otherwise-allowlisted argv reaching it is a real bypass, since a
# tracked, bounded invocation would silently become an untracked one.
assert_rejected_because "startdetached-allowed-lock-argv" "startDetached call found" 'Item {
  Process { id: p; command: ["omanixy-shell", "lock", "lock"]; Component.onCompleted: p.startDetached() }
}'
assert_rejected_because "startdetached-allowed-probe-argv" "startDetached call found" 'Item {
  Process { id: p; command: ["omanixy-idle-state", "probe"]; Component.onCompleted: p.startDetached() }
}'
assert_rejected_because "startdetached-bare" "startDetached call found" \
  'Item { Process { Component.onCompleted: startDetached() } }'
assert_rejected_because "startdetached-multiline" "startDetached call found" 'Item {
  Process { id: p; command: ["omanixy-idle-state", "set", "awake"]; Component.onCompleted: p.startDetached(
  ) }
}'
assert_accepted_raw "startdetached-fake-comment" 'Item {
  // p.startDetached()
  Process { command: ["omanixy-shell", "lock", "lock"] }
}'
assert_accepted_raw "startdetached-fake-block-comment" 'Item {
  /* p.startDetached() */
  Process { command: ["omanixy-idle-state", "probe"] }
}'
assert_accepted_raw "startdetached-fake-string" 'Item {
  property string note: "p.startDetached()"
  Process { command: ["omanixy-idle-state", "set", "idle"] }
}'
assert_rejected_because "startdetached-fake-comment-then-real" "startDetached call found" 'Item {
  // p.startDetached()
  Process { id: p; command: ["omanixy-shell", "lock", "lock"]; Component.onCompleted: p.startDetached() }
}'

printf '%s\n' 'idle executable surface checks passed'
