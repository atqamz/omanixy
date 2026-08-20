#!/usr/bin/env bash
# Real generated-QML behavior test for the adapted PolkitAgent.qml, following
# the same offscreen Quickshell pattern as test/qml-patch-behavior.sh.
#
# The production source under test is the real, already-patched
# shell/plugins/polkit/PolkitAgent.qml from the built polkit-agent-enabled
# runtime - not a hand-authored reimplementation. Only two mechanical,
# test-harness-only transforms are applied on top of it, exactly as
# permitted by the Layer-5 spec: PanelWindow -> Item (a real PanelWindow
# needs a Wayland layer-shell surface no offscreen environment provides,
# mirroring qml-patch-behavior.sh's Bar.qml handling), and the real
# PolkitAgent {} native listener object -> an inline, deterministic fake
# QtObject the harness drives directly (the real one needs a live polkit
# D-Bus daemon). Both transforms are exact-count replacements that fail
# closed on drift, exactly like the production patcher - this is not a
# best-effort sed pass. The fake is defined inline (rather than as a
# separate sibling .qml file) because Quickshell's engine does not
# implicitly register same-directory QML files as types.
set -euo pipefail

compat_root=${1:?polkit-agent-enabled compatibility root required}
quickshell=${2:?selected Quickshell executable required}
python=${PYTHON:-python3}

test_root=$(mktemp -d)
trap 'chmod -R u+w "$test_root" 2>/dev/null || true; rm -rf "$test_root"' EXIT
mkdir -p "$test_root/home" "$test_root/runtime"

polkit_fixture_dir="$test_root/fixture-polkit"
mkdir -p "$polkit_fixture_dir"
cp "$compat_root/shell/plugins/polkit/PolkitAgent.qml" "$polkit_fixture_dir/PolkitAgent.qml"
cp "$compat_root/shell/plugins/polkit/PolkitModel.js" "$polkit_fixture_dir/PolkitModel.js"
chmod u+w "$polkit_fixture_dir/PolkitAgent.qml" "$polkit_fixture_dir/PolkitModel.js"

"$python" - "$polkit_fixture_dir/PolkitAgent.qml" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text()


def replace_once(text, old, new, label):
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected one pinned block, found {count}")
    return text.replace(old, new, 1)


# Harness-only: expose the fake listener and the password field to the
# offscreen driver script. Neither alias exists in the reviewed production
# source; both are injected here, fail-closed on drift, same as the real
# patcher.
root_old = "Item {\n  id: root\n"
root_new = (
    "Item {\n  id: root\n"
    "  property alias fakeAgent: polkitAgent\n"
    "  property alias fakePasswordInput: passwordInput\n"
)
text = replace_once(text, root_old, root_new, "root id/alias anchor")

# Harness-only: PanelWindow needs a real Wayland layer-shell surface, which
# no offscreen environment provides. A plain Item preserves every property
# the rest of the file actually reads (visible, width, height).
panel_old = (
    "  PanelWindow {\n"
    "    id: panel\n"
    "    visible: root.dialogVisible\n"
    '    anchors { top: true; bottom: true; left: true; right: true }\n'
    '    color: "transparent"\n'
    '    WlrLayershell.namespace: "omarchy-polkit"\n'
    "    WlrLayershell.layer: WlrLayer.Overlay\n"
    "    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive\n"
    "    exclusionMode: ExclusionMode.Ignore\n"
)
panel_new = (
    "  Item {\n"
    "    id: panel\n"
    "    visible: root.dialogVisible\n"
    "    width: 400\n"
    "    height: 300\n"
)
text = replace_once(text, panel_old, panel_new, "panel PanelWindow->Item")

# Harness-only: the real PolkitAgent listener needs a live polkit D-Bus
# daemon to register against, which no offscreen test environment provides.
# Replaced with an inline QtObject exposing the identical property/signal
# surface this file actually reads (isActive, flow, path, isRegistered,
# authenticationRequestStarted) plus a small set of fakeXxx() driver
# functions, so every downstream handler in this file is exercised
# unmodified. The three onXxxChanged handlers are preserved verbatim.
agent_old = (
    "  PolkitAgent {\n"
    "    id: polkitAgent\n"
    '    path: "/org/omarchy/PolkitAgent"\n'
    "\n"
    "    onAuthenticationRequestStarted: root.beginFlow()\n"
    "    onIsActiveChanged: {\n"
    "      if (isActive) root.syncFromFlow()\n"
    "      else if (!root.closing) root.resetSnapshot()\n"
    "    }\n"
    "    onIsRegisteredChanged: {\n"
    '      if (isRegistered) console.log("omarchy polkit agent registered")\n'
    '      else console.warn("omarchy polkit agent is not registered; another agent may be running")\n'
    "    }\n"
    "  }\n"
)
agent_new = '''  QtObject {
    id: polkitAgent
    property string path: "/org/omarchy/PolkitAgent"
    property bool isRegistered: true
    property bool isActive: false
    property var flow: null

    signal authenticationRequestStarted()

    onAuthenticationRequestStarted: root.beginFlow()
    onIsActiveChanged: {
      if (isActive) root.syncFromFlow()
      else if (!root.closing) root.resetSnapshot()
    }
    onIsRegisteredChanged: {
      if (isRegistered) console.log("omarchy polkit agent registered")
      else console.warn("omarchy polkit agent is not registered; another agent may be running")
    }

    property QtObject _flowObj: QtObject {
      property string message: ""
      property string inputPrompt: ""
      property bool isResponseRequired: false
      property bool responseVisible: false
      property bool failed: false
      property string supplementaryMessage: ""

      property int submitCount: 0
      property string lastSubmittedValue: ""
      property int cancelCount: 0

      signal authenticationFailed()
      signal authenticationSucceeded()
      signal authenticationRequestCancelled()

      // Mirrors the pinned Quickshell AuthFlow::submit ABI exactly:
      // submitting a response clears isResponseRequired/inputPrompt/
      // responseVisible immediately, before any PAM round-trip outcome is
      // known.
      function submit(value) {
        submitCount += 1
        lastSubmittedValue = value
        isResponseRequired = false
        inputPrompt = ""
        responseVisible = false
      }

      // Mirrors AuthFlow::cancelAuthenticationRequest: marks the
      // cancellation but - unlike the daemon-initiated path - never itself
      // emits authenticationRequestCancelled (only PolkitAgentImpl's own
      // cancel path does that; see fakeAuthenticationRequestCancelledByDaemon
      // below).
      function cancelAuthenticationRequest() {
        cancelCount += 1
      }
    }

    function beginRequest(message) {
      _flowObj.message = message
      _flowObj.inputPrompt = ""
      _flowObj.isResponseRequired = false
      _flowObj.responseVisible = false
      _flowObj.failed = false
      _flowObj.supplementaryMessage = ""
      flow = _flowObj
      isActive = true
      authenticationRequestStarted()
    }

    function requireResponse(prompt, visible) {
      _flowObj.inputPrompt = prompt
      _flowObj.responseVisible = !!visible
      _flowObj.isResponseRequired = true
    }

    // Mirrors AuthFlow::completed's ordinary-failure branch: emits
    // authenticationFailed, then behaves as if a fresh session started for
    // the same request/identity (isResponseRequired etc. reset), matching
    // the pinned ABI's own "no restart loop, but a fresh session" semantics.
    function fakeAuthenticationFailed() {
      _flowObj.failed = true
      _flowObj.authenticationFailed()
      _flowObj.isResponseRequired = false
      _flowObj.inputPrompt = ""
      _flowObj.responseVisible = false
    }

    function fakeAuthenticationSucceeded() {
      _flowObj.authenticationSucceeded()
      isActive = false
    }

    function fakeAuthenticationRequestCancelledByDaemon() {
      _flowObj.authenticationRequestCancelled()
      isActive = false
    }
  }
'''
text = replace_once(text, agent_old, agent_new, "polkitAgent PolkitAgent->fake QtObject")

path.write_text(text)
PY

cat > "$test_root/shell.qml" <<'EOF'
import QtQuick
import Quickshell

ShellRoot {
  id: shellRoot

  Loader {
    id: agentLoader
    source: Qt.resolvedUrl("fixture-polkit/PolkitAgent.qml")
  }

  function fail(label, detail) {
    console.log("POLKIT_QML_FAIL", label, detail === undefined ? "" : JSON.stringify(detail))
    Qt.quit()
  }

  function check(condition, label, detail) {
    if (!condition) fail(label, detail)
  }

  function runCases() {
    var agent = agentLoader.item
    var fake = agent.fakeAgent

    // A. inactive: dialog hidden/reset.
    check(agent.dialogVisible === false, "A-dialogVisible-initial", agent.dialogVisible)
    check(agent.closing === false, "A-closing-initial")

    // B. request begins without response required: generic waiting mode,
    // no password submit, no fingerprint-specific state anywhere reachable.
    fake.beginRequest("Authentication is needed to run `/usr/bin/test-action` as the super user")
    check(agent.dialogVisible === true, "B-dialogVisible")
    check(agent.waitingForAuthentication === true, "B-waitingForAuthentication")
    check(agent.responseRequired === false, "B-responseRequired")
    check(agent.submitted === false, "B-submitted")

    // C. flow switches isResponseRequired=true: input mode becomes
    // available; prompt snapshot tracks flow; responseVisible follows flow.
    fake.requireResponse("Password:", false)
    check(agent.responseRequired === true, "C-responseRequired")
    check(agent.waitingForAuthentication === false, "C-waitingForAuthentication")
    check(agent.currentPrompt === "Password:", "C-currentPrompt", agent.currentPrompt)
    check(agent.responseVisible === false, "C-responseVisible")

    // D. submit: exact entered string passed once to flow.submit(); input
    // cleared; submitted state set.
    agent.fakePasswordInput.text = "hunter2"
    agent.submitResponse()
    check(fake.flow.submitCount === 1, "D-submitCount", fake.flow.submitCount)
    check(fake.flow.lastSubmittedValue === "hunter2", "D-lastSubmittedValue", fake.flow.lastSubmittedValue)
    check(agent.fakePasswordInput.text === "", "D-inputCleared")
    check(agent.submitted === true, "D-submitted")

    // E. Escape/cancel: flow.cancelAuthenticationRequest() called exactly
    // once; input cleared; closing state entered.
    agent.cancelRequest()
    check(fake.flow.cancelCount === 1, "E-cancelCount", fake.flow.cancelCount)
    check(agent.fakePasswordInput.text === "", "E-inputCleared")
    check(agent.closing === true, "E-closing")

    // F. authentication failure: no authorization success path invoked;
    // input cleared; failure feedback set; retry presentation remains
    // bounded by the existing non-repeating errorTimer (interval 1200ms,
    // repeat: false in the production source - not re-verified by waiting
    // out the timer here, since this is a state-machine proof, not a timing
    // proof).
    fake.beginRequest("Authentication is needed to run `/usr/bin/other-action` as the super user")
    fake.requireResponse("Password:", false)
    agent.fakePasswordInput.text = "wrongpass"
    agent.submitResponse()
    fake.fakeAuthenticationFailed()
    check(agent.closing === false, "F-not-closing")
    check(agent.errorFlash === true, "F-errorFlash")
    check(agent.submitted === false, "F-submitted-cleared")
    check(agent.fakePasswordInput.text === "", "F-inputCleared")

    // G. authentication success: closing state entered; no duplicate submit.
    fake.beginRequest("Authentication is needed to run `/usr/bin/success-action` as the super user")
    var submitCountBeforeSuccess = fake.flow.submitCount
    fake.fakeAuthenticationSucceeded()
    check(agent.closing === true, "G-closing")
    check(fake.flow.submitCount === submitCountBeforeSuccess, "G-no-duplicate-submit")

    // H. request cancelled (by the daemon): closing state entered.
    fake.beginRequest("Authentication is needed to run `/usr/bin/daemon-cancel-action` as the super user")
    fake.fakeAuthenticationRequestCancelledByDaemon()
    check(agent.closing === true, "H-closing")

    console.log("POLKIT_QML_PASS")
    Qt.quit()
  }

  Timer {
    id: readyPoll
    interval: 100
    repeat: true
    running: true
    property int attempts: 0
    onTriggered: {
      attempts++
      if (!agentLoader.item) {
        if (attempts >= 50) {
          console.log("POLKIT_QML_FAIL", "agent did not load")
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
  QT_QPA_PLATFORM=offscreen timeout 10s "$quickshell" -n -p "$test_root" \
  >"$test_root/quickshell.log" 2>&1 &
quickshell_pid=$!
wait "$quickshell_pid" || true

if ! grep -Fq 'POLKIT_QML_PASS' "$test_root/quickshell.log"; then
  cat "$test_root/quickshell.log" >&2
  exit 1
fi

printf '%s\n' 'polkit QML behavior checks passed'
