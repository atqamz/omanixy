#!/usr/bin/env bash
# Static source-contract evidence against the pinned Quickshell
# Quickshell.Services.Notifications NotificationServer ABI
# (src/services/notifications/{server,qml}.{cpp,hpp}), proving the
# properties the Layer-7 ADR and ledger rely on: registration targets
# exactly /org/freedesktop/Notifications and org.freedesktop.Notifications,
# a registration conflict is a bounded diagnostic (never a replace/kill),
# the service watcher retries registration purely event-driven on
# serviceUnregistered (never on a polling timer/loop), and keepOnReload is
# immutable once the server has been started.
#
# This is pinned third-party C++ source we do not own or patch; the point of
# this test is to catch drift in our own understanding (or in the pinned
# revision itself) against the exact ABI evidence recorded in the ADR and
# ledger, not to modify or re-implement any of it. Real live D-Bus
# collision/takeover-after-owner-exits evidence is explicitly deferred to
# Layer 8.
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

# 1. Constructor: session bus, registers the exact object path, watches the
# exact service name, then attempts registration exactly once.
ctor_body=$(extract_function "$server_cpp" "NotificationServer::NotificationServer()")
grep -Fq 'auto bus = QDBusConnection::sessionBus();' <<<"$ctor_body"
grep -Fq 'bus.registerObject("/org/freedesktop/Notifications", this)' <<<"$ctor_body"
grep -Fq 'this->serviceWatcher.addWatchedService("org.freedesktop.Notifications");' <<<"$ctor_body"
grep -Fq 'NotificationServer::tryRegister();' <<<"$ctor_body"
assert_before "$ctor_body" 'bus.registerObject("/org/freedesktop/Notifications", this)' \
  'NotificationServer::tryRegister();' \
  "the D-Bus object must be registered before the first registration attempt"

# 2. The watcher is configured to fire only on unregistration (never a
# generic ownership-changed poll) and is wired to onServiceUnregistered,
# which itself only calls tryRegister() again - purely event-driven.
grep -Fq 'this->serviceWatcher.setWatchMode(QDBusServiceWatcher::WatchForUnregistration);' <<<"$ctor_body"
grep -Fq '&QDBusServiceWatcher::serviceUnregistered,' <<<"$ctor_body"
grep -Fq '&NotificationServer::onServiceUnregistered' <<<"$ctor_body"

# 3. tryRegister(): registerService is the ONLY registration primitive used
# - no "replace existing owner" flag, no queueing option - success logs
# info; failure logs a bounded, one-shot diagnostic and explicitly commits
# to retrying only "if the active service is unregistered" (i.e. the
# serviceUnregistered signal above), never a poll/retry loop of its own.
try_register_body=$(extract_function "$server_cpp" "void NotificationServer::tryRegister()")
grep -Fq 'bus.registerService("org.freedesktop.Notifications")' <<<"$try_register_body"
grep -Fq 'Could not register notification server at org.freedesktop.Notifications, presumably' <<<"$try_register_body"
grep -Fq 'Registration will be attempted again if the active service is unregistered.' <<<"$try_register_body"
# (replacesId/replaces_id is the ordinary FDO Notify() parameter, not a
# takeover primitive, so it is deliberately not matched here.)
if grep -Eiq 'ReplaceExistingName|\bkill\b|pkill|terminate|\.stop\(\)' "$server_cpp"; then
  printf '%s\n' 'unexpected replace/kill/terminate vocabulary found in the pinned notifications server source' >&2
  exit 1
fi

# 4. onServiceUnregistered does exactly one thing: call tryRegister() again.
# No timer/loop vocabulary anywhere in this file - registration is
# event-driven only, exactly like security.idle's IdleMonitor and
# security.polkit's PolkitAgent before it.
on_unregistered_body=$(extract_function "$server_cpp" "void NotificationServer::onServiceUnregistered")
grep -Fq 'NotificationServer::tryRegister();' <<<"$on_unregistered_body"
# Scoped to the registration path itself (constructor, tryRegister,
# onServiceUnregistered) rather than the whole file: switchGeneration
# legitimately range-for's over an already-known notification list, which
# is iteration, not polling/retrying for a D-Bus name.
if grep -Eiq 'QTimer|startTimer|singleShot|while\s*\(|for\s*\(' <<<"$ctor_body"$'\n'"$try_register_body"$'\n'"$on_unregistered_body"; then
  printf '%s\n' 'unexpected timer/loop vocabulary found in the pinned notifications registration path - it must stay event-driven' >&2
  exit 1
fi

# 5. Notify(): replacesId != 0 reuses the existing idMap object when
# present - the exact identity-preservation contract the adapted Service.qml
# and NotificationLogic.replacementSnapshot rely on.
notify_body=$(extract_function "$server_cpp" "uint NotificationServer::Notify(")
grep -Fq 'auto* notification = replacesId == 0 ? nullptr : this->idMap.value(replacesId);' <<<"$notify_body"
grep -Fq 'auto old = notification != nullptr;' <<<"$notify_body"

# 6. keepOnReload is immutable once the server has gone live - matches the
# ADR's pinned-semantics claim that generation switching, not keeping old
# QObject references alive across reloads, is how restart safety is
# achieved.
set_keep_on_reload_body=$(extract_function "$qml_cpp" "void NotificationServerQml::setKeepOnReload(bool keepOnReload)")
grep -Fq 'if (this->live) {' <<<"$set_keep_on_reload_body"
grep -Fq 'Cannot set NotificationServer.keepOnReload after the server has been started.' <<<"$set_keep_on_reload_body"

# 7. onPostReload calls switchGeneration with the QML wrapper's own
# keepOnReload flag, threading the reload/generation boundary through
# exactly one call, matching the ADR's generation-safety description.
post_reload_body=$(extract_function "$qml_cpp" "void NotificationServerQml::onPostReload()")
grep -Fq 'instance->switchGeneration(this->mKeepOnReload, ' <<<"$post_reload_body"

printf '%s\n' 'notifications Quickshell ABI contract checks passed'
