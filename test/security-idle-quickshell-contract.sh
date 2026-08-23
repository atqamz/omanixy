#!/usr/bin/env bash
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

grep -Fq 'Q_OBJECT_BINDABLE_PROPERTY_WITH_ARGS(IdleMonitor, bool, bRespectInhibitors, true, &IdleMonitor::respectInhibitorsChanged);' "$monitor_hpp"

post_reload_body=$(extract_function "$monitor_cpp" "void IdleMonitor::onPostReload()")
grep -Fq 'return notification ? notification->bIsIdle.value() : false;' <<<"$post_reload_body"

update_notification_body=$(extract_function "$monitor_cpp" "void IdleMonitor::updateNotification()")

grep -Fq 'if (!manager) {' <<<"$update_notification_body"
grep -Fq 'qWarning() << "Cannot create idle monitor as ext-idle-notify-v1 is not supported by the "' <<<"$update_notification_body"
assert_before "$update_notification_body" 'if (!manager) {' 'return;' \
  "the no-manager warning must be checked before returning"
if grep -Eiq 'QTimer|startTimer|singleShot' "$monitor_cpp" "$proto_cpp"; then
  printf '%s\n' 'unexpected timer vocabulary found in the pinned idle_notify source - no fallback timer may exist' >&2
  exit 1
fi

grep -Fq 'auto timeout = static_cast<quint32>(std::max(0, static_cast<int>(params.timeout * 1000)));' <<<"$update_notification_body"
grep -Fq 'notification = manager->createIdleNotification(timeout, params.respectInhibitors);' <<<"$update_notification_body"
assert_before "$update_notification_body" \
  'auto timeout = static_cast<quint32>(std::max(0, static_cast<int>(params.timeout * 1000)));' \
  'notification = manager->createIdleNotification(timeout, params.respectInhibitors);' \
  "the timeout must be converted to milliseconds before being passed to createIdleNotification"

create_body=$(extract_function "$proto_cpp" "IdleNotificationManager::createIdleNotification(quint32 timeout, bool respectInhibitors)")

grep -Fq 'qCWarning(logIdleNotify) << "Cannot ignore inhibitors for new idle notifier: Compositor does "' <<<"$create_body"
grep -Fq 'respectInhibitors = true;' <<<"$create_body"
assert_before "$create_body" \
  'qCWarning(logIdleNotify) << "Cannot ignore inhibitors for new idle notifier: Compositor does "' \
  'if (inputDevice == nullptr) {' \
  "the protocol-version fallback must be resolved before the seat lookup"

grep -Fq 'if (inputDevice == nullptr) {' <<<"$create_body"
grep -Fq 'qCCritical(logIdleNotify) << "Could not create idle notifier: No seat.";' <<<"$create_body"
grep -Fq 'return nullptr;' <<<"$create_body"
assert_before "$create_body" 'if (inputDevice == nullptr) {' 'return nullptr;' \
  "the seat-null check must precede returning nullptr"
assert_before "$create_body" 'qCCritical(logIdleNotify) << "Could not create idle notifier: No seat.";' 'return nullptr;' \
  "the no-seat critical log must precede returning nullptr"

grep -Fq 'if (respectInhibitors) notification = this->get_idle_notification(timeout, inputDevice->object());' <<<"$create_body"
grep -Fq 'else notification = this->get_input_idle_notification(timeout, inputDevice->object());' <<<"$create_body"
assert_before "$create_body" 'if (inputDevice == nullptr) {' \
  'if (respectInhibitors) notification = this->get_idle_notification(timeout, inputDevice->object());' \
  "the seat lookup must precede the backend selection"

manager_instance_body=$(extract_function "$proto_cpp" "IdleNotificationManager* IdleNotificationManager::instance()")
grep -Fq 'return instance->isInitialized() ? instance : nullptr;' <<<"$manager_instance_body"

idled_body=$(extract_function "$proto_cpp" "IdleNotification::ext_idle_notification_v1_idled()")
grep -Fq 'this->bIsIdle = true;' <<<"$idled_body"
resumed_body=$(extract_function "$proto_cpp" "IdleNotification::ext_idle_notification_v1_resumed()")
grep -Fq 'this->bIsIdle = false;' <<<"$resumed_body"

if grep -Eq '\b(while|for)\s*\(' <<<"$create_body"; then
  printf '%s\n' 'IdleNotificationManager::createIdleNotification unexpectedly contains a loop construct' >&2
  exit 1
fi

grep -Fq 'Q_INVOKABLE void startDetached();' "$process_hpp"
start_detached_body=$(extract_function "$process_cpp" "void Process::startDetached()")
grep -Fq 'process.startDetached();' <<<"$start_detached_body"

on_finished_body=$(extract_function "$process_cpp" "void Process::onFinished(qint32 exitCode, QProcess::ExitStatus exitStatus)")
on_error_occurred_body=$(extract_function "$process_cpp" "void Process::onErrorOccurred(QProcess::ProcessError error)")

grep -Fq 'this->process = nullptr;' <<<"$on_finished_body"
grep -Fq 'emit this->exited(exitCode, exitStatus);' <<<"$on_finished_body"
grep -Fq 'emit this->runningChanged();' <<<"$on_finished_body"
assert_before "$on_finished_body" 'this->process = nullptr;' 'emit this->exited(exitCode, exitStatus);' \
  "the process handle must be cleared before exited() is emitted"
assert_before "$on_finished_body" 'emit this->exited(exitCode, exitStatus);' 'emit this->runningChanged();' \
  "exited() must be emitted before runningChanged() on a normal finish"

grep -Fq 'if (error == QProcess::FailedToStart)' <<<"$on_error_occurred_body"
grep -Fq 'this->process = nullptr;' <<<"$on_error_occurred_body"
grep -Fq 'emit this->runningChanged();' <<<"$on_error_occurred_body"
if grep -q 'emit this->exited(' <<<"$on_error_occurred_body"; then
  printf '%s\n' 'Process::onErrorOccurred unexpectedly emits exited() - FailedToStart must never emit it' >&2
  exit 1
fi

printf '%s\n' 'idle Quickshell ABI contract checks passed'
