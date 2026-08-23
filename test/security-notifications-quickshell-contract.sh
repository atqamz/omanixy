#!/usr/bin/env bash
set -euo pipefail

quickshell_src=${1:?pinned Quickshell source root required}
notifications_dir=$quickshell_src/src/services/notifications

server_cpp=$notifications_dir/server.cpp
server_hpp=$notifications_dir/server.hpp
qml_cpp=$notifications_dir/qml.cpp

for f in "$server_cpp" "$server_hpp" "$qml_cpp"; do
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

ctor_body=$(extract_function "$server_cpp" "NotificationServer::NotificationServer()")
grep -Fq 'auto bus = QDBusConnection::sessionBus();' <<<"$ctor_body"
grep -Fq 'bus.registerObject("/org/freedesktop/Notifications", this)' <<<"$ctor_body"
grep -Fq 'this->serviceWatcher.addWatchedService("org.freedesktop.Notifications");' <<<"$ctor_body"
grep -Fq 'NotificationServer::tryRegister();' <<<"$ctor_body"
assert_before "$ctor_body" 'bus.registerObject("/org/freedesktop/Notifications", this)' \
  'NotificationServer::tryRegister();' \
  "the D-Bus object must be registered before the first registration attempt"

grep -Fq 'this->serviceWatcher.setWatchMode(QDBusServiceWatcher::WatchForUnregistration);' <<<"$ctor_body"
grep -Fq '&QDBusServiceWatcher::serviceUnregistered,' <<<"$ctor_body"
grep -Fq '&NotificationServer::onServiceUnregistered' <<<"$ctor_body"

try_register_body=$(extract_function "$server_cpp" "void NotificationServer::tryRegister()")
grep -Fq 'bus.registerService("org.freedesktop.Notifications")' <<<"$try_register_body"
grep -Fq 'Could not register notification server at org.freedesktop.Notifications, presumably' <<<"$try_register_body"
grep -Fq 'Registration will be attempted again if the active service is unregistered.' <<<"$try_register_body"
if grep -Eiq 'ReplaceExistingName|\bkill\b|pkill|terminate|\.stop\(\)' "$server_cpp"; then
  printf '%s\n' 'unexpected replace/kill/terminate vocabulary found in the pinned notifications server source' >&2
  exit 1
fi

on_unregistered_body=$(extract_function "$server_cpp" "void NotificationServer::onServiceUnregistered")
grep -Fq 'NotificationServer::tryRegister();' <<<"$on_unregistered_body"
if grep -Eiq 'QTimer|startTimer|singleShot|while\s*\(|for\s*\(' <<<"$ctor_body"$'\n'"$try_register_body"$'\n'"$on_unregistered_body"; then
  printf '%s\n' 'unexpected timer/loop vocabulary found in the pinned notifications registration path - it must stay event-driven' >&2
  exit 1
fi

notify_body=$(extract_function "$server_cpp" "uint NotificationServer::Notify(")
grep -Fq 'auto* notification = replacesId == 0 ? nullptr : this->idMap.value(replacesId);' <<<"$notify_body"
grep -Fq 'auto old = notification != nullptr;' <<<"$notify_body"

set_keep_on_reload_body=$(extract_function "$qml_cpp" "void NotificationServerQml::setKeepOnReload(bool keepOnReload)")
grep -Fq 'if (this->live) {' <<<"$set_keep_on_reload_body"
grep -Fq 'Cannot set NotificationServer.keepOnReload after the server has been started.' <<<"$set_keep_on_reload_body"

post_reload_body=$(extract_function "$qml_cpp" "void NotificationServerQml::onPostReload()")
grep -Fq 'instance->switchGeneration(this->mKeepOnReload, ' <<<"$post_reload_body"

printf '%s\n' 'notifications Quickshell ABI contract checks passed'
