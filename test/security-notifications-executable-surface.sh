#!/usr/bin/env bash
set -euo pipefail

scanner=${1:?executable surface scanner script required}
service_file=${2:?patched notification Service.qml required}
python_bin=${3:?python3 interpreter required}
scripts_dir=${4:?scripts directory (for source_discovery) required}

export PYTHONPATH="$scripts_dir"

fixture=$(mktemp -d)
trap 'chmod -R u+w "$fixture"; rm -rf "$fixture"' EXIT

scan_output=$("$python_bin" "$scanner" "$service_file" 2>&1)
printf '%s\n' "$scan_output" >&2
grep -Fq "9 command binding(s) passed, 6 canonical producer block(s) with proven producer-scope provenance, 6 enqueuePopupFileJob call site(s) accounted for, 3 canonical queue block(s) intact, executable always 'omanixy-notification-state'" <<<"$scan_output"

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
    // The JSON and every image source travel as argv elements, not through
    // shell interpolation - omanixy-notification-state owns HOME/stem
    // validation, the images directory, and bounded copying internally.
    var persistable = NotificationLogic.persistablePopup(snapshot, imagesDir)
    var command = ["omanixy-notification-state", "persist-popup", NotificationLogic.imageStem(snapshot),
      NotificationLogic.serializePopup(persistable.entry, NotificationUrgency.Normal)]
    for (var i = 0; i < persistable.copies.length; i++)
      command.push(persistable.copies[i].role, persistable.copies[i].from)
    enqueuePopupFileJob(command)
  }

  function deletePopupFileFor(row) {
    if (!row) return
    // History replays and the "no recent notifications" placeholder never
    // had a file - delete-popup on a nonexistent stem is a harmless no-op.
    var command = ["omanixy-notification-state", "delete-popup", NotificationLogic.imageStem(row)]
    enqueuePopupFileJob(command)
  }

  function archivePopupFileFor(row) {
    if (!row) return
    // A history replay or the empty-history placeholder has no file to move;
    // archive-popup on a nonexistent stem leaves the history untouched.
    // Image copies stay put - live and archived entries share imagesDir.
    var command = ["omanixy-notification-state", "archive-popup", NotificationLogic.imageStem(row)]
    enqueuePopupFileJob(command)
  }

  function writeHistoryFile(entry, done) {
    if (!entry) {
      if (done) done()
      return
    }
    var persistable = NotificationLogic.persistablePopup(entry, imagesDir)
    var command = ["omanixy-notification-state", "persist-history", NotificationLogic.imageStem(entry),
      NotificationLogic.serializePopup(persistable.entry, NotificationUrgency.Normal)]
    for (var i = 0; i < persistable.copies.length; i++)
      command.push(persistable.copies[i].role, persistable.copies[i].from)
    enqueuePopupFileJob(command, done)
  }

  function clearHistory() {
    var command = ["omanixy-notification-state", "clear-history"]
    enqueuePopupFileJob(command)
  }

  function sweepOrphanImages() {
    var command = ["omanixy-notification-state", "sweep-images"]
    enqueuePopupFileJob(command)
  }

  Process { id: popupFileProc }
  Process { id: readHistoryProc }'

assert_accepted_raw "queue-provenance-baseline" "Item {
$good_queue_skeleton
}"

assert_rejected_because "queue-s1-second-command-command" "dynamic command: binding" "Item {
$good_queue_skeleton

  function decoy() {
    Qt.callLater(function() {
      var job = ({ command: command })
    })
  }
}"

assert_rejected_because "queue-s2-second-dequeue" "dynamic procedural .command = assignment" "Item {
$good_queue_skeleton

  function decoy() {
    var job = ({ command: [\"omanixy-notification-state\", \"init\"] })
    popupFileProc.command = job.command
  }
}"

assert_rejected_because "queue-s3-attacker-controlled-call" "only the bare identifier \`command\`" "Item {
$good_queue_skeleton

  function attackerFn() {
    enqueuePopupFileJob(attackerControlled())
  }
}"

assert_rejected_because "queue-s4-dead-literal-dynamic-reassignment" "does not lie inside one of the six pinned producer blocks" "Item {
$good_queue_skeleton

  function attackerFn() {
    var command = [\"omanixy-notification-state\", \"init\"]
    command = attackerControlled()
    enqueuePopupFileJob(command)
  }
}"

assert_rejected_because "queue-s5-duplicated-canonical-block" "expected exactly one pinned occurrence, found 2" "Item {
$good_queue_skeleton

  function enqueuePopupFileJob(command, done) {
    popupFileQueue = popupFileQueue.concat([{ command: command, done: done || null }])
    runNextPopupFileJob()
  }
}"

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


assert_rejected_because "queue-s7-parameter-shadow" "does not lie inside one of the six pinned producer blocks" "Item {
$good_queue_skeleton

  function safe() {
    var command = [\"omanixy-notification-state\", \"init\"]
  }

  function evil(command) {
    enqueuePopupFileJob(command)
  }
}"

assert_rejected_because "queue-s8-parameter-shadow-dynamic-caller" "does not lie inside one of the six pinned producer blocks" "Item {
$good_queue_skeleton

  function evil(command) {
    enqueuePopupFileJob(command)
  }

  function bridge(notification) {
    evil(notification.hints[\"argv\"])
  }
}"

assert_rejected_because "queue-s9-prior-function-literal-only" "does not lie inside one of the six pinned producer blocks" "Item {
$good_queue_skeleton

  function safe() {
    var command = [\"omanixy-notification-state\", \"init\"]
  }

  function evil() {
    enqueuePopupFileJob(command)
  }
}"

assert_rejected_because "queue-s10-destructured-shadow" "does not lie inside one of the six pinned producer blocks" "Item {
$good_queue_skeleton

  function evil(payload) {
    var { command } = payload
    enqueuePopupFileJob(command)
  }
}"

assert_rejected_because "queue-s12-reviewed-producer-second-reassignment" "does not lie inside one of the six pinned producer blocks" "Item {
$good_queue_skeleton

  function evilProducer() {
    var command = [\"omanixy-notification-state\", \"sweep-images\"]
    command = attackerControlled()
    enqueuePopupFileJob(command)
  }
}"

assert_rejected_because "queue-s13-parameter-plus-local-ambiguity" "does not lie inside one of the six pinned producer blocks" "Item {
$good_queue_skeleton

  function evilProducer(command) {
    if (command) {
      var command = [\"omanixy-notification-state\", \"sweep-images\"]
    }
    enqueuePopupFileJob(command)
  }
}"

assert_rejected_because "queue-s14-duplicate-producer-block" "expected exactly one pinned occurrence, found 2" "Item {
$good_queue_skeleton

  function sweepOrphanImages() {
    var command = [\"omanixy-notification-state\", \"sweep-images\"]
    enqueuePopupFileJob(command)
  }
}"

printf '%s\n' 'notifications executable surface checks passed'
