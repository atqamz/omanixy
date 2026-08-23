#!/usr/bin/env bash
set -euo pipefail

scanner=${1:?executable surface scanner script required}
service_file=${2:?patched PolkitAgent.qml required}
python_bin=${3:?python3 interpreter required}
scripts_dir=${4:?scripts directory (for source_discovery) required}

export PYTHONPATH="$scripts_dir"

fixture=$(mktemp -d)
trap 'chmod -R u+w "$fixture"; rm -rf "$fixture"' EXIT

# The real, final PolkitAgent.qml has no process-execution surface of any
# shape at all - patch-polkit-agent removed the only Process the pinned
# source had. The invariant is stronger than "no command binding": it is
# zero Process object instantiations, zero command bindings, and zero
# exec/execDetached/run calls, since a bare Process object with no command
# property can still execute arbitrary commands via .exec(...).
scan_output=$("$python_bin" "$scanner" "$service_file" 2>&1)
printf '%s\n' "$scan_output" >&2
grep -Fq '0 Process objects, 0 command bindings, 0 exec/run calls found' <<<"$scan_output"

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

# Original command-binding shapes: a bare unknown-executable array, a
# bash -c shape, a dynamic (non-literal) command expression, a procedural
# .command = assignment, and a multiline array equivalent. All of these
# also declare (or imply) a Process object, so the current scanner rejects
# them via the Process-object ban as much as via the command-binding check
# - both invariants are exercised together, which is the point.
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

assert_rejected_raw "procedural-assignment-no-process" 'Item {
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

assert_rejected_raw "laptop-closed-reintroduced" 'Item {
  Process {
    command: ["bash", "-c", "omarchy-hw-laptop-closed && echo closed || echo open"]
  }
}
'

# Case A: a Process object whose only executable surface is a runtime
# .exec(...) call with a literal argument - no command: property at all.
# This is exactly the shape the pinned Quickshell Process::exec(QList<QString>)
# overload allows and the previous scanner generation (command-binding-only)
# could not see.
assert_rejected_because "A-process-exec-literal" "Process object instantiation" 'Item {
  Process {
    id: p
    Component.onCompleted: p.exec(["mystery-tool"])
  }
}
'

# Case B: same shape, dynamic argument.
assert_rejected_because "B-process-exec-dynamic" "Process object instantiation" 'Item {
  Process {
    id: p
    Component.onCompleted: p.exec(dynamicCommand)
  }
}
'

# Case C: unqualified exec() called from inside a Process's own scope -
# implicitly resolves to that Process instance own exec method.
assert_rejected_because "C-unqualified-exec" "Process object instantiation" 'Item {
  Process {
    Component.onCompleted: exec(["mystery-tool"])
  }
}
'

# Case D: the original command: property binding shape, restated for the
# permanent adversarial record alongside the newer exec/run cases.
assert_rejected_because "D-command-binding" "Process object instantiation" 'Item {
  Process {
    id: p
    command: ["mystery-tool"]
  }
}
'

# Case E: procedural .command = assignment plus running = true, entirely
# inside a Process object (as opposed to the no-process procedural-
# assignment case above, which has no Process object to catch it either).
assert_rejected_because "E-procedural-assign-running" "Process object instantiation" 'Item {
  Process {
    id: p
    Component.onCompleted: {
      p.command = ["mystery-tool"]
      p.running = true
    }
  }
}
'

# Case F: an arbitrary object.run([...]) call with a LITERAL array argument.
# The shared source_discovery.DYNAMIC_RUN_RE deliberately excludes a literal
# array argument (it is designed for security.lock's allowlist model, which
# needs to inspect rather than reject a literal); this scanner's own local
# RUN_CALL_RE has no such exclusion, since the invariant here is absence of
# any run(...) call at all.
assert_rejected_because "F-run-literal" "run call" 'Item {
  function go() {
    runner.run(["mystery-tool"])
  }
}
'

# Case G: same call, dynamic argument.
assert_rejected_because "G-run-dynamic" "run call" 'Item {
  function go() {
    runner.run(dynamicCommand)
  }
}
'

# Case H/I: Quickshell.exec/execDetached remain rejected, now via the local
# EXEC_CALL_RE rather than an imported source_discovery pattern.
assert_rejected_because "H-quickshell-exec" "exec/execDetached call" 'Item {
  function go() {
    Quickshell.exec(["mystery-tool"])
  }
}
'

assert_rejected_because "I-quickshell-execdetached" "exec/execDetached call" 'Item {
  function go() {
    Quickshell.execDetached(["mystery-tool"])
  }
}
'

# Case J: multiline p.exec([...]) - proves detection is not a per-line regex.
assert_rejected_because "J-multiline-exec" "Process object instantiation" 'Item {
  Process {
    id: p
    Component.onCompleted: p.exec([
      "mystery-tool",
      "--probe"
    ])
  }
}
'

# Comment/string false-positive safety: Process/.exec/.run-looking text
# sitting inertly in a // comment, a /* */ comment, or an ordinary quoted
# string must not itself trip the scanner.
assert_accepted_raw "line-comment-fake" 'Item {
  // Process { command: ["mystery-tool"] }
  // exec(["mystery-tool"])
  // runner.run(["mystery-tool"])
}
'

assert_accepted_raw "block-comment-fake" 'Item {
  /* Process { command: ["mystery-tool"] } exec(["x"]) runner.run(["y"]) */
}
'

assert_accepted_raw "string-fake" 'Item {
  property string note: "Process { command: [\"mystery-tool\"] } exec([\"x\"]) runner.run([\"y\"])"
}
'

# A real executable call sitting after fake text in a comment or string must
# still be caught - the fake text must not "use up" or otherwise weaken the
# scan.
assert_rejected_because "fake-comment-then-real-process" "Process object instantiation" 'Item {
  // Process { command: ["fake-not-real"] }
  Process {
    id: p
    command: ["mystery-tool"]
  }
}
'

assert_rejected_because "fake-string-then-real-exec" "exec/execDetached call" 'Item {
  property string note: "exec([\"fake\"])"
  function go() {
    Quickshell.exec(["real-mystery-tool"])
  }
}
'

# Template-literal policy is unchanged: any live backtick is rejected
# outright, independent of whether it mentions Process/exec/run at all.
# shellcheck disable=SC2016
assert_rejected_because "template-literal" "template literals are unsupported" 'Item {
  property string note: `plain template no process`
}
'

printf '%s\n' 'polkit executable surface checks passed'
