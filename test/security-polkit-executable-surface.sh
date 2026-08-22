#!/usr/bin/env bash
set -euo pipefail

scanner=${1:?executable surface scanner script required}
service_file=${2:?patched PolkitAgent.qml required}
python_bin=${3:?python3 interpreter required}
scripts_dir=${4:?scripts directory (for source_discovery) required}

export PYTHONPATH="$scripts_dir"

fixture=$(mktemp -d)
trap 'chmod -R u+w "$fixture"; rm -rf "$fixture"' EXIT

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

assert_rejected_because "A-process-exec-literal" "Process object instantiation" 'Item {
  Process {
    id: p
    Component.onCompleted: p.exec(["mystery-tool"])
  }
}
'

assert_rejected_because "B-process-exec-dynamic" "Process object instantiation" 'Item {
  Process {
    id: p
    Component.onCompleted: p.exec(dynamicCommand)
  }
}
'

assert_rejected_because "C-unqualified-exec" "Process object instantiation" 'Item {
  Process {
    Component.onCompleted: exec(["mystery-tool"])
  }
}
'

assert_rejected_because "D-command-binding" "Process object instantiation" 'Item {
  Process {
    id: p
    command: ["mystery-tool"]
  }
}
'

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

assert_rejected_because "F-run-literal" "run call" 'Item {
  function go() {
    runner.run(["mystery-tool"])
  }
}
'

assert_rejected_because "G-run-dynamic" "run call" 'Item {
  function go() {
    runner.run(dynamicCommand)
  }
}
'

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

# shellcheck disable=SC2016
assert_rejected_because "template-literal" "template literals are unsupported" 'Item {
  property string note: `plain template no process`
}
'

printf '%s\n' 'polkit executable surface checks passed'
