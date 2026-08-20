#!/usr/bin/env bash
# Static source-contract evidence against the pinned Quickshell
# Quickshell.Wayland IdleMonitor ABI (src/wayland/idle_notify/), proving the
# properties the Layer-6 ADR and ledger rely on: respectInhibitors defaults
# to true, an unsupported ext-idle-notify-v1 protocol logs a warning and
# leaves isIdle false with no fallback timer ever invented, the timeout is
# converted from seconds to milliseconds, respectInhibitors selects between
# get_idle_notification/get_input_idle_notification (falling back to
# respecting inhibitors on an old protocol version), a missing seat yields
# nullptr rather than a crash or a retry loop, and idled/resumed map
# directly onto isIdle.
#
# This is pinned third-party C++ source we do not own or patch; the point of
# this test is to catch drift in our own understanding (or in the pinned
# revision itself) against the exact ABI evidence recorded in the ADR and
# ledger, not to modify or re-implement any of it. Section 43 deliberately
# does not claim this proves real compositor/inhibitor interaction - that is
# explicitly deferred to Layer 8.
#
# Remediation pass: also proves the pinned Quickshell.Io Process ABI
# (src/io/process.{hpp,cpp}) the idle service's own FailedToStart handling
# depends on - a normal finish emits exited() before runningChanged(), a
# failed-to-start process emits ONLY runningChanged() and never exited() at
# all, and Process exposes a real, parameterless, untracked
# Q_INVOKABLE startDetached() (the reason scan-idle-executable-surface must
# reject it unconditionally, even against an otherwise-allowlisted argv).
set -euo pipefail

quickshell_src=${1:?pinned Quickshell source root required}
idle_notify_dir=$quickshell_src/src/wayland/idle_notify
io_dir=$quickshell_src/src/io

monitor_hpp=$idle_notify_dir/monitor.hpp
monitor_cpp=$idle_notify_dir/monitor.cpp
proto_cpp=$idle_notify_dir/proto.cpp
process_hpp=$io_dir/process.hpp
process_cpp=$io_dir/process.cpp

for f in "$monitor_hpp" "$monitor_cpp" "$proto_cpp" "$process_hpp" "$process_cpp"; do
  test -f "$f"
done

extract_function() {
  # Mirrors test/security-polkit-quickshell-contract.sh's extraction helper:
  # prints the body of the first function whose signature contains $2, up
  # to (but not including) the next top-level "}" - good enough for these
  # small, consistently-formatted files without a real C++ parser.
  local file=$1 signature=$2
  awk -v sig="$signature" '
    index($0, sig) { found = 1 }
    found { print; if (/^}/) exit }
  ' "$file"
}

line_of() {
  local body=$1 needle=$2
  grep -nF "$needle" <<<"$body" | head -1 | cut -d: -f1
}

assert_before() {
  local body=$1 earlier=$2 later=$3 description=$4
  local earlier_line later_line
  earlier_line=$(line_of "$body" "$earlier")
  later_line=$(line_of "$body" "$later")
  test -n "$earlier_line" -a -n "$later_line"
  if [ "$earlier_line" -ge "$later_line" ]; then
    printf '%s: expected %s before %s\n' "$description" "$earlier" "$later" >&2
    exit 1
  fi
}

# 1. respectInhibitors defaults to true - MANDATORY, no way to disable it
# from our own Service.qml, which never sets it to anything but true.
grep -Fq 'Q_OBJECT_BINDABLE_PROPERTY_WITH_ARGS(IdleMonitor, bool, bRespectInhibitors, true, &IdleMonitor::respectInhibitorsChanged);' "$monitor_hpp"

# 2. isIdle has no independent default of its own - it is purely derived
# from whichever notification object (if any) exists.
post_reload_body=$(extract_function "$monitor_cpp" "void IdleMonitor::onPostReload()")
grep -Fq 'return notification ? notification->bIsIdle.value() : false;' <<<"$post_reload_body"

# 3 & 4 both live inside IdleMonitor::updateNotification() - extract it once.
update_notification_body=$(extract_function "$monitor_cpp" "void IdleMonitor::updateNotification()")

# 3. Unsupported ext-idle-notify-v1 protocol (no manager instance): a
# warning is logged and the function returns with notification left null -
# combined with check 2 above, isIdle stays false. No fallback timer is
# ever invented anywhere in this pinned source.
grep -Fq 'if (!manager) {' <<<"$update_notification_body"
grep -Fq 'qWarning() << "Cannot create idle monitor as ext-idle-notify-v1 is not supported by the "' <<<"$update_notification_body"
assert_before "$update_notification_body" 'if (!manager) {' 'return;' \
  "the no-manager warning must be checked before returning"
if grep -Eiq 'QTimer|startTimer|singleShot' "$monitor_cpp" "$proto_cpp"; then
  printf '%s\n' 'unexpected timer vocabulary found in the pinned idle_notify source - no fallback timer may exist' >&2
  exit 1
fi

# 4. The timeout is converted from seconds (our Service.qml's
# lockTimeoutSeconds) to milliseconds, clamped to non-negative, exactly
# once, right before being handed to createIdleNotification.
grep -Fq 'auto timeout = static_cast<quint32>(std::max(0, static_cast<int>(params.timeout * 1000)));' <<<"$update_notification_body"
grep -Fq 'notification = manager->createIdleNotification(timeout, params.respectInhibitors);' <<<"$update_notification_body"
assert_before "$update_notification_body" \
  'auto timeout = static_cast<quint32>(std::max(0, static_cast<int>(params.timeout * 1000)));' \
  'notification = manager->createIdleNotification(timeout, params.respectInhibitors);' \
  "the timeout must be converted to milliseconds before being passed to createIdleNotification"

# 5-7 all live inside IdleNotificationManager::createIdleNotification.
create_body=$(extract_function "$proto_cpp" "IdleNotificationManager::createIdleNotification(quint32 timeout, bool respectInhibitors)")

# 5. respectInhibitors=false is itself forced back to true (with a warning)
# when the compositor's protocol version is too old to support
# get_input_idle_notification - this happens before the seat lookup and
# before the backend call, never silently ignored.
grep -Fq 'qCWarning(logIdleNotify) << "Cannot ignore inhibitors for new idle notifier: Compositor does "' <<<"$create_body"
grep -Fq 'respectInhibitors = true;' <<<"$create_body"
assert_before "$create_body" \
  'qCWarning(logIdleNotify) << "Cannot ignore inhibitors for new idle notifier: Compositor does "' \
  'if (inputDevice == nullptr) {' \
  "the protocol-version fallback must be resolved before the seat lookup"

# 6. A missing seat (no last or default input device) yields nullptr - no
# crash, no retry loop, no polling wait for a seat to appear.
grep -Fq 'if (inputDevice == nullptr) {' <<<"$create_body"
grep -Fq 'qCCritical(logIdleNotify) << "Could not create idle notifier: No seat.";' <<<"$create_body"
grep -Fq 'return nullptr;' <<<"$create_body"
assert_before "$create_body" 'if (inputDevice == nullptr) {' 'return nullptr;' \
  "the seat-null check must precede returning nullptr"
assert_before "$create_body" 'qCCritical(logIdleNotify) << "Could not create idle notifier: No seat.";' 'return nullptr;' \
  "the no-seat critical log must precede returning nullptr"

# 7. respectInhibitors (after the version-guard above) selects the backend
# call exactly once, either way - get_idle_notification when true,
# get_input_idle_notification when false.
grep -Fq 'if (respectInhibitors) notification = this->get_idle_notification(timeout, inputDevice->object());' <<<"$create_body"
grep -Fq 'else notification = this->get_input_idle_notification(timeout, inputDevice->object());' <<<"$create_body"
assert_before "$create_body" 'if (inputDevice == nullptr) {' \
  'if (respectInhibitors) notification = this->get_idle_notification(timeout, inputDevice->object());' \
  "the seat lookup must precede the backend selection"

# 8. instance() itself never retries or polls for the manager to become
# available - a single lazily-constructed static instance, exposed as
# nullptr whenever it never finished initializing.
manager_instance_body=$(extract_function "$proto_cpp" "IdleNotificationManager* IdleNotificationManager::instance()")
grep -Fq 'return instance->isInitialized() ? instance : nullptr;' <<<"$manager_instance_body"

# 9. idled()/resumed() map directly onto isIdle with no debouncing, no
# additional condition, and no fallback-timer vocabulary anywhere in this
# file either.
idled_body=$(extract_function "$proto_cpp" "IdleNotification::ext_idle_notification_v1_idled()")
grep -Fq 'this->bIsIdle = true;' <<<"$idled_body"
resumed_body=$(extract_function "$proto_cpp" "IdleNotification::ext_idle_notification_v1_resumed()")
grep -Fq 'this->bIsIdle = false;' <<<"$resumed_body"

# 10. No polling/loop construct in the registration or creation entry
# points - matches the "bounded, event-driven, never a busy-wait" claim.
if grep -Eq '\b(while|for)\s*\(' <<<"$create_body"; then
  printf '%s\n' 'IdleNotificationManager::createIdleNotification unexpectedly contains a loop construct' >&2
  exit 1
fi

# 11. Process exposes a real, parameterless, untracked startDetached() -
# the exact reason scan-idle-executable-surface must reject it
# unconditionally, even against an otherwise-allowlisted argv: it launches
# whatever `command` already holds completely outside Quickshell's own
# tracking (no `running` transition to true, no `exited` ever possible).
grep -Fq 'Q_INVOKABLE void startDetached();' "$process_hpp"
start_detached_body=$(extract_function "$process_cpp" "void Process::startDetached()")
grep -Fq 'process.startDetached();' <<<"$start_detached_body"

# 12 & 13 both live inside Process::onFinished/Process::onErrorOccurred -
# the two real transitions the idle service's FailedToStart handling
# (requestLock/reconcileLockFailedToStart, and the probe/writer analogs)
# depends on.
on_finished_body=$(extract_function "$process_cpp" "void Process::onFinished(qint32 exitCode, QProcess::ExitStatus exitStatus)")
on_error_occurred_body=$(extract_function "$process_cpp" "void Process::onErrorOccurred(QProcess::ProcessError error)")

# 12. A normal finish (onFinished): the process handle is cleared BEFORE
# exited() is emitted, and exited() is emitted BEFORE runningChanged() -
# the exact ordering test/security-idle-qml-behavior.sh's fakeExit() is
# deliberately built to exercise in the REVERSE order (property change
# before the signal), proving the production callLater-based
# reconciliation is safe regardless of which order a real or fake caller
# uses.
grep -Fq 'this->process = nullptr;' <<<"$on_finished_body"
grep -Fq 'emit this->exited(exitCode, exitStatus);' <<<"$on_finished_body"
grep -Fq 'emit this->runningChanged();' <<<"$on_finished_body"
assert_before "$on_finished_body" 'this->process = nullptr;' 'emit this->exited(exitCode, exitStatus);' \
  "the process handle must be cleared before exited() is emitted"
assert_before "$on_finished_body" 'emit this->exited(exitCode, exitStatus);' 'emit this->runningChanged();' \
  "exited() must be emitted before runningChanged() on a normal finish"

# 13. A failed-to-start process (onErrorOccurred(QProcess::FailedToStart)):
# only runningChanged() is ever emitted - exited() is never reachable from
# this function at all. This is the entire reason the idle service cannot
# rely on an "onError" QML signal (none exists) and must instead detect
# the no-exit transition through running/runningChanged plus its own
# explicit per-operation awaiting-result state.
grep -Fq 'if (error == QProcess::FailedToStart)' <<<"$on_error_occurred_body"
grep -Fq 'this->process = nullptr;' <<<"$on_error_occurred_body"
grep -Fq 'emit this->runningChanged();' <<<"$on_error_occurred_body"
if grep -q 'emit this->exited(' <<<"$on_error_occurred_body"; then
  printf '%s\n' 'Process::onErrorOccurred unexpectedly emits exited() - FailedToStart must never emit it' >&2
  exit 1
fi

printf '%s\n' 'idle Quickshell ABI contract checks passed'
