#!/usr/bin/env bash
# Real generated-QML behavior test for the adapted idle Service.qml,
# following the same offscreen Quickshell pattern as
# test/security-polkit-qml-behavior.sh.
#
# The production source under test is the real, already-patched
# shell/plugins/services/idle/Service.qml from the built idle-enabled
# runtime - not a hand-authored reimplementation. Section 41 permits the
# harness to replace IdleMonitor/Process with deterministic fakes; three
# mechanical, exact-count, fail-closed-on-drift transforms do exactly that:
# the real IdleMonitor (needs a live Wayland ext-idle-notify-v1 compositor)
# and the three real Process objects (lockProcess, stayAwakeStateProbe,
# stayAwakeStateWriter - each would otherwise try to exec a real binary) all
# become plain QtObject fakes exposing the identical property/signal
# surface this file actually reads, plus small fakeXxx() driver functions.
# Every onExited/onIsIdleChanged handler body is preserved verbatim. The
# FileView directory watcher and the real lockRetryTimer are left
# untouched - a Timer needs no live backend, and the harness stops/replaces
# its effect manually instead of waiting out the real 1s interval.
set -euo pipefail

compat_root=${1:?idle-enabled compatibility root required}
quickshell=${2:?selected Quickshell executable required}
python=${PYTHON:-python3}

test_root=$(mktemp -d)
trap 'chmod -R u+w "$test_root" 2>/dev/null || true; rm -rf "$test_root"' EXIT
mkdir -p "$test_root/home" "$test_root/runtime"

idle_fixture_dir="$test_root/fixture-idle"
mkdir -p "$idle_fixture_dir"
cp "$compat_root/shell/plugins/services/idle/Service.qml" "$idle_fixture_dir/Service.qml"
cp "$compat_root/shell/plugins/services/idle/IdleModel.js" "$idle_fixture_dir/IdleModel.js"
cp "$compat_root/shell/plugins/services/idle/IdlePolicy.js" "$idle_fixture_dir/IdlePolicy.js"
chmod u+w "$idle_fixture_dir/Service.qml"

"$python" - "$idle_fixture_dir/Service.qml" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text()


def replace_once(text, old, new, label):
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected one pinned block, found {count}")
    return text.replace(old, new, 1)


# Harness-only: expose the fakeable children so the offscreen driver script
# can inspect and drive them. None of these aliases exist in the reviewed
# production source; they are injected here, fail-closed on drift, exactly
# like the real patcher.
shell_old = "  property var shell: null\n"
shell_new = shell_old + (
    "  property alias fakeIdleMonitor: idleMonitor\n"
    "  property alias fakeLockProcess: lockProcess\n"
    "  property alias fakeStayAwakeProbe: stayAwakeStateProbe\n"
    "  property alias fakeStayAwakeWriter: stayAwakeStateWriter\n"
    "  property alias fakeRetryTimer: lockRetryTimer\n"
    "  property alias fakeIpc: idleIpc\n"
)
text = replace_once(text, shell_old, shell_new, "root shell property anchor")

# Harness-only: the real IdleMonitor needs a live Wayland ext-idle-notify-v1
# compositor, which no offscreen test environment provides. Replaced with a
# QtObject exposing the identical isIdle property/signal surface this file
# actually reads, plus fakeSetIdle() to drive it.
idle_monitor_old = (
    "  IdleMonitor {\n"
    "    id: idleMonitor\n"
    "    enabled: root.idleEnabled\n"
    "    timeout: root.lockTimeoutSeconds\n"
    "    respectInhibitors: true\n"
    "    onIsIdleChanged: root.handleIdleChanged()\n"
    "  }\n"
)
idle_monitor_new = (
    "  QtObject {\n"
    "    id: idleMonitor\n"
    "    property bool enabled: root.idleEnabled\n"
    "    property int timeout: root.lockTimeoutSeconds\n"
    "    property bool respectInhibitors: true\n"
    "    property bool isIdle: false\n"
    "    onIsIdleChanged: root.handleIdleChanged()\n"
    "    function fakeSetIdle(value) { isIdle = value }\n"
    "  }\n"
)
text = replace_once(text, idle_monitor_old, idle_monitor_new, "idleMonitor IdleMonitor->fake QtObject")

# Harness-only: the real lockProcess would exec ["omanixy-shell", "lock",
# "lock"], which no offscreen test environment can run deterministically.
lock_process_old = (
    "  Process {\n"
    "    id: lockProcess\n"
    '    stdout: StdioCollector { id: lockProcessOut; waitForEnd: true }\n'
    '    onExited: function(exitCode, exitStatus) { root.handleLockExited(exitCode, String(lockProcessOut.text || "")) }\n'
    "  }\n"
)
lock_process_new = (
    "  QtObject {\n"
    "    id: lockProcess\n"
    "    property var command: []\n"
    "    property bool running: false\n"
    "    signal exited(int exitCode, var exitStatus)\n"
    '    onExited: function(exitCode, exitStatus) { root.handleLockExited(exitCode, String(lockProcessOut.text || "")) }\n'
    '    property QtObject lockProcessOut: QtObject { property string text: "" }\n'
    "    function fakeExit(exitCode, output) {\n"
    "      lockProcessOut.text = output\n"
    "      running = false\n"
    "      exited(exitCode, {})\n"
    "    }\n"
    "  }\n"
)
text = replace_once(text, lock_process_old, lock_process_new, "lockProcess Process->fake QtObject")

# Harness-only: the real stayAwakeStateProbe would exec
# ["omanixy-idle-state", "probe"].
probe_old = (
    "  Process {\n"
    "    id: stayAwakeStateProbe\n"
    '    command: ["omanixy-idle-state", "probe"]\n'
    "    onExited: function(exitCode) {\n"
    '      if (exitCode === 0) root.applyStayAwake(true, false, "state-file")\n'
    '      else if (exitCode === 1) root.applyStayAwake(false, false, "state-file")\n'
    "      stayAwakeStateDirWatcher.reload()\n"
    "    }\n"
    "  }\n"
)
probe_new = (
    "  QtObject {\n"
    "    id: stayAwakeStateProbe\n"
    '    property var command: ["omanixy-idle-state", "probe"]\n'
    "    property bool running: false\n"
    "    signal exited(int exitCode)\n"
    "    onExited: function(exitCode) {\n"
    '      if (exitCode === 0) root.applyStayAwake(true, false, "state-file")\n'
    '      else if (exitCode === 1) root.applyStayAwake(false, false, "state-file")\n'
    "      stayAwakeStateDirWatcher.reload()\n"
    "    }\n"
    "    function fakeExit(exitCode) {\n"
    "      running = false\n"
    "      exited(exitCode)\n"
    "    }\n"
    "  }\n"
)
text = replace_once(text, probe_old, probe_new, "stayAwakeStateProbe Process->fake QtObject")

# Harness-only: the real stayAwakeStateWriter would exec ["omanixy-idle-state",
# "set", "awake"/"idle"].
writer_old = (
    "  Process {\n"
    "    id: stayAwakeStateWriter\n"
    "    onExited: function() {\n"
    "      if (root.hasPendingStayAwakePersist) {\n"
    "        var pending = root.pendingStayAwakePersist\n"
    "        root.hasPendingStayAwakePersist = false\n"
    "        root.persistStayAwake(pending)\n"
    "        return\n"
    "      }\n"
    "\n"
    "      root.refreshStayAwakeState()\n"
    "    }\n"
    "  }\n"
)
writer_new = (
    "  QtObject {\n"
    "    id: stayAwakeStateWriter\n"
    "    property var command: []\n"
    "    property bool running: false\n"
    "    signal exited()\n"
    "    onExited: function() {\n"
    "      if (root.hasPendingStayAwakePersist) {\n"
    "        var pending = root.pendingStayAwakePersist\n"
    "        root.hasPendingStayAwakePersist = false\n"
    "        root.persistStayAwake(pending)\n"
    "        return\n"
    "      }\n"
    "\n"
    "      root.refreshStayAwakeState()\n"
    "    }\n"
    "    function fakeExit() {\n"
    "      running = false\n"
    "      exited()\n"
    "    }\n"
    "  }\n"
)
text = replace_once(text, writer_old, writer_new, "stayAwakeStateWriter Process->fake QtObject")

# Harness-only: give the IpcHandler an id so the driver can call its
# methods directly, exactly the path the real IPC bus reaches.
ipc_old = '  IpcHandler {\n    target: "idle"\n'
ipc_new = '  IpcHandler {\n    id: idleIpc\n    target: "idle"\n'
text = replace_once(text, ipc_old, ipc_new, "IpcHandler id anchor")

path.write_text(text)
PY

cat > "$test_root/shell.qml" <<'EOF'
import QtQuick
import Quickshell

ShellRoot {
  id: shellRoot

  Loader {
    id: idleLoader
    source: Qt.resolvedUrl("fixture-idle/Service.qml")
  }

  function fail(label, detail) {
    console.log("IDLE_QML_FAIL", label, detail === undefined ? "" : JSON.stringify(detail))
    Qt.quit()
  }

  function check(condition, label, detail) {
    if (!condition) fail(label, detail)
  }

  function runCases() {
    var agent = idleLoader.item

    // Default lock timeout with no shell/config wired at all, then the
    // real reactive pickup once shellConfig.idle.lock is provided -
    // IdleModel.js's own timeout-parsing matrix is covered exhaustively by
    // test/security-idle-model.sh; this just proves the wiring.
    check(agent.lockTimeoutSeconds === 300, "setup-defaultTimeout", agent.lockTimeoutSeconds)
    agent.shell = { shellConfig: { idle: { lock: 5 } } }
    check(agent.lockTimeoutSeconds === 5, "setup-configuredTimeout", agent.lockTimeoutSeconds)

    // A. startup-before-probe(disabled): idle is not yet enabled until the
    // stay-awake marker probe resolves - fail-safe default.
    check(agent.stayAwakeStateLoaded === false, "A-stateLoaded-initial")
    check(agent.idleEnabled === false, "A-idleEnabled-initial")
    check(agent.fakeStayAwakeProbe.running === true, "A-probe-running-initial")

    // B. probe-absent(enabled): marker absent -> idle becomes enabled.
    agent.fakeStayAwakeProbe.fakeExit(1)
    check(agent.stayAwakeStateLoaded === true, "B-stateLoaded")
    check(agent.stayAwake === false, "B-stayAwake")
    check(agent.idleEnabled === true, "B-idleEnabled")

    // C. idle-signal(one attempt): going idle starts a cycle and issues
    // exactly one bounded lock attempt.
    agent.fakeIdleMonitor.fakeSetIdle(true)
    check(agent.idledThisCycle === true, "C-cycleActive")
    check(agent.lockAttempts === 1, "C-attempts", agent.lockAttempts)
    check(agent.fakeLockProcess.running === true, "C-processRunning")
    check(JSON.stringify(agent.fakeLockProcess.command) === JSON.stringify(["omanixy-shell", "lock", "lock"]),
      "C-command", agent.fakeLockProcess.command)

    // D. ok(accepted/no retry).
    agent.fakeLockProcess.fakeExit(0, "ok")
    check(agent.lockAccepted === true, "D-accepted")
    check(agent.lockTerminalFailure === false, "D-notTerminal")
    check(agent.fakeRetryTimer.running === false, "D-noRetry")
    check(agent.lockAttempts === 1, "D-attemptsUnchanged")
    agent.fakeIdleMonitor.fakeSetIdle(false)
    check(agent.idledThisCycle === false, "D-cycleEnded")

    // E. transient-failure(one non-repeating retry armed).
    agent.fakeIdleMonitor.fakeSetIdle(true)
    check(agent.lockAttempts === 1, "E-freshAttempt", agent.lockAttempts)
    agent.fakeLockProcess.fakeExit(1, "")
    check(agent.lockAccepted === false, "E-notAccepted")
    check(agent.lockTerminalFailure === false, "E-notTerminal")
    check(agent.fakeRetryTimer.running === true, "E-retryArmed")
    check(agent.fakeRetryTimer.interval === 1000, "E-retryInterval", agent.fakeRetryTimer.interval)
    check(agent.fakeRetryTimer.repeat === false, "E-retryNonRepeating")

    // F. three-failures(exhausted): the armed retry is driven manually
    // (calling the same requestLock() the timer itself would call) instead
    // of waiting out the real 1s interval - never more than 3 actual
    // attempts, ever.
    agent.fakeRetryTimer.stop()
    agent.requestLock()
    check(agent.lockAttempts === 2, "F-attempt2", agent.lockAttempts)
    agent.fakeLockProcess.fakeExit(1, "")
    check(agent.fakeRetryTimer.running === true, "F-retry2Armed")
    agent.fakeRetryTimer.stop()
    agent.requestLock()
    check(agent.lockAttempts === 3, "F-attempt3", agent.lockAttempts)
    agent.fakeLockProcess.fakeExit(1, "")
    check(agent.fakeRetryTimer.running === false, "F-exhaustedNoRetry")
    var attemptsBeforeExtra = agent.lockAttempts
    agent.requestLock()
    check(agent.lockAttempts === attemptsBeforeExtra, "F-boundedAtThree", agent.lockAttempts)

    // G. activity-before-retry(cancelled): activity cancels an armed retry
    // before it ever fires, and the cancelled cycle never resumes itself.
    agent.fakeIdleMonitor.fakeSetIdle(false)
    agent.fakeIdleMonitor.fakeSetIdle(true)
    check(agent.lockAttempts === 1, "G-freshCycleAttempt", agent.lockAttempts)
    agent.fakeLockProcess.fakeExit(1, "")
    check(agent.fakeRetryTimer.running === true, "G-retryArmedBeforeActivity")
    agent.fakeIdleMonitor.fakeSetIdle(false)
    check(agent.idledThisCycle === false, "G-cycleCancelled")
    check(agent.fakeRetryTimer.running === false, "G-retryCancelled")
    var attemptsAfterActivity = agent.lockAttempts
    agent.requestLock()
    check(agent.lockAttempts === attemptsAfterActivity, "G-noAttemptAfterActivity")

    // H. stay-awake-during-cycle(cancelled+ends): marking stay-awake
    // mid-cycle cancels it immediately and persists the marker.
    agent.fakeIdleMonitor.fakeSetIdle(true)
    check(agent.idledThisCycle === true, "H-cycleStarted")
    agent.applyStayAwake(true, true, "test-stay-awake")
    check(agent.stayAwake === true, "H-stayAwake")
    check(agent.idleEnabled === false, "H-idleDisabled")
    check(agent.idledThisCycle === false, "H-cycleCancelled")
    check(agent.fakeRetryTimer.running === false, "H-retryCancelled")
    check(agent.fakeStayAwakeWriter.running === true, "H-persistRunning")
    check(JSON.stringify(agent.fakeStayAwakeWriter.command) === JSON.stringify(["omanixy-idle-state", "set", "awake"]),
      "H-persistCommand", agent.fakeStayAwakeWriter.command)
    agent.fakeStayAwakeWriter.fakeExit()
    check(agent.hasPendingStayAwakePersist === false, "H-noPendingPersist")
    check(agent.fakeStayAwakeProbe.running === true, "H-reprobeAfterWrite")
    agent.fakeStayAwakeProbe.fakeExit(0)
    check(agent.stayAwake === true, "H-stillStayAwakeAfterReprobe")
    check(agent.idleEnabled === false, "H-stillDisabledAfterReprobe")

    // I. write-serialization (Section 25): coalesced desired-state
    // requests while a writer Process is already in flight resolve to the
    // LAST requested value, not the first or an intermediate one -
    // awake -> idle -> awake while the first write is in flight resolves
    // to awake.
    check(agent.fakeStayAwakeWriter.running === false, "I-writerIdleBeforeStart")
    agent.persistStayAwake(false)
    check(agent.fakeStayAwakeWriter.running === true, "I-firstWriteRunning")
    check(JSON.stringify(agent.fakeStayAwakeWriter.command) === JSON.stringify(["omanixy-idle-state", "set", "idle"]),
      "I-firstWriteCommand")
    agent.persistStayAwake(true)
    agent.persistStayAwake(false)
    agent.persistStayAwake(true)
    check(agent.hasPendingStayAwakePersist === true, "I-pendingQueued")
    check(agent.pendingStayAwakePersist === true, "I-pendingIsAwake")
    agent.fakeStayAwakeWriter.fakeExit()
    check(agent.fakeStayAwakeWriter.running === true, "I-secondWriteRunning")
    check(JSON.stringify(agent.fakeStayAwakeWriter.command) === JSON.stringify(["omanixy-idle-state", "set", "awake"]),
      "I-secondWriteReflectsLastRequest", agent.fakeStayAwakeWriter.command)
    agent.fakeStayAwakeWriter.fakeExit()
    check(agent.hasPendingStayAwakePersist === false, "I-drainedAfterSecondWrite")
    agent.fakeStayAwakeProbe.fakeExit(0)

    agent.applyStayAwake(false, false, "test-reset")
    check(agent.idleEnabled === true, "reset-idleEnabled")

    // J. missing-pam(terminal/no retry): a terminal failure on the very
    // first attempt blocks all further attempts outright - distinct from
    // a transient failure, and never reinterpreted as success.
    agent.fakeIdleMonitor.fakeSetIdle(true)
    check(agent.idledThisCycle === true, "J-cycleStarted")
    check(agent.lockAttempts === 1, "J-firstAttempt", agent.lockAttempts)
    agent.fakeLockProcess.fakeExit(0, "missing-pam")
    check(agent.lockTerminalFailure === true, "J-terminal")
    check(agent.lockAccepted === false, "J-notAccepted")
    check(agent.fakeRetryTimer.running === false, "J-noRetry")
    var attemptsAfterMissingPam = agent.lockAttempts
    agent.requestLock()
    check(agent.lockAttempts === attemptsAfterMissingPam, "J-boundedAfterTerminal")

    // K. new-cycle(budget reset): ending the terminal-failure cycle and
    // starting a fresh one resets attempts/accepted/terminalFailure, so
    // the previous exhaustion never carries over.
    agent.fakeIdleMonitor.fakeSetIdle(false)
    check(agent.idledThisCycle === false, "K-cycleEnded")
    agent.fakeIdleMonitor.fakeSetIdle(true)
    check(agent.idledThisCycle === true, "K-newCycleStarted")
    check(agent.lockTerminalFailure === false, "K-terminalReset")
    check(agent.lockAccepted === false, "K-acceptedReset")
    check(agent.lockAttempts === 1, "K-attemptsResetAndRestarted", agent.lockAttempts)
    check(agent.fakeLockProcess.running === true, "K-newProcessStarted")
    agent.fakeLockProcess.fakeExit(0, "ok")
    agent.fakeIdleMonitor.fakeSetIdle(false)

    // L. IPC enable/disable/toggle drive ONLY the persistent stay-awake
    // marker via the writer Process - never shell.json (which is not
    // reachable from this file at all; proven separately by
    // test/security-idle-shell-json.sh). status()/debug() expose exactly
    // the field set Section 27 requires, with no stale screensaver fields.
    check(agent.stayAwake === false, "L-startingStayAwakeFalse")
    var disableResult = agent.fakeIpc.disable()
    check(disableResult === "disabled", "L-disableResult", disableResult)
    check(agent.stayAwake === true, "L-disabledMeansStayAwake")
    check(JSON.stringify(agent.fakeStayAwakeWriter.command) === JSON.stringify(["omanixy-idle-state", "set", "awake"]),
      "L-disablePersistsAwake")
    agent.fakeStayAwakeWriter.fakeExit()
    agent.fakeStayAwakeProbe.fakeExit(0)

    var enableResult = agent.fakeIpc.enable()
    check(enableResult === "enabled", "L-enableResult", enableResult)
    check(agent.stayAwake === false, "L-enableMeansNotStayAwake")
    check(JSON.stringify(agent.fakeStayAwakeWriter.command) === JSON.stringify(["omanixy-idle-state", "set", "idle"]),
      "L-enablePersistsIdle")
    agent.fakeStayAwakeWriter.fakeExit()
    agent.fakeStayAwakeProbe.fakeExit(1)

    var toggleResult = agent.fakeIpc.toggle()
    check(toggleResult === "disabled", "L-toggleResult", toggleResult)
    check(agent.stayAwake === true, "L-toggleFlipped")
    agent.fakeStayAwakeWriter.fakeExit()
    agent.fakeStayAwakeProbe.fakeExit(0)

    var status = JSON.parse(agent.fakeIpc.status())
    var expectedKeys = [
      "enabled", "stayAwake", "stayAwakeStateLoaded", "stayAwakeStatePath",
      "idle", "inIdleCycle", "lockAccepted", "lockTerminalFailure",
      "lockAttempts", "lockMaxAttempts", "lockRetryPending",
      "lockProcessRunning", "lockTimeoutSeconds", "lastEvent", "lastEventAt",
    ]
    var actualKeys = Object.keys(status).sort()
    check(JSON.stringify(actualKeys) === JSON.stringify(expectedKeys.slice().sort()), "L-statusKeys", actualKeys)
    check(JSON.stringify(JSON.parse(agent.fakeIpc.debug())) === JSON.stringify(status), "L-debugMatchesStatus")

    console.log("IDLE_QML_PASS")
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
      if (!idleLoader.item) {
        if (attempts >= 50) {
          console.log("IDLE_QML_FAIL", "service did not load")
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

HOME="$test_root/home" XDG_RUNTIME_DIR="$test_root/runtime" QML2_IMPORT_PATH="$test_root" \
  QT_QPA_PLATFORM=offscreen timeout 10s "$quickshell" -n -p "$test_root" \
  >"$test_root/quickshell.log" 2>&1 &
quickshell_pid=$!
wait "$quickshell_pid" || true

if ! grep -Fq 'IDLE_QML_PASS' "$test_root/quickshell.log"; then
  cat "$test_root/quickshell.log" >&2
  exit 1
fi

printf '%s\n' 'idle QML behavior checks passed'
