#!/usr/bin/env bash
# Real generated-QML behavior test for the adapted notifications Service.qml,
# following the same offscreen Quickshell pattern as
# test/security-polkit-qml-behavior.sh.
#
# The production source under test is the real, already-patched
# shell/plugins/notifications/{Service.qml,NotificationLogic.js} from the
# built notification-daemon-enabled runtime - not a hand-authored
# reimplementation. Two mechanical, test-harness-only transforms are applied
# on top of it, exactly as permitted by the Layer-7 spec: the popup
# PanelWindow -> Item (a real PanelWindow needs a Wayland layer-shell
# surface no offscreen environment provides), and the real
# NotificationServer {} listener -> an inline, deterministic fake QtObject
# the harness drives directly (the real one needs a live D-Bus session bus,
# which the exact D-Bus ownership/registration ABI itself is separately,
# statically proven by test/security-notifications-quickshell-contract.sh
# against the pinned Quickshell source - not re-proven live here). Both
# transforms are exact-count replacements that fail closed on drift.
#
# Unlike the fake NotificationServer, the state-persistence Process calls
# are NOT faked: the real omanixy-notification-state adapter runs against a
# real temporary HOME, so popup/history files this test inspects afterward
# are genuine adapter output, not a stand-in for it.
set -euo pipefail

compat_root=${1:?notification-daemon-enabled compatibility root required}
quickshell=${2:?selected Quickshell executable required}
notification_state_adapter=${3:?adapters/notification-state.bash path required}
python=${PYTHON:-python3}

test_root=$(mktemp -d)
trap 'chmod -R u+w "$test_root" 2>/dev/null || true; rm -rf "$test_root"' EXIT
mkdir -p "$test_root/home" "$test_root/runtime" "$test_root/bin"

notifications_fixture_dir="$test_root/fixture-notifications"
mkdir -p "$notifications_fixture_dir/components"
cp "$compat_root/shell/plugins/notifications/Service.qml" "$notifications_fixture_dir/Service.qml"
cp "$compat_root/shell/plugins/notifications/NotificationLogic.js" "$notifications_fixture_dir/NotificationLogic.js"
cp "$compat_root/shell/plugins/notifications/components/NotificationCard.qml" "$notifications_fixture_dir/components/NotificationCard.qml"
chmod u+w "$notifications_fixture_dir/Service.qml" "$notifications_fixture_dir/NotificationLogic.js"

# Harness-only: Service.qml's `import "components"` relies on the real
# PluginRegistry's own plugin-loading machinery to resolve as a directory
# import; loading Service.qml standalone through a bare Loader (as this
# harness does) needs an explicit qmldir to resolve the same sibling
# directory the same way.
cat >"$notifications_fixture_dir/components/qmldir" <<'EOF'
module fixture-notifications.components
NotificationCard 1.0 NotificationCard.qml
EOF

# A real omanixy-notification-state on PATH, not a fake - the adapted
# Service.qml's Process calls hit real bash/coreutils against a real
# temporary HOME. The Nix build sandbox has no /usr/bin/env, so the
# shebang is rewritten to the real, absolute bash path actually in PATH -
# the same fix test/security-notifications-state.sh's own probe_script uses.
real_bash=$(command -v bash)
cat >"$test_root/bin/omanixy-notification-state" <<EOF
#!/usr/bin/env bash
set -euo pipefail
source "$notification_state_adapter"
notification_state "\$@"
EOF
chmod +x "$test_root/bin/omanixy-notification-state"
sed -i "1c#!$real_bash" "$test_root/bin/omanixy-notification-state"

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


# Harness-only: expose the fake server to the offscreen driver script.
service_old = "Item {\n  id: service\n"
service_new = (
    "Item {\n  id: service\n"
    "  property alias fakeServer: server\n"
    "  property alias fakePopupFileProc: popupFileProc\n"
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
# syntax (anchor to a screen edge) is not the standard Item anchors API
# (which expects AnchorLine values) and fails to parse against a plain
# Item. popupWindow needs no anchors of its own for this harness - only to
# exist as a valid parent for popupColumn's real Item anchors below it.
anchors_old = (
    "      anchors { top: true; bottom: true; left: true; right: true }\n"
    "\n"
)
text = replace_once(text, anchors_old, "", "popupWindow boolean-edge anchors (layer-shell only)")

# Harness-only: the real NotificationServer needs a live D-Bus session bus
# to register against. Replaced with an inline QtObject exposing the
# identical signal surface this file actually reads (a "notification"
# signal feeding the unmodified onNotification: handler) plus a fakeNotify
# driver function building deterministic fake Notification-shaped QtObjects
# - real QtObject property signals (summaryChanged etc.), a real actions
# array, a real closed signal, and tracked/expire/dismiss semantics that
# mirror the pinned Quickshell Notification ABI closely enough to exercise
# every handler in this file unmodified.
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

cat >"$test_root/shell.qml" <<'EOF'
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
      'import QtQuick; Timer { interval: 50; repeat: true; running: true }',
      shellRoot, "poll-" + description)
    poll.triggered.connect(function() {
      attempts++
      if (predicate()) {
        poll.running = false
        poll.destroy()
        next()
        return
      }
      if (attempts >= 100) {
        poll.running = false
        poll.destroy()
        fail("timeout-" + description)
      }
    })
  }

  function runCases() {
    service = serviceLoader.item
    fake = service.fakeServer

    // A. an ordinary notification creates exactly one popup, with no exec
    // role anywhere on the row (the historical omarchy-exec hint must never
    // survive into persisted/model state under any name).
    fake.fakeNotify({ appName: "TestApp", summary: "Hello", hints: { "omarchy-exec": "touch /tmp/pwned" } })
    waitFor("A-popup-created", function() { return service.popupModel.count === 1 }, function() {
      var row = service.popupModel.get(0)
      check(row.app === "TestApp", "A-app", row.app)
      check(row.summary === "Hello", "A-summary", row.summary)
      check(row.exec === undefined, "A-no-exec-role", row.exec)
      caseB()
    })
  }

  function caseB() {
    // B. DND suppresses the popup and records it straight into history
    // instead (no live toast for a silenced notification).
    service.setDoNotDisturb(true)
    var beforeCount = service.popupModel.count
    fake.fakeNotify({ appName: "SilencedApp", summary: "Silenced" })
    // A silenced notification never becomes a popup - count must not grow.
    check(service.popupModel.count === beforeCount, "B-no-new-popup")
    service.setDoNotDisturb(false)
    caseG()
  }

  function caseG() {
    // G. a live "default" FDO action invokes exactly once, and only that -
    // never a shell command, never a compositor-focus fallback.
    var invokedCount = 0
    var id = fake.fakeNotify({
      appName: "ActionApp",
      summary: "Has action",
      actions: [{ identifier: "default", invoke: function() { invokedCount++ } }]
    })
    waitFor("G-popup-created", function() { return service.popupModel.count >= 1 && service.popupModel.get(0).originalId === id }, function() {
      service.invokePopupDefault(0)
      check(invokedCount === 1, "G-invoked-once", invokedCount)
      caseH()
    })
  }

  function caseH() {
    // H. no live "default" action: invoking performs no external execution
    // and no error - the popup is simply dismissed.
    var id = fake.fakeNotify({ appName: "NoActionApp", summary: "No action", actions: [] })
    waitFor("H-popup-created", function() { return service.popupModel.count >= 1 && service.popupModel.get(0).originalId === id }, function() {
      var countBefore = service.popupModel.count
      service.invokePopupDefault(0)
      check(service.popupModel.count === countBefore - 1, "H-dismissed-not-crashed")
      caseJ()
    })
  }

  function caseJ() {
    // J. a restored row (isRestoredRow) performs NO action execution even
    // when it happens to carry a live-looking actions array (it never
    // would in practice - liveRefs has no entry for it - but this proves
    // invokePopupDefault never resolves a restored row against liveRefs by
    // coincidental id reuse).
    // popupFileName is imageStem(row) + ".json", and imageStem is
    // "<timestamp>-<originalId>" - the key must match that exactly, not the
    // row's own "id" field.
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
    caseK()
  }

  function caseK() {
    // K. real state persistence: wait for every queued popup-file job
    // (from cases A, G, H, both fakeNotify calls) to actually finish
    // against the real omanixy-notification-state adapter before quitting,
    // so the on-disk assertions the wrapper script runs afterward observe
    // real, completed adapter output rather than a race.
    waitFor("K-queue-drained", function() {
      return service.popupFileQueue.length === 0 && !service.fakePopupFileProc.running
    }, function() {
      console.log("NOTIF_QML_PASS")
      Qt.quit()
    })
  }

  Timer {
    id: readyPoll
    interval: 100
    repeat: true
    running: true
    property int attempts: 0
    onTriggered: {
      attempts++
      if (!serviceLoader.item) {
        if (attempts >= 50) {
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

ln -s "$compat_root/shell" "$test_root/qs"
cp -R "$compat_root/shell/Commons" "$test_root/Commons"
cp -R "$compat_root/shell/Ui" "$test_root/Ui"
chmod -R u+w "$test_root/Commons" "$test_root/Ui"

HOME="$test_root/home" XDG_RUNTIME_DIR="$test_root/runtime" QML2_IMPORT_PATH="$test_root" \
  PATH="$test_root/bin:$PATH" QT_QPA_PLATFORM=offscreen timeout 15s "$quickshell" -n -p "$test_root" \
  >"$test_root/quickshell.log" 2>&1 &
quickshell_pid=$!
wait "$quickshell_pid" || true

if ! grep -Fq 'NOTIF_QML_PASS' "$test_root/quickshell.log"; then
  cat "$test_root/quickshell.log" >&2
  exit 1
fi

# Real, on-disk proof the popup persistence job from case A actually ran
# against the real adapter: the file exists, and it structurally cannot
# contain an exec field.
popup_dir="$test_root/home/.local/state/omarchy/notifications"
popup_file=$(find "$popup_dir" -maxdepth 1 -name '*.json' 2>/dev/null | head -1)
if [[ -z $popup_file ]]; then
  printf 'expected a real persisted popup file under %s, found none\n' "$popup_dir" >&2
  exit 1
fi
if grep -q '"exec"' "$popup_file"; then
  printf 'persisted popup file unexpectedly contains an exec field: %s\n' "$popup_file" >&2
  cat "$popup_file" >&2
  exit 1
fi
grep -q 'touch /tmp/pwned' "$popup_file" && {
  printf 'the omarchy-exec hint value leaked into persisted state under some other field\n' >&2
  exit 1
}

printf '%s\n' 'notifications QML behavior checks passed'
