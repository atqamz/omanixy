#!/usr/bin/env bash
set -euo pipefail

scanner=${1:?executable surface scanner script required}
service_file=${2:?patched PolkitAgent.qml required}
python_bin=${3:?python3 interpreter required}
scripts_dir=${4:?scripts directory (for source_discovery) required}

export PYTHONPATH="$scripts_dir"

fixture=$(mktemp -d)
trap 'chmod -R u+w "$fixture"; rm -rf "$fixture"' EXIT

# The real, final PolkitAgent.qml has no Process.command executable surface
# at all - patch-polkit-agent removed the only one the pinned source had.
scan_output=$("$python_bin" "$scanner" "$service_file" 2>&1)
printf '%s\n' "$scan_output" >&2
grep -Fq '0 command bindings found' <<<"$scan_output"

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

# Section 13's explicit adversarial shapes: a bare unknown-executable array, a
# bash -c shape, a dynamic (non-literal) command expression, a procedural
# .command = assignment, and a multiline array equivalent - the audited
# invariant here is that NO command binding of any shape may survive, so all
# of these must fail even though some would be allowlisted by security.lock's
# own (much more permissive) scanner.
assert_rejected_raw "array-unknown-tool" 'Item {
  Process {
    command: ["mystery-tool"]
  }
}
'

assert_rejected_raw "bash-c" 'Item {
  Process {
    command: ["bash", "-c", "echo hi"]
  }
}
'

assert_rejected_raw "dynamic-expression" 'Item {
  Process {
    command: someDynamicExpression
  }
}
'

assert_rejected_raw "procedural-assignment" 'Item {
  function go() {
    proc.command = ["mystery-tool"]
  }
}
'

assert_rejected_raw "multiline-bash-c" 'Item {
  Process {
    command: [
      "bash",
      "-c",
      "echo hi"
    ]
  }
}
'

assert_rejected_raw "dynamic-call" 'Item {
  function go() {
    Quickshell.execDetached(dynamicArgs)
  }
}
'

assert_rejected_because "laptop-closed-reintroduced" "omarchy-hw-laptop-closed" 'Item {
  Process {
    command: ["bash", "-c", "omarchy-hw-laptop-closed && echo closed || echo open"]
  }
}
'

printf '%s\n' 'polkit executable surface checks passed'
