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
# Every onExited/onRunningChanged/onIsIdleChanged handler body is preserved
# verbatim. The FileView directory watcher and the real lockRetryTimer are
# left untouched - a Timer needs no live backend, and the harness
# stops/replaces its effect manually instead of waiting out the real 1s
# interval.
#
# The idleMonitor fake additionally models one real behavior the pinned
# ABI itself exhibits (proven separately by
# test/security-idle-quickshell-contract.sh): isIdle is a read-only
# property driven solely by the live notification object, and disabling
# the monitor destroys that notification, so isIdle falls back to false
# while disabled and stays false until a fresh notification (and therefore
# a fresh genuine idle transition) exists after re-enabling. This is a
# deliberate choice among the two documented options for what happens if
# the monitor is idle at trust-revocation/recovery time: recovery never
# auto-resumes a stale cycle, and never reuses an exhausted budget - only
# the next genuine idle transition starts a fresh one.
#
# fakeFailedToStart() on all three Process fakes models the pinned
# Quickshell Process ABI's other real transition (proven by
# test/security-idle-quickshell-contract.sh against src/io/process.cpp):
# onErrorOccurred(QProcess::FailedToStart) only ever emits runningChanged(),
# never exited() - so it is deliberately implemented as a bare
# `running = false` (which fires the auto-generated runningChanged
# notification) with no `exited(...)` emission at all, never as
# `fakeExit(some-code)`, which would exercise a different, real-exit path
# instead of this one.
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
# actually reads, plus fakeSetIdle() to drive it. onEnabledChanged models
# the pinned ABI's own real behavior: isIdle is read-only, driven solely by
# a live notification object that gets destroyed whenever the monitor is
# disabled, so isIdle always falls back to false while disabled.
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
    "    onEnabledChanged: { if (!enabled) isIdle = false }\n"
    "    onIsIdleChanged: root.handleIdleChanged()\n"
    "    function fakeSetIdle(value) {\n"
    "      if (!enabled) return\n"
    "      isIdle = value\n"
    "    }\n"
    "  }\n"
)
text = replace_once(text, idle_monitor_old, idle_monitor_new, "idleMonitor IdleMonitor->fake QtObject")

# Harness-only: the real lockProcess would exec ["omanixy-shell", "lock",
# "lock"], which no offscreen test environment can run deterministically.
# fakeFailedToStart() models onErrorOccurred(QProcess::FailedToStart): only
# `running` changes, exited() never fires.
lock_process_old = (
    "  Process {\n"
    "    id: lockProcess\n"
    '    stdout: StdioCollector { id: lockProcessOut; waitForEnd: true }\n'
    "    onExited: function(exitCode, exitStatus) {\n"
    "      root.lockAwaitingResult = false\n"
    '      root.handleLockExited(exitCode, String(lockProcessOut.text || ""))\n'
    "    }\n"
    "    onRunningChanged: {\n"
    "      if (!running && root.lockAwaitingResult) Qt.callLater(root.reconcileLockFailedToStart)\n"
    "    }\n"
    "  }\n"
)
lock_process_new = (
    "  QtObject {\n"
    "    id: lockProcess\n"
    "    property var command: []\n"
    "    property bool running: false\n"
    "    signal exited(int exitCode, var exitStatus)\n"
    "    onExited: function(exitCode, exitStatus) {\n"
    "      root.lockAwaitingResult = false\n"
    '      root.handleLockExited(exitCode, String(lockProcessOut.text || ""))\n'
    "    }\n"
    "    onRunningChanged: {\n"
    "      if (!running && root.lockAwaitingResult) Qt.callLater(root.reconcileLockFailedToStart)\n"
    "    }\n"
    '    property QtObject lockProcessOut: QtObject { property string text: "" }\n'
    "    function fakeExit(exitCode, output) {\n"
    "      lockProcessOut.text = output\n"
    "      running = false\n"
    "      exited(exitCode, {})\n"
    "    }\n"
    "    function fakeFailedToStart() {\n"
    "      running = false\n"
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
    "      root.stayAwakeProbeAwaitingResult = false\n"
    "      root.handleStayAwakeProbeExited(exitCode)\n"
    "    }\n"
    "    onRunningChanged: {\n"
    "      if (!running && root.stayAwakeProbeAwaitingResult) Qt.callLater(root.reconcileStayAwakeProbeFailedToStart)\n"
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
    "      root.stayAwakeProbeAwaitingResult = false\n"
    "      root.handleStayAwakeProbeExited(exitCode)\n"
    "    }\n"
    "    onRunningChanged: {\n"
    "      if (!running && root.stayAwakeProbeAwaitingResult) Qt.callLater(root.reconcileStayAwakeProbeFailedToStart)\n"
    "    }\n"
    "    function fakeExit(exitCode) {\n"
    "      running = false\n"
    "      exited(exitCode)\n"
    "    }\n"
    "    function fakeFailedToStart() {\n"
    "      running = false\n"
    "    }\n"
    "  }\n"
)
text = replace_once(text, probe_old, probe_new, "stayAwakeStateProbe Process->fake QtObject")

# Harness-only: the real stayAwakeStateWriter would exec ["omanixy-idle-state",
# "set", "awake"/"idle"].
writer_old = (
    "  Process {\n"
    "    id: stayAwakeStateWriter\n"
    "    onExited: function(exitCode) {\n"
    "      root.stayAwakeWriterAwaitingResult = false\n"
    "      root.handleStayAwakeWriterExited(exitCode)\n"
    "    }\n"
    "    onRunningChanged: {\n"
    "      if (!running && root.stayAwakeWriterAwaitingResult) Qt.callLater(root.reconcileStayAwakeWriterFailedToStart)\n"
    "    }\n"
    "  }\n"
)
writer_new = (
    "  QtObject {\n"
    "    id: stayAwakeStateWriter\n"
    "    property var command: []\n"
    "    property bool running: false\n"
    "    signal exited(int exitCode)\n"
    "    onExited: function(exitCode) {\n"
    "      root.stayAwakeWriterAwaitingResult = false\n"
    "      root.handleStayAwakeWriterExited(exitCode)\n"
    "    }\n"
    "    onRunningChanged: {\n"
    "      if (!running && root.stayAwakeWriterAwaitingResult) Qt.callLater(root.reconcileStayAwakeWriterFailedToStart)\n"
    "    }\n"
    "    function fakeExit(exitCode) {\n"
    "      running = false\n"
    "      exited(exitCode)\n"
    "    }\n"
    "    function fakeFailedToStart() {\n"
    "      running = false\n"
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

    // --- Trust/revocation matrix (Section 2/3) ---

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

    // C. probe indeterminate (exit 2): existence is unprovable, not
    // "marker absent" - trust is revoked outright, never inferred as
    // stayAwake=false.
    agent.fakeStayAwakeProbe.fakeExit(2)
    check(agent.stayAwakeStateLoaded === false, "C-stateRevoked")
    check(agent.idleEnabled === false, "C-idleDisabledOnRevocation")

    // D. probe indeterminate while an idle cycle exists and a retry is
    // armed: the revocation cancels the cycle and the retry outright, and
    // no further attempt can occur while state remains unknown.
    agent.fakeStayAwakeProbe.fakeExit(1) // recover trust first
    check(agent.idleEnabled === true, "D-recoveredBeforeCycle")
    agent.fakeIdleMonitor.fakeSetIdle(true)
    check(agent.idledThisCycle === true, "D-cycleStarted")
    agent.fakeLockProcess.fakeExit(1, "")
    check(agent.fakeRetryTimer.running === true, "D-retryArmedBeforeRevocation")
    agent.fakeStayAwakeProbe.fakeExit(2)
    check(agent.idledThisCycle === false, "D-cycleCancelledByRevocation")
    check(agent.fakeRetryTimer.running === false, "D-retryCancelledByRevocation")
    var attemptsAtRevocation = agent.lockAttempts
    agent.requestLock()
    check(agent.lockAttempts === attemptsAtRevocation, "D-noAttemptWhileUnknown")

    // E. after recovering trust, going idle then marking stay-awake
    // (exit 0) still disables idle and cancels the active cycle - the
    // ordinary stay-awake path is unaffected by the revocation path above.
    agent.fakeStayAwakeProbe.fakeExit(1)
    agent.fakeIdleMonitor.fakeSetIdle(true)
    check(agent.idledThisCycle === true, "E-cycleStarted")
    agent.fakeLockProcess.fakeExit(1, "")
    agent.fakeStayAwakeProbe.fakeExit(0)
    check(agent.stayAwake === true, "E-stayAwakeTrue")
    check(agent.idleEnabled === false, "E-idleDisabled")
    check(agent.idledThisCycle === false, "E-cycleCancelled")

    // F. after an indeterminate state, a later probe 1 makes the state
    // trusted again - and because the fake idleMonitor models the pinned
    // ABI's own enabled-disables-isIdle behavior, isIdle was already reset
    // to false while disabled, so recovery never auto-resumes a stale
    // cycle: only a fresh genuine idle transition starts a new one, with a
    // fresh budget.
    agent.applyStayAwake(false, false, "test-reset") // back to stayAwake=false, still loaded
    agent.fakeIdleMonitor.fakeSetIdle(true)
    check(agent.idledThisCycle === true, "F-cycleBeforeRevocation")
    check(agent.lockAttempts === 1, "F-attemptBeforeRevocation", agent.lockAttempts)
    agent.fakeLockProcess.fakeExit(0, "ok") // resolve the in-flight attempt cleanly before revoking trust
    agent.fakeStayAwakeProbe.fakeExit(2) // revoke while genuinely idle
    check(agent.idleEnabled === false, "F-revoked")
    check(agent.fakeIdleMonitor.isIdle === false, "F-isIdleResetWhileDisabled")
    agent.fakeStayAwakeProbe.fakeExit(1) // recover
    check(agent.idleEnabled === true, "F-recovered")
    check(agent.idledThisCycle === false, "F-noStaleCycleResumed")
    check(agent.fakeIdleMonitor.isIdle === false, "F-stillNotIdleUntilFreshTransition")
    agent.fakeIdleMonitor.fakeSetIdle(true) // the next genuine transition
    check(agent.idledThisCycle === true, "F-freshCycleStarted")
    check(agent.lockAttempts === 1, "F-freshBudget", agent.lockAttempts)
    agent.fakeLockProcess.fakeExit(0, "ok")
    agent.fakeIdleMonitor.fakeSetIdle(false)

    // --- Bounded lock-retry policy (Section 6, carried over from the
    // original review) ---

    // idle-signal(one attempt): going idle starts a cycle and issues
    // exactly one bounded lock attempt.
    agent.fakeIdleMonitor.fakeSetIdle(true)
    check(agent.idledThisCycle === true, "G-cycleActive")
    check(agent.lockAttempts === 1, "G-attempts", agent.lockAttempts)
    check(agent.fakeLockProcess.running === true, "G-processRunning")
    check(JSON.stringify(agent.fakeLockProcess.command) === JSON.stringify(["omanixy-shell", "lock", "lock"]),
      "G-command", agent.fakeLockProcess.command)

    // ok(accepted/no retry).
    agent.fakeLockProcess.fakeExit(0, "ok")
    check(agent.lockAccepted === true, "H-accepted")
    check(agent.lockTerminalFailure === false, "H-notTerminal")
    check(agent.fakeRetryTimer.running === false, "H-noRetry")
    check(agent.lockAttempts === 1, "H-attemptsUnchanged")
    agent.fakeIdleMonitor.fakeSetIdle(false)
    check(agent.idledThisCycle === false, "H-cycleEnded")

    // transient-failure(one non-repeating retry armed).
    agent.fakeIdleMonitor.fakeSetIdle(true)
    check(agent.lockAttempts === 1, "I-freshAttempt", agent.lockAttempts)
    agent.fakeLockProcess.fakeExit(1, "")
    check(agent.lockAccepted === false, "I-notAccepted")
    check(agent.lockTerminalFailure === false, "I-notTerminal")
    check(agent.fakeRetryTimer.running === true, "I-retryArmed")
    check(agent.fakeRetryTimer.interval === 1000, "I-retryInterval", agent.fakeRetryTimer.interval)
    check(agent.fakeRetryTimer.repeat === false, "I-retryNonRepeating")

    // three-failures(exhausted): the armed retry is driven manually
    // (calling the same requestLock() the timer itself would call) instead
    // of waiting out the real 1s interval - never more than 3 actual
    // attempts, ever.
    agent.fakeRetryTimer.stop()
    agent.requestLock()
    check(agent.lockAttempts === 2, "J-attempt2", agent.lockAttempts)
    agent.fakeLockProcess.fakeExit(1, "")
    check(agent.fakeRetryTimer.running === true, "J-retry2Armed")
    agent.fakeRetryTimer.stop()
    agent.requestLock()
    check(agent.lockAttempts === 3, "J-attempt3", agent.lockAttempts)
    agent.fakeLockProcess.fakeExit(1, "")
    check(agent.fakeRetryTimer.running === false, "J-exhaustedNoRetry")
    var attemptsBeforeExtra = agent.lockAttempts
    agent.requestLock()
    check(agent.lockAttempts === attemptsBeforeExtra, "J-boundedAtThree", agent.lockAttempts)

    // activity-before-retry(cancelled): activity cancels an armed retry
    // before it ever fires, and the cancelled cycle never resumes itself.
    agent.fakeIdleMonitor.fakeSetIdle(false)
    agent.fakeIdleMonitor.fakeSetIdle(true)
    check(agent.lockAttempts === 1, "K-freshCycleAttempt", agent.lockAttempts)
    agent.fakeLockProcess.fakeExit(1, "")
    check(agent.fakeRetryTimer.running === true, "K-retryArmedBeforeActivity")
    agent.fakeIdleMonitor.fakeSetIdle(false)
    check(agent.idledThisCycle === false, "K-cycleCancelled")
    check(agent.fakeRetryTimer.running === false, "K-retryCancelled")
    var attemptsAfterActivity = agent.lockAttempts
    agent.requestLock()
    check(agent.lockAttempts === attemptsAfterActivity, "K-noAttemptAfterActivity")

    // stay-awake-during-cycle(cancelled+ends): marking stay-awake
    // mid-cycle cancels it immediately and persists the marker.
    agent.fakeIdleMonitor.fakeSetIdle(true)
    check(agent.idledThisCycle === true, "L-cycleStarted")
    agent.applyStayAwake(true, true, "test-stay-awake")
    check(agent.stayAwake === true, "L-stayAwake")
    check(agent.idleEnabled === false, "L-idleDisabled")
    check(agent.idledThisCycle === false, "L-cycleCancelled")
    check(agent.fakeRetryTimer.running === false, "L-retryCancelled")
    // The cancelled cycle's own lock attempt is still in flight (cancelling
    // a cycle never kills an already-running lock Process - see the ADR);
    // resolve it here so it cannot block a later cycle's own first attempt
    // via canRequestLock's lockRunning guard.
    agent.fakeLockProcess.fakeExit(0, "ok")
    check(agent.fakeStayAwakeWriter.running === true, "L-persistRunning")
    check(JSON.stringify(agent.fakeStayAwakeWriter.command) === JSON.stringify(["omanixy-idle-state", "set", "awake"]),
      "L-persistCommand", agent.fakeStayAwakeWriter.command)
    agent.fakeStayAwakeWriter.fakeExit(0)
    check(agent.hasPendingStayAwakePersist === false, "L-noPendingPersist")
    check(agent.fakeStayAwakeProbe.running === true, "L-reprobeAfterWrite")
    agent.fakeStayAwakeProbe.fakeExit(0)
    check(agent.stayAwake === true, "L-stillStayAwakeAfterReprobe")
    check(agent.idleEnabled === false, "L-stillDisabledAfterReprobe")

    // write-serialization (Section 25): coalesced desired-state
    // requests while a writer Process is already in flight resolve to the
    // LAST requested value, not the first or an intermediate one -
    // awake -> idle -> awake while the first write is in flight resolves
    // to awake.
    check(agent.fakeStayAwakeWriter.running === false, "M-writerIdleBeforeStart")
    agent.persistStayAwake(false)
    check(agent.fakeStayAwakeWriter.running === true, "M-firstWriteRunning")
    check(JSON.stringify(agent.fakeStayAwakeWriter.command) === JSON.stringify(["omanixy-idle-state", "set", "idle"]),
      "M-firstWriteCommand")
    agent.persistStayAwake(true)
    agent.persistStayAwake(false)
    agent.persistStayAwake(true)
    check(agent.hasPendingStayAwakePersist === true, "M-pendingQueued")
    check(agent.pendingStayAwakePersist === true, "M-pendingIsAwake")
    agent.fakeStayAwakeWriter.fakeExit(0)
    check(agent.fakeStayAwakeWriter.running === true, "M-secondWriteRunning")
    check(JSON.stringify(agent.fakeStayAwakeWriter.command) === JSON.stringify(["omanixy-idle-state", "set", "awake"]),
      "M-secondWriteReflectsLastRequest", agent.fakeStayAwakeWriter.command)
    agent.fakeStayAwakeWriter.fakeExit(0)
    check(agent.hasPendingStayAwakePersist === false, "M-drainedAfterSecondWrite")
    agent.fakeStayAwakeProbe.fakeExit(0)

    agent.applyStayAwake(false, false, "test-reset")
    check(agent.idleEnabled === true, "reset-idleEnabled")

    // missing-pam(terminal/no retry): a terminal failure on the very
    // first attempt blocks all further attempts outright - distinct from
    // a transient failure, and never reinterpreted as success.
    agent.fakeIdleMonitor.fakeSetIdle(true)
    check(agent.idledThisCycle === true, "N-cycleStarted")
    check(agent.lockAttempts === 1, "N-firstAttempt", agent.lockAttempts)
    agent.fakeLockProcess.fakeExit(0, "missing-pam")
    check(agent.lockTerminalFailure === true, "N-terminal")
    check(agent.lockAccepted === false, "N-notAccepted")
    check(agent.fakeRetryTimer.running === false, "N-noRetry")
    var attemptsAfterMissingPam = agent.lockAttempts
    agent.requestLock()
    check(agent.lockAttempts === attemptsAfterMissingPam, "N-boundedAfterTerminal")

    // new-cycle(budget reset): ending the terminal-failure cycle and
    // starting a fresh one resets attempts/accepted/terminalFailure, so
    // the previous exhaustion never carries over.
    agent.fakeIdleMonitor.fakeSetIdle(false)
    check(agent.idledThisCycle === false, "O-cycleEnded")
    agent.fakeIdleMonitor.fakeSetIdle(true)
    check(agent.idledThisCycle === true, "O-newCycleStarted")
    check(agent.lockTerminalFailure === false, "O-terminalReset")
    check(agent.lockAccepted === false, "O-acceptedReset")
    check(agent.lockAttempts === 1, "O-attemptsResetAndRestarted", agent.lockAttempts)
    check(agent.fakeLockProcess.running === true, "O-newProcessStarted")
    agent.fakeLockProcess.fakeExit(0, "ok")
    agent.fakeIdleMonitor.fakeSetIdle(false)

    // --- FailedToStart matrix (Section 10) ---
    //
    // Every reconciliation below runs from a Qt.callLater the production
    // code itself schedules (never synchronously from fakeFailedToStart()
    // - the pinned ABI's own onErrorOccurred(FailedToStart) only emits
    // runningChanged(), and the production onRunningChanged handler defers
    // to the next event-loop turn exactly as designed). Every check that
    // depends on a FailedToStart's effect therefore runs from its own
    // Qt.callLater-driven continuation, one real event-loop turn after the
    // fakeFailedToStart() call that triggers it - never synchronously in
    // the same statement block, which would race ahead of the production
    // reconciliation and observe stale state.
    runFailedToStartMatrix(agent)
  }

  // FS-A/FS-B: lock start failures are bounded exactly like transient exit
  // failures - never refunded, never a fourth attempt, and 100 synthetic
  // FailedToStart events still cap at exactly 3 actual starts (lockAttempts
  // only ever increments on an actual requestLock() start, and a denied
  // canRequestLock() call never increments it, so lockAttempts alone is
  // the count of actual starts).
  function stressLockFailedToStart(agent, iterationsLeft, done) {
    agent.fakeLockProcess.fakeFailedToStart()
    Qt.callLater(function () {
      if (!agent.fakeRetryTimer.running) { done(); return }
      agent.fakeRetryTimer.stop()
      agent.requestLock()
      if (iterationsLeft <= 1) { done(); return }
      Qt.callLater(function () { stressLockFailedToStart(agent, iterationsLeft - 1, done) })
    })
  }

  function runFailedToStartMatrix(agent) {
    agent.fakeIdleMonitor.fakeSetIdle(true)
    check(agent.lockAttempts === 1, "FS-A-firstAttempt", agent.lockAttempts)

    stressLockFailedToStart(agent, 100, function () {
      check(agent.lockAttempts === 3, "FS-B-boundedAtThreeAttempts", agent.lockAttempts)
      check(agent.fakeRetryTimer.running === false, "FS-B-noRetryAfterExhaustion")
      var attemptsAfterHundred = agent.lockAttempts
      agent.requestLock()
      check(agent.lockAttempts === attemptsAfterHundred, "FS-B-noFourthAttempt")
      agent.fakeIdleMonitor.fakeSetIdle(false)
      runSteps(agent, failedToStartSteps, 0, runIpcAndFinish)
    })
  }

  property int fsAttemptsAfterNormalExit: 0

  // FS-C through FS-J: a fixed sequence of steps, each possibly containing
  // one fakeFailedToStart() call - runSteps() defers one event-loop turn
  // between every step, so any reconciliation a step triggers has already
  // run by the time the next step's checks execute.
  property var failedToStartSteps: [
    // FS-C: a normal transient exit failure mixed with a start failure is
    // classified independently, in the same 3-attempt budget - no
    // over-counting either way.
    function (agent) {
      agent.fakeIdleMonitor.fakeSetIdle(true)
      check(agent.lockAttempts === 1, "FS-C-attempt1", agent.lockAttempts)
      agent.fakeLockProcess.fakeFailedToStart() // attempt 1: start failure
    },
    function (agent) {
      check(agent.fakeRetryTimer.running === true, "FS-C-retryAfterStartFailure")
      agent.fakeRetryTimer.stop()
      agent.requestLock()
      check(agent.lockAttempts === 2, "FS-C-attempt2", agent.lockAttempts)
      agent.fakeLockProcess.fakeExit(1, "") // attempt 2: ordinary transient exit
      check(agent.fakeRetryTimer.running === true, "FS-C-retryAfterNormalFailure")
      agent.fakeRetryTimer.stop()
      agent.requestLock()
      check(agent.lockAttempts === 3, "FS-C-attempt3", agent.lockAttempts)
      agent.fakeLockProcess.fakeFailedToStart() // attempt 3: start failure again
    },
    function (agent) {
      check(agent.fakeRetryTimer.running === false, "FS-C-exhaustedAfterMixedFailures")

      // FS-D: a normal exit's own runningChanged (fired as part of the
      // same fakeExit() call, synchronously before the deferred
      // reconciliation this same step schedules would run) must never be
      // misclassified as a second FailedToStart - proven by the attempt
      // count staying exactly where the exit-based classification left
      // it, across every ordinary fakeExit() case in this file and this
      // one, checked one turn later in the next step.
      fsAttemptsAfterNormalExit = agent.lockAttempts
      agent.fakeLockProcess.fakeExit(0, "ok") // ACCEPTED: no retry, no FailedToStart double-count
    },
    function (agent) {
      check(agent.lockAccepted === true, "FS-D-accepted")
      check(agent.lockAttempts === fsAttemptsAfterNormalExit, "FS-D-noDoubleProcessing")
      check(agent.fakeRetryTimer.running === false, "FS-D-noSpuriousRetry")
      agent.fakeIdleMonitor.fakeSetIdle(false)

      // FS-E: a probe FailedToStart leaves loaded=false, exactly like an
      // indeterminate exit code would.
      agent.fakeStayAwakeProbe.fakeExit(1) // ensure a known starting point
      check(agent.idleEnabled === true, "FS-E-setup")
      agent.refreshStayAwakeState()
      check(agent.fakeStayAwakeProbe.running === true, "FS-E-probeRunning")
      agent.fakeStayAwakeProbe.fakeFailedToStart()
    },
    function (agent) {
      check(agent.stayAwakeStateLoaded === false, "FS-E-loadedFalseAfterStartFailure")
      check(agent.idleEnabled === false, "FS-E-idleDisabledAfterStartFailure")

      // FS-F: successful probe 1, then a later probe FailedToStart: loaded
      // becomes false again, idle revoked - the FailedToStart path revokes
      // trust exactly like the indeterminate-exit path does.
      agent.fakeStayAwakeProbe.fakeExit(1)
      check(agent.idleEnabled === true, "FS-F-recovered")
      agent.refreshStayAwakeState()
      agent.fakeStayAwakeProbe.fakeFailedToStart()
    },
    function (agent) {
      check(agent.stayAwakeStateLoaded === false, "FS-F-revokedAgain")
      check(agent.idleEnabled === false, "FS-F-idleDisabledAgain")

      // FS-G: a probe FailedToStart while an idle cycle is active and a
      // retry is armed cancels both, exactly like the indeterminate-exit
      // revocation case D above.
      agent.fakeStayAwakeProbe.fakeExit(1)
      agent.fakeIdleMonitor.fakeSetIdle(true)
      check(agent.idledThisCycle === true, "FS-G-cycleStarted")
      agent.fakeLockProcess.fakeExit(1, "")
      check(agent.fakeRetryTimer.running === true, "FS-G-retryArmed")
      agent.refreshStayAwakeState()
      agent.fakeStayAwakeProbe.fakeFailedToStart()
    },
    function (agent) {
      check(agent.idledThisCycle === false, "FS-G-cycleCancelled")
      check(agent.fakeRetryTimer.running === false, "FS-G-retryCancelled")
      agent.fakeIdleMonitor.fakeSetIdle(false)
      agent.fakeStayAwakeProbe.fakeExit(1)

      // FS-H: a writer FailedToStart persisting "idle disable" (stay-awake
      // marker being set) leaves loaded=false until a confirming probe -
      // never optimistically assumed to have succeeded.
      var disableResult = agent.fakeIpc.disable()
      check(disableResult === "disabled", "FS-H-disableResult", disableResult)
      check(agent.fakeStayAwakeWriter.running === true, "FS-H-writerRunning")
      agent.fakeStayAwakeWriter.fakeFailedToStart()
    },
    function (agent) {
      check(agent.stayAwakeStateLoaded === false, "FS-H-loadedFalseAfterWriterStartFailure")
      check(agent.idleEnabled === false, "FS-H-idleDisabledUnconfirmed")
      agent.fakeStayAwakeProbe.fakeExit(0) // the drain-or-refresh path re-probed automatically
      check(agent.stayAwake === true, "FS-H-confirmedAfterProbe")

      // FS-I: a writer FailedToStart persisting "idle enable" (removing
      // the stay-awake marker) must NOT leave automatic locking active
      // from an optimistic assumption - loaded stays false until
      // confirmed, exactly symmetric to FS-H.
      var enableResult = agent.fakeIpc.enable()
      check(enableResult === "enabled", "FS-I-enableResult", enableResult)
      check(agent.fakeStayAwakeWriter.running === true, "FS-I-writerRunning")
      agent.fakeStayAwakeWriter.fakeFailedToStart()
    },
    function (agent) {
      check(agent.stayAwakeStateLoaded === false, "FS-I-loadedFalseAfterWriterStartFailure")
      check(agent.idleEnabled === false, "FS-I-idleDisabledDespiteRequestedEnable",
        "automatic locking must never become active from an unconfirmed optimistic write")
      agent.fakeStayAwakeProbe.fakeExit(1) // the drain-or-refresh path re-probed automatically
      check(agent.idleEnabled === true, "FS-I-confirmedAfterProbe")

      // FS-J: a writer FailedToStart with exactly one coalesced later
      // desired-state request attempts only that one queued write - no
      // autonomous loop, and no more than the explicitly user-requested
      // latest value.
      agent.persistStayAwake(true) // first write in flight
      check(agent.fakeStayAwakeWriter.running === true, "FS-J-firstWriteRunning")
      agent.persistStayAwake(false) // coalesced while in flight
      check(agent.hasPendingStayAwakePersist === true, "FS-J-pendingQueued")
      agent.fakeStayAwakeWriter.fakeFailedToStart() // the first write itself fails to start
    },
    function (agent) {
      check(agent.stayAwakeStateLoaded === false, "FS-J-revokedByFirstFailure")
      check(agent.fakeStayAwakeWriter.running === true, "FS-J-secondWriteAttemptedOnce",
        "exactly the one coalesced pending request must be attempted next, not zero and not a loop")
      check(JSON.stringify(agent.fakeStayAwakeWriter.command) === JSON.stringify(["omanixy-idle-state", "set", "idle"]),
        "FS-J-secondWriteReflectsCoalescedRequest", agent.fakeStayAwakeWriter.command)
      agent.fakeStayAwakeWriter.fakeExit(0)
      check(agent.hasPendingStayAwakePersist === false, "FS-J-noFurtherPendingAfterSecondWrite")
      agent.fakeStayAwakeProbe.fakeExit(1)
    },
  ]

  // Generic deferred-step driver: runs steps[index](agent) synchronously,
  // then waits one real event-loop turn (via Qt.callLater) before running
  // the next step - always, even for steps with no FailedToStart call of
  // their own, so no step's checks can ever race ahead of a reconciliation
  // scheduled by the previous one.
  function runSteps(agent, steps, index, done) {
    if (index >= steps.length) {
      done(agent)
      return
    }
    steps[index](agent)
    Qt.callLater(function () { runSteps(agent, steps, index + 1, done) })
  }

  // --- IPC (Section 27) ---
  //
  // IPC enable/disable/toggle drive ONLY the persistent stay-awake marker
  // via the writer Process - never shell.json (which is not reachable from
  // this file at all; proven separately by
  // test/security-idle-shell-json.sh). status()/debug() expose exactly the
  // field set Section 27 requires, with no stale screensaver fields. This
  // section only ever uses fakeExit(), never fakeFailedToStart(), so it
  // stays fully synchronous.
  function runIpcAndFinish(agent) {
    check(agent.stayAwake === false, "P-startingStayAwakeFalse")
    var disableResult2 = agent.fakeIpc.disable()
    check(disableResult2 === "disabled", "P-disableResult", disableResult2)
    check(agent.stayAwake === true, "P-disabledMeansStayAwake")
    check(JSON.stringify(agent.fakeStayAwakeWriter.command) === JSON.stringify(["omanixy-idle-state", "set", "awake"]),
      "P-disablePersistsAwake")
    agent.fakeStayAwakeWriter.fakeExit(0)
    agent.fakeStayAwakeProbe.fakeExit(0)

    var enableResult2 = agent.fakeIpc.enable()
    check(enableResult2 === "enabled", "P-enableResult", enableResult2)
    check(agent.stayAwake === false, "P-enableMeansNotStayAwake")
    check(JSON.stringify(agent.fakeStayAwakeWriter.command) === JSON.stringify(["omanixy-idle-state", "set", "idle"]),
      "P-enablePersistsIdle")
    agent.fakeStayAwakeWriter.fakeExit(0)
    agent.fakeStayAwakeProbe.fakeExit(1)

    var toggleResult = agent.fakeIpc.toggle()
    check(toggleResult === "disabled", "P-toggleResult", toggleResult)
    check(agent.stayAwake === true, "P-toggleFlipped")
    agent.fakeStayAwakeWriter.fakeExit(0)
    agent.fakeStayAwakeProbe.fakeExit(0)

    var status = JSON.parse(agent.fakeIpc.status())
    var expectedKeys = [
      "enabled", "stayAwake", "stayAwakeStateLoaded", "stayAwakeStatePath",
      "idle", "inIdleCycle", "lockAccepted", "lockTerminalFailure",
      "lockAttempts", "lockMaxAttempts", "lockRetryPending",
      "lockProcessRunning", "lockTimeoutSeconds", "lastEvent", "lastEventAt",
    ]
    var actualKeys = Object.keys(status).sort()
    check(JSON.stringify(actualKeys) === JSON.stringify(expectedKeys.slice().sort()), "P-statusKeys", actualKeys)
    check(JSON.stringify(JSON.parse(agent.fakeIpc.debug())) === JSON.stringify(status), "P-debugMatchesStatus")

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
