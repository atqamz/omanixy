#!/usr/bin/env bash
set -euo pipefail

compat_root=${1:?notification-daemon-enabled compatibility root required}
quickshell=${2:?selected Quickshell executable required}
notification_state_adapter=${3:?adapters/notification-state.bash path required}
python=${PYTHON:-python3}

test_root=$(mktemp -d)
trap 'chmod -R u+w "$test_root" 2>/dev/null || true; rm -rf "$test_root"' EXIT
mkdir -p "$test_root/home" "$test_root/runtime" "$test_root/bin"

real_bash=$(command -v bash)
cat >"$test_root/bin/omanixy-notification-state" <<EOF
#!/usr/bin/env bash
set -euo pipefail
source "$notification_state_adapter"
notification_state "\$@"
EOF
chmod +x "$test_root/bin/omanixy-notification-state"
sed -i "1c#!$real_bash" "$test_root/bin/omanixy-notification-state"

setup_fixture() {
  local fixture_dir=$1
  mkdir -p "$fixture_dir/components"
  cp "$compat_root/shell/plugins/notifications/Service.qml" "$fixture_dir/Service.qml"
  cp "$compat_root/shell/plugins/notifications/NotificationLogic.js" "$fixture_dir/NotificationLogic.js"
  cp "$compat_root/shell/plugins/notifications/components/NotificationCard.qml" "$fixture_dir/components/NotificationCard.qml"
  chmod u+w "$fixture_dir/Service.qml" "$fixture_dir/NotificationLogic.js"
  cat >"$fixture_dir/components/qmldir" <<'EOF'
module fixture-notifications.components
NotificationCard 1.0 NotificationCard.qml
EOF
}


harness1_dir="$test_root/h1"
mkdir -p "$harness1_dir"
notifications_fixture_dir="$harness1_dir/fixture-notifications"
setup_fixture "$notifications_fixture_dir"

"$python" - "$notifications_fixture_dir/Service.qml" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text()


def replace_once(text, old, new, label):
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected one pinned block, found {count}")
    return text.replace(old, new, 1)


# Harness-only: expose real internal state to the offscreen driver script.
service_old = "Item {\n  id: service\n"
service_new = (
    "Item {\n  id: service\n"
    "  property alias fakeServer: server\n"
    "  property alias fakePopupFileProc: popupFileProc\n"
    "  property alias fakeReadHistoryProc: readHistoryProc\n"
    "  property alias fakeRestorePopupsProc: restorePopupsProc\n"
)
text = replace_once(text, service_old, service_new, "service id/alias anchor")

# Harness-only: PanelWindow needs a real Wayland layer-shell surface, which
# no offscreen environment provides. A plain Item preserves the property
# this file actually reads from popupWindow (visible via popupModel.count).
panel_old = (
    "    PanelWindow {\n"
    "      id: popupWindow\n"
    "      required property var modelData\n"
    "      screen: modelData\n"
    "      visible: popupModel.count > 0\n"
    "\n"
    '      WlrLayershell.namespace: "omarchy-notifications"\n'
    "      WlrLayershell.layer: WlrLayer.Overlay\n"
    "      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None\n"
    "      exclusionMode: ExclusionMode.Ignore\n"
    '      color: "transparent"\n'
)
panel_new = (
    "    Item {\n"
    "      id: popupWindow\n"
    "      required property var modelData\n"
    "      visible: popupModel.count > 0\n"
)
text = replace_once(text, panel_old, panel_new, "popupWindow PanelWindow->Item")

mask_old = "      mask: Region { item: popupColumn }\n"
text = replace_once(text, mask_old, "", "popupWindow mask (layer-shell only)")

# Harness-only: PanelWindow's own boolean-edge `anchors { top: true; ... }`
# syntax is not the standard Item anchors API and fails to parse against a
# plain Item. popupWindow needs no anchors of its own for this harness.
anchors_old = (
    "      anchors { top: true; bottom: true; left: true; right: true }\n"
    "\n"
)
text = replace_once(text, anchors_old, "", "popupWindow boolean-edge anchors (layer-shell only)")

# Harness-only: the real NotificationServer needs a live D-Bus session bus.
# Replaced with an inline QtObject exposing the identical signal surface
# this file actually reads (a "notification" signal feeding the unmodified
# onNotification: handler) plus a fakeNotify driver function building
# deterministic fake Notification-shaped QtObjects - real QtObject property
# signals (summaryChanged etc.), a real actions array, a real closed
# signal, and tracked/expire/dismiss semantics mirroring the pinned
# Quickshell Notification ABI closely enough to exercise every handler in
# this file unmodified.
server_old = (
    "  NotificationServer {\n"
    "    id: server\n"
    "    keepOnReload: false\n"
    "    imageSupported: true\n"
    "    actionsSupported: true\n"
    "    bodyMarkupSupported: true\n"
    "    bodyHyperlinksSupported: true\n"
    "    persistenceSupported: true\n"
    "\n"
    "    onNotification: function(notification) {\n"
    "      service.handleNotification(notification)\n"
    "    }\n"
    "  }\n"
)
server_new = '''  QtObject {
    id: server

    signal notification(var notification)
    onNotification: function(n) { service.handleNotification(n) }

    property var _idMap: ({})
    property int _nextId: 1

    property Component _notificationComponent: Component {
      QtObject {
        id: n
        property int id: 0
        property string appName: ""
        property string appIcon: ""
        property string summary: ""
        property string body: ""
        property string image: ""
        property var hints: ({})
        property int urgency: 1
        property int expireTimeout: -1
        property var actions: []
        property bool tracked: false
        signal closed(int reason)
        function expire() { n.closed(1) }
        function dismiss() { n.closed(2) }
      }
    }

    // Mirrors the pinned NotificationServer.Notify() replaces_id contract:
    // replacesId != 0 reuses the existing idMap object (updating its
    // properties, which fires the real QtObject xChanged signals
    // watchForUpdates listens to) rather than emitting a second
    // "notification" signal.
    function fakeNotify(fields) {
      var f = fields || {}
      var replacesId = f.replacesId || 0
      var existing = replacesId !== 0 ? server._idMap[replacesId] : null
      if (existing) {
        existing.appName = f.appName !== undefined ? f.appName : existing.appName
        existing.appIcon = f.appIcon !== undefined ? f.appIcon : existing.appIcon
        existing.summary = f.summary !== undefined ? f.summary : existing.summary
        existing.body = f.body !== undefined ? f.body : existing.body
        existing.image = f.image !== undefined ? f.image : existing.image
        existing.hints = f.hints !== undefined ? f.hints : existing.hints
        existing.urgency = f.urgency !== undefined ? f.urgency : existing.urgency
        existing.expireTimeout = f.expireTimeout !== undefined ? f.expireTimeout : existing.expireTimeout
        return existing.id
      }

      var id = server._nextId++
      var obj = server._notificationComponent.createObject(server, {
        id: id,
        appName: f.appName || "",
        appIcon: f.appIcon || "",
        summary: f.summary || "",
        body: f.body || "",
        image: f.image || "",
        hints: f.hints || ({}),
        urgency: f.urgency === undefined ? 1 : f.urgency,
        expireTimeout: f.expireTimeout === undefined ? -1 : f.expireTimeout,
        actions: f.actions || []
      })
      server._idMap[id] = obj
      server.notification(obj)
      return id
    }
  }
'''
text = replace_once(text, server_old, server_new, "server NotificationServer->fake QtObject")

path.write_text(text)
PY

hostile_marker="$harness1_dir/hostile-side-effect"

cat >"$harness1_dir/shell.qml" <<EOF
import QtQuick
import Quickshell

ShellRoot {
  id: shellRoot

  Loader {
    id: serviceLoader
    source: Qt.resolvedUrl("fixture-notifications/Service.qml")
  }

  Loader {
    id: serviceLoader2
    active: false
    source: Qt.resolvedUrl("fixture-notifications/Service.qml")
  }

  readonly property string hostileMarkerPath: "$hostile_marker"

  function fail(label, detail) {
    console.log("NOTIF_QML_FAIL", label, detail === undefined ? "" : JSON.stringify(detail))
    Qt.quit()
  }

  function check(condition, label, detail) {
    if (!condition) fail(label, detail)
  }

  property var service: null
  property var fake: null

  function waitFor(description, predicate, next) {
    var attempts = 0
    var poll = Qt.createQmlObject(
      'import QtQuick; Timer { interval: 20; repeat: true; running: true }',
      shellRoot, "poll-" + description)
    poll.triggered.connect(function() {
      attempts++
      if (predicate()) {
        poll.running = false
        poll.destroy()
        next()
        return
      }
      if (attempts >= 250) {
        poll.running = false
        poll.destroy()
        fail("timeout-" + description)
      }
    })
  }

  function queueDrained() {
    return service.popupFileQueue.length === 0 && !service.fakePopupFileProc.running
      && !service.fakeReadHistoryProc.running
  }

  function runCases() {
    service = serviceLoader.item
    fake = service.fakeServer

    // A. an ordinary notification creates exactly one popup, with no exec
    // role anywhere on the row (the historical omarchy-exec hint must never
    // survive into persisted/model state under any name).
    fake.fakeNotify({ appName: "TestApp", summary: "Hello-A", hints: { "omarchy-exec": "touch /tmp/pwned" } })
    waitFor("A-popup-created", function() { return service.popupModel.count === 1 }, function() {
      var row = service.popupModel.get(0)
      check(row.app === "TestApp", "A-app", row.app)
      check(row.summary === "Hello-A", "A-summary", row.summary)
      check(row.exec === undefined, "A-no-exec-role", row.exec)
      waitFor("A-persisted", queueDrained, caseB)
    })
  }

  function caseB() {
    // B. DND on: an ordinary non-ephemeral notification creates no popup,
    // AND actually produces history state through the real queue/helper
    // (writeSilenced -> writeHistoryFile -> the real adapter) - not merely
    // a popup-count assertion.
    service.setDoNotDisturb(true)
    check(service.doNotDisturb === true, "B-dnd-on")
    var beforeCount = service.popupModel.count
    fake.fakeNotify({ appName: "SilencedApp", summary: "Silenced-B-marker" })
    check(service.popupModel.count === beforeCount, "B-no-new-popup")
    waitFor("B-history-persisted", queueDrained, function() {
      service.setDoNotDisturb(false)
      caseC()
    })
  }

  function caseC() {
    // C. replacement: same live identity, no duplicate popup row, row
    // content updates, persisted popup reflects the replacement, no old
    // duplicate persisted row (replacementSnapshot reuses the original
    // timestamp, so the persisted file's stem never changes on replace).
    var idC = fake.fakeNotify({ appName: "ReplaceApp", summary: "Original-C", body: "orig-body-C" })
    waitFor("C-popup-created", function() {
      return service.popupModel.count >= 1 && service.popupModel.get(0).originalId === idC
    }, function() {
      var countBefore = service.popupModel.count
      fake.fakeNotify({ replacesId: idC, summary: "Updated-C-marker", body: "updated-body-C" })
      check(service.popupModel.count === countBefore, "C-no-duplicate-row")
      var row = service.popupModel.get(0)
      check(row.originalId === idC, "C-same-identity", row.originalId)
      check(row.summary === "Updated-C-marker", "C-row-updated", row.summary)
      waitFor("C-replacement-persisted", queueDrained, caseD)
    })
  }

  function caseD() {
    // D. DND persistence: toggle DND, let the debounced settings save
    // complete, then hydrate a SECOND real instance of the same generated
    // Service.qml against the same HOME - the narrowest deterministic
    // equivalent of a shell restart using the real generated load path
    // (FileView onLoaded -> loadSettings), not a reimplementation.
    service.setDoNotDisturb(true)
    waitFor("D-settings-saved", function() { return !service.settingsLoaded === false }, function() {
      // settingsSaveTimer is 200ms; poll until enough time has elapsed by
      // waiting for the timer to no longer be logically pending via a
      // fixed number of event-loop turns instead of a raw sleep.
      var ticks = 0
      var settleTimer = Qt.createQmlObject('import QtQuick; Timer { interval: 30; repeat: true; running: true }', shellRoot, "d-settle")
      settleTimer.triggered.connect(function() {
        ticks++
        if (ticks < 15) return
        settleTimer.running = false
        settleTimer.destroy()
        serviceLoader2.active = true
        waitFor("D-second-instance-loaded", function() { return serviceLoader2.item !== null }, function() {
          var service2 = serviceLoader2.item
          waitFor("D-second-instance-hydrated", function() { return service2.settingsLoaded === true }, function() {
            check(service2.doNotDisturb === true, "D-dnd-hydrated-from-disk", service2.doNotDisturb)
            service.setDoNotDisturb(false)
            waitFor("D-restore-off-persisted", queueDrained, caseE)
          })
        })
      })
    })
  }

  function caseE() {
    // E. dismiss: create a popup, wait for it to persist, dismiss it -
    // live popup disappears, and (checked on-disk after this process
    // exits) its live popup file is archived into history, not left behind
    // and not merely deleted.
    var idE = fake.fakeNotify({ appName: "DismissApp", summary: "Dismiss-E-marker" })
    waitFor("E-popup-created", function() {
      return service.popupModel.count >= 1 && service.popupModel.get(0).originalId === idE
    }, function() {
      waitFor("E-persisted", queueDrained, function() {
        var countBefore = service.popupModel.count
        service.dismissPopup(0)
        check(service.popupModel.count === countBefore - 1, "E-popup-removed")
        waitFor("E-archived", queueDrained, caseF)
      })
    })
  }

  function caseF() {
    // F. expiration: create a finite-lifetime popup and drive expiration
    // directly through the same function the real countdown Timer calls
    // (service.expirePopup), rather than sleeping through the real
    // wall-clock lifetime - proving the same archive semantics production
    // expiration uses, without a timing-dependent test.
    var idF = fake.fakeNotify({ appName: "ExpireApp", summary: "Expire-F-marker", expireTimeout: 1000 })
    waitFor("F-popup-created", function() {
      return service.popupModel.count >= 1 && service.popupModel.get(0).originalId === idF
    }, function() {
      waitFor("F-persisted", queueDrained, function() {
        var countBefore = service.popupModel.count
        service.expirePopup(0)
        check(service.popupModel.count === countBefore - 1, "F-popup-removed")
        waitFor("F-archived", queueDrained, caseG)
      })
    })
  }

  function caseG() {
    // G. a live "default" FDO action invokes exactly once, and only that -
    // never a shell command, never a compositor-focus fallback.
    var invokedCount = 0
    var id = fake.fakeNotify({
      appName: "ActionApp",
      summary: "Has-action-G",
      actions: [{ identifier: "default", invoke: function() { invokedCount++ } }]
    })
    waitFor("G-popup-created", function() { return service.popupModel.count >= 1 && service.popupModel.get(0).originalId === id }, function() {
      service.invokePopupDefault(0)
      check(invokedCount === 1, "G-invoked-once", invokedCount)
      waitFor("G-settled", queueDrained, caseH)
    })
  }

  function caseH() {
    // H. no live "default" action: invoking performs no external execution
    // and no error - the popup is simply dismissed.
    var id = fake.fakeNotify({ appName: "NoActionApp", summary: "No-action-H", actions: [] })
    waitFor("H-popup-created", function() { return service.popupModel.count >= 1 && service.popupModel.get(0).originalId === id }, function() {
      var countBefore = service.popupModel.count
      service.invokePopupDefault(0)
      check(service.popupModel.count === countBefore - 1, "H-dismissed-not-crashed")
      waitFor("H-settled", queueDrained, caseI)
    })
  }

  function caseI() {
    // I. hostile omarchy-exec click: a LIVE notification with no default
    // action carries hints["omarchy-exec"] naming a real, checkable side
    // effect (a file this test would find afterward). Actually calling the
    // click path (invokePopupDefault) must never create it - not a
    // structural schema assertion alone.
    var id = fake.fakeNotify({
      appName: "HostileExecApp",
      summary: "Hostile-I-marker",
      hints: { "omarchy-exec": "touch " + shellRoot.hostileMarkerPath },
      actions: []
    })
    waitFor("I-popup-created", function() { return service.popupModel.count >= 1 && service.popupModel.get(0).originalId === id }, function() {
      var row = service.popupModel.get(0)
      check(row.exec === undefined, "I-no-exec-role-on-live-row", row.exec)
      var countBefore = service.popupModel.count
      service.invokePopupDefault(0)
      check(service.popupModel.count === countBefore - 1, "I-dismissed-only")
      waitFor("I-settled", queueDrained, caseJ)
    })
  }

  function caseJ() {
    // J. a restored row (isRestoredRow) performs NO action execution even
    // when it happens to carry a live-looking actions array (it never
    // would in practice - liveRefs has no entry for it - but this proves
    // invokePopupDefault never resolves a restored row against liveRefs by
    // coincidental id reuse).
    // popupFileName is imageStem(row) + ".json", and imageStem is
    // "<timestamp>-<originalId>" - the key must match that exactly, not
    // the row's own "id" field.
    service.restoredPopups["9000-9.json"] = true
    var invoked = false
    service.popupModel.insert(0, {
      id: 9999, originalId: 9, app: "Restored", appIcon: "", summary: "Restored toast",
      body: "", image: "", glyph: "", urgency: 1, expireTimeout: 0, timestamp: 9000
    })
    // A coincidental fresh notification could reuse originalId 9 in
    // liveRefs; simulate that hostile coincidence directly to prove the
    // restored flag - not the id - gates whether an action may fire.
    service.liveRefs[9] = { actions: [{ identifier: "default", invoke: function() { invoked = true } }], tracked: true }
    service.invokePopupDefault(0)
    check(invoked === false, "J-restored-row-never-invokes")
    delete service.liveRefs[9]
    // Cases K and L run in a separate quickshell invocation (part 2, below)
    // against the same HOME: K's history flood legitimately trims older
    // history (including case B/E/F's entries) to its own newest 10, so
    // the on-disk proofs for A-J below must run before K ever starts, not
    // after the same process has moved on to K/L.
    console.log("NOTIF_QML_PASS_PART1")
    Qt.quit()
  }

  Timer {
    id: readyPoll
    interval: 50
    repeat: true
    running: true
    property int attempts: 0
    onTriggered: {
      attempts++
      if (!serviceLoader.item) {
        if (attempts >= 100) {
          console.log("NOTIF_QML_FAIL", "service did not load")
          Qt.quit()
        }
        return
      }
      running = false
      runCases()
    }
  }
}
EOF

ln -s "$compat_root/shell" "$harness1_dir/qs"
cp -R "$compat_root/shell/Commons" "$harness1_dir/Commons"
cp -R "$compat_root/shell/Ui" "$harness1_dir/Ui"
chmod -R u+w "$harness1_dir/Commons" "$harness1_dir/Ui"

HOME="$test_root/home" XDG_RUNTIME_DIR="$test_root/runtime" QML2_IMPORT_PATH="$harness1_dir" \
  PATH="$test_root/bin:$PATH" QT_QPA_PLATFORM=offscreen timeout 30s "$quickshell" -n -p "$harness1_dir" \
  >"$harness1_dir/quickshell-part1.log" 2>&1 &
quickshell1a_pid=$!
wait "$quickshell1a_pid" || true

if ! grep -Fq 'NOTIF_QML_PASS_PART1' "$harness1_dir/quickshell-part1.log"; then
  cat "$harness1_dir/quickshell-part1.log" >&2
  exit 1
fi

state_dir="$test_root/home/.local/state/omarchy/notifications"
history_dir="$state_dir/history"
settings_file="$test_root/home/.local/state/omarchy/notifications.json"

if grep -rq '"exec"' "$state_dir" 2>/dev/null; then
  printf 'persisted state unexpectedly contains an exec field somewhere under %s\n' "$state_dir" >&2
  grep -rl '"exec"' "$state_dir" >&2
  exit 1
fi
if grep -rq 'touch /tmp/pwned' "$state_dir" 2>/dev/null; then
  printf 'the omarchy-exec hint value from case A leaked into persisted state\n' >&2
  exit 1
fi

if ! grep -rq 'Silenced-B-marker' "$history_dir" 2>/dev/null; then
  printf 'case B: DND-silenced notification did not reach real history state under %s\n' "$history_dir" >&2
  exit 1
fi
if find "$state_dir" -maxdepth 1 -name '*.json' -exec grep -q 'Silenced-B-marker' {} \; -print 2>/dev/null | grep -q .; then
  printf 'case B: DND-silenced notification unexpectedly has a live popup file\n' >&2
  exit 1
fi

c_files=$(grep -rl 'Updated-C-marker' "$state_dir" 2>/dev/null | wc -l)
if [[ $c_files -ne 1 ]]; then
  printf 'case C: expected exactly one persisted file reflecting the replacement, found %s\n' "$c_files" >&2
  exit 1
fi
if grep -rq '"summary":"Original-C"' "$state_dir" 2>/dev/null; then
  printf 'case C: a stale pre-replacement persisted row survived\n' >&2
  exit 1
fi

if [[ ! -f $settings_file ]]; then
  printf 'case D: expected a real notifications.json settings file at %s\n' "$settings_file" >&2
  exit 1
fi
if ! grep -q '"dnd"' "$settings_file"; then
  printf 'case D: settings file missing the dnd key entirely\n' >&2
  exit 1
fi

if find "$state_dir" -maxdepth 1 -name '*.json' -exec grep -q 'Dismiss-E-marker' {} \; -print 2>/dev/null | grep -q .; then
  printf 'case E: dismissed popup unexpectedly still has a live popup file\n' >&2
  exit 1
fi
if ! grep -rq 'Dismiss-E-marker' "$history_dir" 2>/dev/null; then
  printf 'case E: dismissed popup was not archived into history\n' >&2
  exit 1
fi

if find "$state_dir" -maxdepth 1 -name '*.json' -exec grep -q 'Expire-F-marker' {} \; -print 2>/dev/null | grep -q .; then
  printf 'case F: expired popup unexpectedly still has a live popup file\n' >&2
  exit 1
fi
if ! grep -rq 'Expire-F-marker' "$history_dir" 2>/dev/null; then
  printf 'case F: expired popup was not archived into history\n' >&2
  exit 1
fi

if [[ -e $hostile_marker ]]; then
  printf 'case I: the hostile omarchy-exec hint was executed - marker file exists at %s\n' "$hostile_marker" >&2
  exit 1
fi
if grep -rq 'Hostile-I-marker' "$state_dir" 2>/dev/null && grep -rq '"exec"' "$state_dir" 2>/dev/null; then
  printf 'case I: persisted state for the hostile notification unexpectedly carries an exec field\n' >&2
  exit 1
fi


cat >"$harness1_dir/shell-part2.qml" <<'EOF'
import QtQuick
import Quickshell

ShellRoot {
  id: shellRoot

  Loader {
    id: serviceLoader
    source: Qt.resolvedUrl("fixture-notifications/Service.qml")
  }

  function fail(label, detail) {
    console.log("NOTIF_QML_FAIL", label, detail === undefined ? "" : JSON.stringify(detail))
    Qt.quit()
  }

  function check(condition, label, detail) {
    if (!condition) fail(label, detail)
  }

  property var service: null
  property var fake: null

  function waitFor(description, predicate, next) {
    var attempts = 0
    var poll = Qt.createQmlObject(
      'import QtQuick; Timer { interval: 20; repeat: true; running: true }',
      shellRoot, "poll-" + description)
    poll.triggered.connect(function() {
      attempts++
      if (predicate()) {
        poll.running = false
        poll.destroy()
        next()
        return
      }
      if (attempts >= 250) {
        poll.running = false
        poll.destroy()
        fail("timeout-" + description)
      }
    })
  }

  function queueDrained() {
    return service.popupFileQueue.length === 0 && !service.fakePopupFileProc.running
      && !service.fakeReadHistoryProc.running
  }

  property var kExpectedSummaries: []

  function runCases() {
    service = serviceLoader.item
    fake = service.fakeServer
    caseK()
  }

  function caseK() {
    // K. history replay: create more than 10 real history candidates
    // through the real queue/helper (DND-silenced, so each goes straight
    // to history), then replay - deterministic, newest <=10, no
    // executable state anywhere in the replayed rows.
    service.clearPopups()
    service.clearHistory()
    waitFor("K-cleared", queueDrained, function() {
      service.setDoNotDisturb(true)
      var total = 12
      var i = 0
      kExpectedSummaries = []
      // A small stagger (not a feature-timer sleep - see case F's comment
      // for that distinction) so each synthetic notification gets a
      // distinct Date.now() millisecond; back-to-back Qt.callLater sends
      // can otherwise land on the same millisecond and make "newest sent"
      // ambiguous by timestamp alone, independent of any real bug.
      var sendTimer = Qt.createQmlObject('import QtQuick; Timer { interval: 5; repeat: true; running: false }', shellRoot, "k-send-timer")
      sendTimer.triggered.connect(function() {
        if (i >= total) {
          sendTimer.running = false
          sendTimer.destroy()
          service.setDoNotDisturb(false)
          waitFor("K-history-built", queueDrained, doReplay)
          return
        }
        var summary = "History-K-" + i
        kExpectedSummaries.push(summary)
        fake.fakeNotify({ appName: "HistoryApp", summary: summary })
        i++
      })
      function sendNext() {
        sendTimer.running = true
      }
      function doReplay() {
        service.showRecentHistory()
        waitFor("K-replayed", function() { return service.popupModel.count > 0 }, function() {
          check(service.popupModel.count === 10, "K-replay-count-is-10", service.popupModel.count)
          for (var r = 0; r < service.popupModel.count; r++) {
            check(service.popupModel.get(r).exec === undefined, "K-no-exec-in-replay-row-" + r)
          }
          // Newest-first: the very last notification sent (index total-1)
          // must be the first replayed row.
          var newest = service.popupModel.get(0)
          check(newest.summary === kExpectedSummaries[total - 1], "K-newest-first", newest.summary)
          waitFor("K-settled", queueDrained, caseL)
        })
      }
      sendNext()
    })
  }

  function caseL() {
    // L. corrupt/torn persisted state: a valid entry, a torn/corrupt line,
    // and another valid entry - driven directly through the REAL
    // restorePopups(raw) function (the same one Component.onCompleted
    // calls), not a reimplementation of its parsing. The corrupt entry
    // must be skipped without losing either valid neighbor.
    service.clearPopups()
    waitFor("L-cleared", queueDrained, function() {
      // Recent, real timestamps - restorePopups() legitimately archives
      // (rather than restores) any entry whose configured duration has
      // already elapsed since its timestamp; a synthetic epoch-adjacent
      // timestamp would be correctly treated as long-expired and never
      // reach popupModel at all, which would test the wrong thing.
      var recentNow = Date.now()
      var validA = JSON.stringify({ id: 1, originalId: 111, app: "CorruptTestA", summary: "Valid-L-A", timestamp: recentNow - 2000 })
      var torn = '{not valid json at all'
      var validB = JSON.stringify({ id: 2, originalId: 222, app: "CorruptTestB", summary: "Valid-L-B", timestamp: recentNow - 1000 })
      var raw = validA + "\n" + torn + "\n" + validB + "\n"
      service.restorePopups(raw)
      waitFor("L-restored", function() { return service.popupModel.count === 2 }, function() {
        var summaries = [service.popupModel.get(0).summary, service.popupModel.get(1).summary]
        check(summaries.indexOf("Valid-L-A") !== -1, "L-valid-a-survives", summaries)
        check(summaries.indexOf("Valid-L-B") !== -1, "L-valid-b-survives", summaries)
        console.log("NOTIF_QML_PASS_PART2")
        Qt.quit()
      })
    })
  }

  Timer {
    id: readyPoll
    interval: 50
    repeat: true
    running: true
    property int attempts: 0
    onTriggered: {
      attempts++
      if (!serviceLoader.item) {
        if (attempts >= 100) {
          console.log("NOTIF_QML_FAIL", "service did not load")
          Qt.quit()
        }
        return
      }
      running = false
      runCases()
    }
  }
}
EOF

HOME="$test_root/home" XDG_RUNTIME_DIR="$test_root/runtime" QML2_IMPORT_PATH="$harness1_dir" \
  PATH="$test_root/bin:$PATH" QT_QPA_PLATFORM=offscreen timeout 30s "$quickshell" -n -p "$harness1_dir/shell-part2.qml" \
  >"$harness1_dir/quickshell-part2.log" 2>&1 &
quickshell1b_pid=$!
wait "$quickshell1b_pid" || true

if ! grep -Fq 'NOTIF_QML_PASS_PART2' "$harness1_dir/quickshell-part2.log"; then
  cat "$harness1_dir/quickshell-part2.log" >&2
  exit 1
fi


harness2_dir="$test_root/h2"
mkdir -p "$harness2_dir"
notifications_fixture_dir2="$harness2_dir/fixture-notifications"
setup_fixture "$notifications_fixture_dir2"

"$python" - "$notifications_fixture_dir2/Service.qml" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text()


def replace_once(text, old, new, label):
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected one pinned block, found {count}")
    return text.replace(old, new, 1)


service_old = "Item {\n  id: service\n"
service_new = (
    "Item {\n  id: service\n"
    "  property alias fakeServer: server\n"
    "  property alias fakePopupFileProc: popupFileProc\n"
    "  property alias fakeReadHistoryProc: readHistoryProc\n"
    "  property alias fakeRestorePopupsProc: restorePopupsProc\n"
)
text = replace_once(text, service_old, service_new, "service id/alias anchor")

panel_old = (
    "    PanelWindow {\n"
    "      id: popupWindow\n"
    "      required property var modelData\n"
    "      screen: modelData\n"
    "      visible: popupModel.count > 0\n"
    "\n"
    '      WlrLayershell.namespace: "omarchy-notifications"\n'
    "      WlrLayershell.layer: WlrLayer.Overlay\n"
    "      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None\n"
    "      exclusionMode: ExclusionMode.Ignore\n"
    '      color: "transparent"\n'
)
panel_new = (
    "    Item {\n"
    "      id: popupWindow\n"
    "      required property var modelData\n"
    "      visible: popupModel.count > 0\n"
)
text = replace_once(text, panel_old, panel_new, "popupWindow PanelWindow->Item")

mask_old = "      mask: Region { item: popupColumn }\n"
text = replace_once(text, mask_old, "", "popupWindow mask (layer-shell only)")

anchors_old = (
    "      anchors { top: true; bottom: true; left: true; right: true }\n"
    "\n"
)
text = replace_once(text, anchors_old, "", "popupWindow boolean-edge anchors (layer-shell only)")

server_old = (
    "  NotificationServer {\n"
    "    id: server\n"
    "    keepOnReload: false\n"
    "    imageSupported: true\n"
    "    actionsSupported: true\n"
    "    bodyMarkupSupported: true\n"
    "    bodyHyperlinksSupported: true\n"
    "    persistenceSupported: true\n"
    "\n"
    "    onNotification: function(notification) {\n"
    "      service.handleNotification(notification)\n"
    "    }\n"
    "  }\n"
)
server_new = '''  QtObject {
    id: server
    signal notification(var notification)
    onNotification: function(n) { service.handleNotification(n) }
    function fakeNotify(fields) { return 0 }
  }
'''
text = replace_once(text, server_old, server_new, "server NotificationServer->fake QtObject")

# Harness-2-only: fake the three state-persistence Process objects
# themselves. Every onExited/onRunningChanged handler body is reproduced
# byte-for-byte from the pinned generated source - only the underlying
# type changes from the real Quickshell Process (which needs a real OS
# process to toggle `running`) to a QtObject the test drives directly via
# fakeNormalExit/fakeFailedToStart/fakeReversedOrderExit. The real
# production functions these handlers call (finishPopupFileJob,
# reconcile*FailedToStart, runNextPopupFileJob) are untouched.
popup_file_proc_old = (
    "  Process {\n"
    "    id: popupFileProc\n"
    "    running: false\n"
    "    onExited: {\n"
    "      service.popupFileJobAwaitingResult = false\n"
    "      service.finishPopupFileJob()\n"
    "    }\n"
    "    onRunningChanged: {\n"
    "      if (!running && service.popupFileJobAwaitingResult) Qt.callLater(service.reconcilePopupFileJobFailedToStart)\n"
    "    }\n"
    "  }\n"
)
popup_file_proc_new = '''  QtObject {
    id: popupFileProc
    property bool running: false
    property var command: []
    signal exited(int exitCode, int exitStatus)
    onExited: {
      service.popupFileJobAwaitingResult = false
      service.finishPopupFileJob()
    }
    onRunningChanged: {
      if (!running && service.popupFileJobAwaitingResult) Qt.callLater(service.reconcilePopupFileJobFailedToStart)
    }
    function fakeNormalExit(exitCode) { popupFileProc.exited(exitCode, 0); popupFileProc.running = false }
    function fakeReversedOrderExit(exitCode) { popupFileProc.running = false; popupFileProc.exited(exitCode, 0) }
    function fakeFailedToStart() { popupFileProc.running = false }
  }
'''
text = replace_once(text, popup_file_proc_old, popup_file_proc_new, "popupFileProc Process->fake QtObject")

read_history_proc_old = (
    "  Process {\n"
    "    id: readHistoryProc\n"
    "    running: false\n"
    "    onExited: {\n"
    "      service.readHistoryAwaitingResult = false\n"
    "      service.runNextPopupFileJob()\n"
    "    }\n"
    "    onRunningChanged: {\n"
    "      if (!running && service.readHistoryAwaitingResult) Qt.callLater(service.reconcileReadHistoryFailedToStart)\n"
    "    }\n"
    "    stdout: StdioCollector {\n"
    "      waitForEnd: true\n"
    "      onStreamFinished: service.replayHistory(text)\n"
    "    }\n"
    "  }\n"
)
read_history_proc_new = '''  QtObject {
    id: readHistoryProc
    property bool running: false
    property var command: []
    signal exited(int exitCode, int exitStatus)
    onExited: {
      service.readHistoryAwaitingResult = false
      service.runNextPopupFileJob()
    }
    onRunningChanged: {
      if (!running && service.readHistoryAwaitingResult) Qt.callLater(service.reconcileReadHistoryFailedToStart)
    }
    function fakeFailedToStart() { readHistoryProc.running = false }
  }
'''
text = replace_once(text, read_history_proc_old, read_history_proc_new, "readHistoryProc Process->fake QtObject")

restore_popups_proc_old = (
    "  Process {\n"
    "    id: restorePopupsProc\n"
    "    running: false\n"
    "    onExited: {\n"
    "      service.restorePopupsAwaitingResult = false\n"
    "    }\n"
    "    onRunningChanged: {\n"
    "      if (!running && service.restorePopupsAwaitingResult) Qt.callLater(service.reconcileRestorePopupsFailedToStart)\n"
    "    }\n"
    "    stdout: StdioCollector {\n"
    "      waitForEnd: true\n"
    "      onStreamFinished: service.restorePopups(text)\n"
    "    }\n"
    "  }\n"
)
restore_popups_proc_new = '''  QtObject {
    id: restorePopupsProc
    property bool running: false
    property var command: []
    signal exited(int exitCode, int exitStatus)
    onExited: {
      service.restorePopupsAwaitingResult = false
    }
    onRunningChanged: {
      if (!running && service.restorePopupsAwaitingResult) Qt.callLater(service.reconcileRestorePopupsFailedToStart)
    }
    function fakeFailedToStart() { restorePopupsProc.running = false }
  }
'''
text = replace_once(text, restore_popups_proc_old, restore_popups_proc_new, "restorePopupsProc Process->fake QtObject")

path.write_text(text)
PY

cat >"$harness2_dir/shell.qml" <<'EOF'
import QtQuick
import Quickshell

ShellRoot {
  id: shellRoot

  Loader {
    id: serviceLoader
    source: Qt.resolvedUrl("fixture-notifications/Service.qml")
  }

  function fail(label, detail) {
    console.log("NOTIF_STRESS_FAIL", label, detail === undefined ? "" : JSON.stringify(detail))
    Qt.quit()
  }

  function check(condition, label, detail) {
    if (!condition) fail(label, detail)
  }

  property var service: null

  function waitFor(description, predicate, next) {
    var attempts = 0
    var poll = Qt.createQmlObject(
      'import QtQuick; Timer { interval: 10; repeat: true; running: true }',
      shellRoot, "poll-" + description)
    poll.triggered.connect(function() {
      attempts++
      if (predicate()) {
        poll.running = false
        poll.destroy()
        next()
        return
      }
      if (attempts >= 500) {
        poll.running = false
        poll.destroy()
        fail("timeout-" + description)
      }
    })
  }

  // Drains popupFileProc to a fully idle state (queue empty, not running,
  // awaitingResult cleared), synthetically failing to start whatever is
  // currently running on each tick - regardless of whether it is a job
  // this case itself enqueued or a leftover from something earlier (e.g.
  // clearPopups()'s own archive-popup call). Every case below that needs
  // a clean starting slate calls this first rather than assuming exactly
  // one job is ever in flight.
  function drainPopupFileQueue(description, next) {
    var attempts = 0
    var poll = Qt.createQmlObject('import QtQuick; Timer { interval: 10; repeat: true; running: true }', shellRoot, "drain-" + description)
    poll.triggered.connect(function() {
      attempts++
      // Checked before failing anything this tick - the real
      // reconciliation a fakeFailedToStart() triggers is deferred to a
      // later Qt.callLater turn, so awaitingResult must be re-checked on
      // a later tick, never assumed cleared in the same one.
      if (service.popupFileQueue.length === 0 && service.fakePopupFileProc.running === false
          && service.popupFileJobAwaitingResult === false) {
        poll.running = false
        poll.destroy()
        next()
        return
      }
      if (service.fakePopupFileProc.running === true) {
        service.fakePopupFileProc.fakeFailedToStart()
      }
      if (attempts > 200) {
        poll.running = false
        poll.destroy()
        fail("timeout-drain-" + description)
      }
    })
  }

  function runCases() {
    service = serviceLoader.item

    // M (restorePopupsProc leg): Component.onCompleted already started it
    // asynchronously (via Qt.callLater) - wait for it to actually be
    // running, then fail it to start.
    waitFor("M-restore-running", function() { return service.fakeRestorePopupsProc.running === true }, function() {
      service.fakeRestorePopupsProc.fakeFailedToStart()
      // Includes awaitingResult in the predicate itself (not a separate
      // check right after) - fakeFailedToStart() only flips `running`
      // synchronously; the real reconciliation that clears awaitingResult
      // is deferred to a later Qt.callLater turn.
      waitFor("M-restore-settled", function() {
        return service.fakeRestorePopupsProc.running === false && service.restorePopupsAwaitingResult === false
      }, caseMPopupFile)
    })
  }

  function caseMPopupFile() {
    // M (popupFileProc leg): a real enqueued job (via the real
    // enqueuePopupFileJob-backed sweepOrphanImages call) fails to start -
    // the awaiting flag clears and the queue advances exactly once, with
    // no autonomous retry of the same job. Component.onCompleted's own
    // startup sweepOrphanImages() call may still be queued or in flight
    // ahead of this explicit one, so this drains the queue in a loop
    // (failing to start whatever is currently running each tick) rather
    // than assuming exactly one job is ever in flight - the invariant
    // under test (awaiting-result clears, queue reaches zero, no hang) is
    // the same either way.
    service.sweepOrphanImages()
    drainPopupFileQueue("M-popupfile", caseMReadHistory)
  }

  function caseMReadHistory() {
    // M (readHistoryProc leg): a failed history read degrades to the
    // "no recent notifications" placeholder (replayHistory("")) rather
    // than leaving the replay hanging or crashing, and the shared queue
    // still advances afterward.
    service.clearPopups()
    service.showRecentHistory()
    waitFor("M-readhistory-running", function() { return service.fakeReadHistoryProc.running === true }, function() {
      service.fakeReadHistoryProc.fakeFailedToStart()
      waitFor("M-readhistory-settled", function() { return service.popupModel.count === 1 }, function() {
        check(service.popupModel.get(0).originalId === -1, "M-readhistory-degrades-to-placeholder")
        check(service.readHistoryAwaitingResult === false, "M-readhistory-awaiting-cleared")
        service.clearPopups()
        caseN()
      })
    })
  }

  property int nDoneCount: 0

  function caseN() {
    // N. hostile signal ordering: runningChanged (running=false) fires
    // BEFORE exited(), the reverse of the pinned normal-exit ordering.
    // onExited must still clear the awaiting flag and advance the queue
    // exactly once; the deferred Qt.callLater reconciliation scheduled by
    // the (now already-handled) runningChanged must become a no-op, not a
    // second, duplicate completion.
    //
    // Drains first: caseMReadHistory's own clearPopups() call may have
    // enqueued (and possibly already started) an archive-popup job of its
    // own, which would otherwise be the thing "N-running" observes
    // instead of this case's own enqueued job.
    drainPopupFileQueue("N-pre", function() {
    nDoneCount = 0
    service.enqueuePopupFileJob(["omanixy-notification-state", "sweep-images"], function() { nDoneCount++ })
    waitFor("N-running", function() { return service.fakePopupFileProc.running === true }, function() {
      service.fakePopupFileProc.fakeReversedOrderExit(0)
      // Give the deferred Qt.callLater reconciliation a chance to run (it
      // must find awaitingResult already false and do nothing) before
      // checking the done callback fired exactly once, not twice.
      var settleTicks = 0
      var settle = Qt.createQmlObject('import QtQuick; Timer { interval: 10; repeat: true; running: true }', shellRoot, "n-settle")
      settle.triggered.connect(function() {
        settleTicks++
        if (settleTicks < 10) return
        settle.running = false
        settle.destroy()
        check(nDoneCount === 1, "N-done-exactly-once", nDoneCount)
        check(service.popupFileJobAwaitingResult === false, "N-awaiting-cleared")
        check(service.popupFileQueue.length === 0 && service.fakePopupFileProc.running === false, "N-queue-settled")
        caseNNormalOrder()
      })
    })
    })
  }

  function caseNNormalOrder() {
    // N (control case): the pinned normal ordering (exited() then
    // runningChanged) must also complete exactly once, proving the
    // reconciliation is ordering-independent in both directions.
    drainPopupFileQueue("N-normal-pre", function() {
    nDoneCount = 0
    service.enqueuePopupFileJob(["omanixy-notification-state", "sweep-images"], function() { nDoneCount++ })
    waitFor("N-normal-running", function() { return service.fakePopupFileProc.running === true }, function() {
      service.fakePopupFileProc.fakeNormalExit(0)
      var settleTicks = 0
      var settle = Qt.createQmlObject('import QtQuick; Timer { interval: 10; repeat: true; running: true }', shellRoot, "n-normal-settle")
      settle.triggered.connect(function() {
        settleTicks++
        if (settleTicks < 10) return
        settle.running = false
        settle.destroy()
        check(nDoneCount === 1, "N-normal-done-exactly-once", nDoneCount)
        check(service.popupFileQueue.length === 0 && service.fakePopupFileProc.running === false, "N-normal-queue-settled")
        caseO()
      })
    })
    })
  }

  property int oProcessed: 0
  property int oTotal: 100

  function caseO() {
    // O. 100-failure stress: drive 100 real enqueued jobs through the
    // REAL production runNextPopupFileJob/finishPopupFileJob/
    // reconcilePopupFileJobFailedToStart, each one synthetically failing
    // to start. Must terminate (no runaway loop), consume the queue to
    // exactly zero, and never double-process a job.
    drainPopupFileQueue("O-pre", function() {
    oProcessed = 0
    var doneCount = 0
    for (var i = 0; i < oTotal; i++) {
      service.enqueuePopupFileJob(["omanixy-notification-state", "sweep-images"], function() { doneCount++ })
    }
    var poll = Qt.createQmlObject('import QtQuick; Timer { interval: 5; repeat: true; running: true }', shellRoot, "o-poll")
    poll.triggered.connect(function() {
      // Exit condition checked BEFORE failing anything this tick, and
      // includes awaitingResult: fakeFailedToStart() only flips `running`
      // synchronously and defers the real reconciliation (which runs the
      // done callback and advances the queue) to a later Qt.callLater
      // turn - checking doneCount/queue in the very same tick that
      // triggered the last failure would race that deferred completion.
      if (service.popupFileQueue.length === 0 && service.fakePopupFileProc.running === false
          && service.popupFileJobAwaitingResult === false) {
        poll.running = false
        poll.destroy()
        check(oProcessed === oTotal, "O-processed-exactly-total", oProcessed)
        check(doneCount === oTotal, "O-done-callbacks-exactly-total", doneCount)
        check(service.popupFileQueue.length === 0, "O-queue-empty")
        console.log("NOTIF_STRESS_PASS")
        Qt.quit()
        return
      }
      if (service.fakePopupFileProc.running === true) {
        oProcessed++
        service.fakePopupFileProc.fakeFailedToStart()
      }
      // Safety margin against a genuine runaway/self-requeue loop: real
      // production code must consume exactly oTotal jobs, never more.
      if (oProcessed > oTotal + 10) {
        poll.running = false
        poll.destroy()
        fail("O-runaway-loop", oProcessed)
      }
    })
    })
  }

  Timer {
    id: readyPoll
    interval: 50
    repeat: true
    running: true
    property int attempts: 0
    onTriggered: {
      attempts++
      if (!serviceLoader.item) {
        if (attempts >= 100) {
          console.log("NOTIF_STRESS_FAIL", "service did not load")
          Qt.quit()
        }
        return
      }
      running = false
      runCases()
    }
  }
}
EOF

ln -s "$compat_root/shell" "$harness2_dir/qs"
cp -R "$compat_root/shell/Commons" "$harness2_dir/Commons"
cp -R "$compat_root/shell/Ui" "$harness2_dir/Ui"
chmod -R u+w "$harness2_dir/Commons" "$harness2_dir/Ui"

mkdir -p "$test_root/home2" "$test_root/runtime2"
HOME="$test_root/home2" XDG_RUNTIME_DIR="$test_root/runtime2" QML2_IMPORT_PATH="$harness2_dir" \
  PATH="$test_root/bin:$PATH" QT_QPA_PLATFORM=offscreen timeout 30s "$quickshell" -n -p "$harness2_dir" \
  >"$harness2_dir/quickshell.log" 2>&1 &
quickshell2_pid=$!
wait "$quickshell2_pid" || true

if ! grep -Fq 'NOTIF_STRESS_PASS' "$harness2_dir/quickshell.log"; then
  cat "$harness2_dir/quickshell.log" >&2
  exit 1
fi

printf '%s\n' 'notifications QML behavior checks passed'
