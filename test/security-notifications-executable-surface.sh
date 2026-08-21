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
# (one per fixed-domain verb), exactly six pinned executable producer
# blocks (persistPopupFile/deletePopupFileFor/archivePopupFileFor/
# writeHistoryFile/clearHistory/sweepOrphanImages) each proving its own
# enqueuePopupFileJob call site in its own lexical scope, three canonical
# queue-plumbing blocks, and zero exec/execDetached/run/startDetached
# calls.
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
# enqueueHistoryRead/runNextPopupFileJob plumbing PLUS the six canonical
# executable producer functions (persistPopupFile/deletePopupFileFor/
# archivePopupFileFor/writeHistoryFile/clearHistory/sweepOrphanImages),
# all reproduced verbatim from the production patcher output. Kept in
# exact sync with scripts/scan-notification-executable-surface's own
# CANONICAL_BLOCKS/PRODUCER_CANONICAL_BLOCKS constants - a change to one
# without the other is exactly the kind of drift these adversarial cases
# exist to catch.
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

# Baseline: the canonical skeleton alone, with its six legitimate producer
# call sites, must be accepted - proves the provenance machinery does not
# itself false-positive on the real shape it exists to verify. This is
# also adversarial case S11 (a function-local reviewed literal producer,
# under its proven canonical shape, must ACCEPT) for every one of the six
# producers at once.
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
# call, inside a function that is not one of the six pinned producers.
# Must reject - the call-shape alone (bare \`command\`) is not enough, the
# call site itself must lie inside a pinned producer's own lexical scope,
# never traced back to a same-named construction anywhere else in the file.
assert_rejected_because "queue-s4-dead-literal-dynamic-reassignment" "does not lie inside one of the six pinned producer blocks" "Item {
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

# ---------------------------------------------------------------
# Cross-scope producer provenance (S7-S14): the false-open this
# remediation closes. The old scanner traced an enqueuePopupFileJob call's
# \`command\` argument back to the file-global "nearest preceding
# construction" of that identifier - a lexical-scope-blind proof that a
# same-named function parameter, an unrelated prior function's literal, a
# destructured local, or a dynamic reassignment inside a wholly different,
# unreviewed function could all satisfy by pure text position. Every case
# below builds on the full six-producer/three-queue skeleton above, so
# each one proves the decoy function - never one of the six pinned
# producers - is what gets rejected.
# ---------------------------------------------------------------

# S7: a function parameter named \`command\` shadows an unrelated, safe
# literal construction in a prior function. Must reject.
assert_rejected_because "queue-s7-parameter-shadow" "does not lie inside one of the six pinned producer blocks" "Item {
$good_queue_skeleton

  function safe() {
    var command = [\"omanixy-notification-state\", \"init\"]
  }

  function evil(command) {
    enqueuePopupFileJob(command)
  }
}"

# S8: same shadow as S7, plus an actual dynamic caller feeding the
# parameter from attacker-influenced notification hints. Must reject.
assert_rejected_because "queue-s8-parameter-shadow-dynamic-caller" "does not lie inside one of the six pinned producer blocks" "Item {
$good_queue_skeleton

  function evil(command) {
    enqueuePopupFileJob(command)
  }

  function bridge(notification) {
    evil(notification.hints[\"argv\"])
  }
}"

# S9: no parameter shadow at all - the calling function has no local
# \`command\` of its own, only a prior, unrelated function's literal. Must
# reject; a lexical scope cannot borrow another function's local.
assert_rejected_because "queue-s9-prior-function-literal-only" "does not lie inside one of the six pinned producer blocks" "Item {
$good_queue_skeleton

  function safe() {
    var command = [\"omanixy-notification-state\", \"init\"]
  }

  function evil() {
    enqueuePopupFileJob(command)
  }
}"

# S10: a destructured local named \`command\` stands in for the parameter
# shadow. Must reject via the same producer-scope mechanism.
assert_rejected_because "queue-s10-destructured-shadow" "does not lie inside one of the six pinned producer blocks" "Item {
$good_queue_skeleton

  function evil(payload) {
    var { command } = payload
    enqueuePopupFileJob(command)
  }
}"

# S12: a reviewed-looking producer with an extra reassignment between the
# literal construction and the enqueue call. The extra statement means
# this function's text can never match any of the six pinned producer
# blocks, so its call site is rejected the same as any other decoy.
assert_rejected_because "queue-s12-reviewed-producer-second-reassignment" "does not lie inside one of the six pinned producer blocks" "Item {
$good_queue_skeleton

  function evilProducer() {
    var command = [\"omanixy-notification-state\", \"sweep-images\"]
    command = attackerControlled()
    enqueuePopupFileJob(command)
  }
}"

# S13: a function parameter named \`command\` plus an ambiguous local
# reassignment inside the same function. Must fail closed.
assert_rejected_because "queue-s13-parameter-plus-local-ambiguity" "does not lie inside one of the six pinned producer blocks" "Item {
$good_queue_skeleton

  function evilProducer(command) {
    if (command) {
      var command = [\"omanixy-notification-state\", \"sweep-images\"]
    }
    enqueuePopupFileJob(command)
  }
}"

# S14: one of the six canonical producer blocks (sweepOrphanImages) is
# duplicated verbatim a second time. Must reject on exact-count drift, not
# silently accept the duplicate as a second valid producer.
assert_rejected_because "queue-s14-duplicate-producer-block" "expected exactly one pinned occurrence, found 2" "Item {
$good_queue_skeleton

  function sweepOrphanImages() {
    var command = [\"omanixy-notification-state\", \"sweep-images\"]
    enqueuePopupFileJob(command)
  }
}"

printf '%s\n' 'notifications executable surface checks passed'
