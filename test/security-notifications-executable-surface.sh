#!/usr/bin/env bash
set -euo pipefail

scanner=${1:?executable surface scanner script required}
service_file=${2:?patched notification Service.qml required}
python_bin=${3:?python3 interpreter required}
scripts_dir=${4:?scripts directory (for source_discovery) required}

export PYTHONPATH="$scripts_dir"

fixture=$(mktemp -d)
trap 'chmod -R u+w "$fixture"; rm -rf "$fixture"' EXIT

# The real, final Service.qml has exactly nine allowed command bindings
# (one per fixed-domain verb), exactly six enqueuePopupFileJob call sites
# with proven literal-array provenance, and zero exec/execDetached/run/
# startDetached calls.
scan_output=$("$python_bin" "$scanner" "$service_file" 2>&1)
printf '%s\n' "$scan_output" >&2
grep -Fq "9 command binding(s) passed, 6 enqueuePopupFileJob call site(s) with proven literal-array provenance, executable always 'omanixy-notification-state'" <<<"$scan_output"

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

# Every reviewed verb, both as a bare literal call and with trailing dynamic
# data - the ABI-defined shape.
assert_accepted_raw "allowed-init" 'Item { Process { command: ["omanixy-notification-state", "init"] } }'
assert_accepted_raw "allowed-persist-popup" 'Item { function go() { var command = ["omanixy-notification-state", "persist-popup", stem(), json()]; enqueue(command) } }'
assert_accepted_raw "allowed-archive-popup" 'Item { function go() { var command = ["omanixy-notification-state", "archive-popup", stem()] } }'
assert_accepted_raw "allowed-delete-popup" 'Item { function go() { var command = ["omanixy-notification-state", "delete-popup", stem()] } }'
assert_accepted_raw "allowed-persist-history" 'Item { function go() { var command = ["omanixy-notification-state", "persist-history", stem(), json(), "appIcon", src()] } }'
assert_accepted_raw "allowed-read-popups" 'Item { Process { command: ["omanixy-notification-state", "read-popups"] } }'
assert_accepted_raw "allowed-read-history" 'Item { Process { command: ["omanixy-notification-state", "read-history"] } }'
assert_accepted_raw "allowed-clear-history" 'Item { function go() { var command = ["omanixy-notification-state", "clear-history"] } }'
assert_accepted_raw "allowed-sweep-images" 'Item { function go() { var command = ["omanixy-notification-state", "sweep-images"] } }'
assert_accepted_raw "allowed-multiline" 'Item { Process { command: [
  "omanixy-notification-state",
  "read-history"
] } }'

assert_rejected_because "unknown-executable" "is not the allowed" \
  'Item { Process { command: ["mystery-tool", "init"] } }'
assert_rejected_because "dynamic-executable" "dynamic executable" \
  'Item { function go() { var command = [executableName(), "init"] } }'
assert_rejected_because "unknown-verb" "is not one of the reviewed fixed-domain verbs" \
  'Item { Process { command: ["omanixy-notification-state", "delete-everything"] } }'
assert_rejected_because "dynamic-verb" "dynamic verb" \
  'Item { function go() { var command = ["omanixy-notification-state", verbFromHints()] } }'
assert_rejected_because "no-verb" "invoked with no verb" \
  'Item { Process { command: ["omanixy-notification-state"] } }'
assert_rejected_because "bash-c" "not the allowed" \
  'Item { Process { command: ["bash", "-c", "echo hi"] } }'
assert_rejected_because "shell-in-data-position" "shell interpreter literal found in a data position" \
  'Item { function go() { var command = ["omanixy-notification-state", "persist-popup", "bash", json()] } }'
assert_rejected_because "dynamic-command" "dynamic command: binding" \
  'Item { Process { command: dynamicExpression } }'
assert_rejected_because "process-exec" "exec/execDetached call found" \
  'Item { Process { id: p; Component.onCompleted: p.exec(["omanixy-notification-state", "init"]) } }'
assert_rejected_because "bare-exec" "exec/execDetached call found" \
  'Item { Process { Component.onCompleted: exec(["omanixy-notification-state", "init"]) } }'
assert_rejected_because "quickshell-exec" "exec/execDetached call found" \
  'Item { function go() { Quickshell.exec(["omanixy-notification-state", "init"]) } }'
assert_rejected_because "quickshell-execdetached" "exec/execDetached call found" \
  'Item { function go() { Quickshell.execDetached(["omanixy-notification-state", "init"]) } }'
assert_rejected_because "util-execdetached" "exec/execDetached call found" \
  'Item { function go() { Util.execDetached(hintCommand()) } }'
assert_rejected_because "dot-run" "run call found" \
  'Item { function go() { runner.run(["omanixy-notification-state", "init"]) } }'
assert_rejected_because "startdetached" "startDetached call found" \
  'Item { Process { id: p; command: ["omanixy-notification-state", "init"]; Component.onCompleted: p.startDetached() } }'
# shellcheck disable=SC2016
assert_rejected_because "template-literal" "template literals are unsupported" \
  'Item { property string note: `no process here` }'
assert_rejected_because "omarchy-path-helper" "dynamic executable" \
  'Item { function go() { var command = [omarchyPath + "/bin/omarchy-hyprland-focus-app", app()] } }'

# Comment/string false-positive safety.
assert_accepted_raw "comment-fake" 'Item {
  // Process { command: ["mystery-tool", "init"] } exec(["x"]) runner.run(["y"])
  Process { command: ["omanixy-notification-state", "init"] }
}'
assert_accepted_raw "string-fake" 'Item {
  property string note: "Process { command: [\"mystery-tool\"] } exec([\"x\"])"
  Process { command: ["omanixy-notification-state", "read-popups"] }
}'
assert_rejected_because "fake-comment-then-real-bad" "is not the allowed" 'Item {
  // command: ["omanixy-notification-state", "init"]
  Process { command: ["mystery-tool", "init"] }
}'
assert_rejected_because "fake-string-then-real-exec" "exec/execDetached call found" 'Item {
  property string note: "exec([\"fake\"])"
  function go() { Quickshell.exec(["omanixy-notification-state", "init"]) }
}'

# ---------------------------------------------------------------
# Queue provenance: the canonical enqueuePopupFileJob/
# enqueueHistoryRead/runNextPopupFileJob plumbing, reproduced
# verbatim from the production patcher output. Kept in exact sync
# with scripts/scan-notification-executable-surface's own
# CANONICAL_BLOCKS constants - a change to one without the other is
# exactly the kind of drift these adversarial cases exist to catch.
# ---------------------------------------------------------------
good_queue_skeleton='  property var popupFileQueue: []
  property var runningPopupFileJobDone: null
  property bool popupFileJobAwaitingResult: false

  function enqueuePopupFileJob(command, done) {
    popupFileQueue = popupFileQueue.concat([{ command: command, done: done || null }])
    runNextPopupFileJob()
  }

  function enqueueHistoryRead() {
    popupFileQueue = popupFileQueue.concat([{ read: true }])
    runNextPopupFileJob()
  }

  function runNextPopupFileJob() {
    if (readHistoryProc.running || popupFileProc.running) return
    if (popupFileQueue.length === 0) return

    var job = popupFileQueue[0]
    popupFileQueue = popupFileQueue.slice(1)

    if (job.read) {
      startHistoryRead()
      return
    }

    popupFileProc.command = job.command
    service.runningPopupFileJobDone = job.done || null
    service.popupFileJobAwaitingResult = true
    popupFileProc.running = true
  }

  function persistPopupFile(snapshot) {
    var command = ["omanixy-notification-state", "persist-popup", stem(), json()]
    enqueuePopupFileJob(command)
  }

  Process { id: popupFileProc }
  Process { id: readHistoryProc }'

# Baseline: the canonical skeleton alone, with one legitimate call site,
# must be accepted - proves the provenance machinery does not itself
# false-positive on the real shape it exists to verify.
assert_accepted_raw "queue-provenance-baseline" "Item {
$good_queue_skeleton
}"

# S1: a harmless valid literal command exists, but a second, unrelated
# \`command: command\` appears outside any canonical block. Must reject -
# the exemption is not a bare-text allowlist anymore.
assert_rejected_because "queue-s1-second-command-command" "dynamic command: binding" "Item {
$good_queue_skeleton

  function decoy() {
    Qt.callLater(function() {
      var job = ({ command: command })
    })
  }
}"

# S2: a valid literal command exists, but \`popupFileProc.command =
# job.command\` appears a second time outside the one canonical
# runNextPopupFileJob context. Must reject.
assert_rejected_because "queue-s2-second-dequeue" "dynamic procedural .command = assignment" "Item {
$good_queue_skeleton

  function decoy() {
    var job = ({ command: [\"omanixy-notification-state\", \"init\"] })
    popupFileProc.command = job.command
  }
}"

# S3: canonical plumbing intact, but one enqueue callsite passes a function
# result instead of the reviewed literal command variable. Must reject.
assert_rejected_because "queue-s3-attacker-controlled-call" "only the bare identifier \`command\`" "Item {
$good_queue_skeleton

  function attackerFn() {
    enqueuePopupFileJob(attackerControlled())
  }
}"

# S4: one reviewed literal command construction is left dead while the
# actual enqueued value comes from a dynamic reassignment closer to the
# call. Must reject - the call-shape alone (bare \`command\`) is not enough,
# the nearest preceding construction must itself be the literal array.
assert_rejected_because "queue-s4-dead-literal-dynamic-reassignment" "is not a literal array" "Item {
$good_queue_skeleton

  function attackerFn() {
    var command = [\"omanixy-notification-state\", \"init\"]
    command = attackerControlled()
    enqueuePopupFileJob(command)
  }
}"

# S5: a second copy of an allowed dynamic expression (the whole
# enqueuePopupFileJob block, verbatim) is added. Must reject on the
# canonical-block occurrence count, not silently accept the duplicate.
assert_rejected_because "queue-s5-duplicated-canonical-block" "expected exactly one pinned occurrence, found 2" "Item {
$good_queue_skeleton

  function enqueuePopupFileJob(command, done) {
    popupFileQueue = popupFileQueue.concat([{ command: command, done: done || null }])
    runNextPopupFileJob()
  }
}"

# S6: the canonical queue function is renamed/restructured enough that the
# scanner can no longer prove provenance. Must fail closed on drift, not
# silently fall back to accepting the renamed shape.
assert_rejected_because "queue-s6-renamed-canonical-function" "expected exactly one pinned occurrence, found 0" "Item {
  property var popupFileQueue: []
  property var runningPopupFileJobDone: null
  property bool popupFileJobAwaitingResult: false

  function enqueuePopupFileJobRenamed(command, done) {
    popupFileQueue = popupFileQueue.concat([{ command: command, done: done || null }])
    runNextPopupFileJob()
  }

  function enqueueHistoryRead() {
    popupFileQueue = popupFileQueue.concat([{ read: true }])
    runNextPopupFileJob()
  }

  function runNextPopupFileJob() {
    if (readHistoryProc.running || popupFileProc.running) return
    if (popupFileQueue.length === 0) return

    var job = popupFileQueue[0]
    popupFileQueue = popupFileQueue.slice(1)

    if (job.read) {
      startHistoryRead()
      return
    }

    popupFileProc.command = job.command
    service.runningPopupFileJobDone = job.done || null
    service.popupFileJobAwaitingResult = true
    popupFileProc.running = true
  }

  function persistPopupFile(snapshot) {
    var command = [\"omanixy-notification-state\", \"persist-popup\", stem(), json()]
    enqueuePopupFileJobRenamed(command)
  }

  Process { id: popupFileProc }
  Process { id: readHistoryProc }
}"

printf '%s\n' 'notifications executable surface checks passed'
