#!/usr/bin/env bash
set -euo pipefail

if [[ ${1:-} != --session ]]; then
  provider=${1:?SNI provider path required}
  quickshell=${2:?Quickshell executable required}
  runtime=${3:?runtime package path required}
  compatibility_root=${4:?compatibility root path required}
  test_root=$(mktemp -d)
  trap 'rm -rf "$test_root"' EXIT
  dbus_config=${DBUS_SESSION_CONFIG:-/etc/dbus-1/session.conf}
  exec dbus-run-session --config-file="$dbus_config" -- "$BASH" "$0" --session "$provider" "$quickshell" "$runtime" "$compatibility_root" "$test_root"
fi

provider=${2:?SNI provider path required}
quickshell=${3:?Quickshell executable required}
runtime=${4:?runtime package path required}
compatibility_root=${5:?compatibility root path required}
test_root=${6:?test root required}
python=${PYTHON:-python3}
watcher_name=org.kde.StatusNotifierWatcher
item_name=org.omanixy.DeterministicStatusNotifierItem
passive_item_name=org.omanixy.PassiveStatusNotifierItem

cleanup() {
  for pid in ${quickshell_pid:-} ${active_item_pid:-} ${passive_item_pid:-} ${watcher_pid:-} ${broken_watcher_pid:-} ${rival_watcher_pid:-}; do
    kill "$pid" 2>/dev/null || true
  done
  wait 2>/dev/null || true
}
trap cleanup EXIT

wait_for_name() {
  local name=$1
  for _ in $(seq 1 100); do
    if busctl --user status "$name" >/dev/null 2>&1; then
      return 0
    fi
    sleep 0.05
  done
  return 1
}

wait_for_text() {
  local file=$1 text=$2
  for _ in $(seq 1 200); do
    if grep -Fq "$text" "$file"; then
      return 0
    fi
    sleep 0.05
  done
  cat "$file" >&2 || true
  return 1
}

wait_for_item() {
  local item=$1
  for _ in $(seq 1 100); do
    if busctl --user get-property "$watcher_name" /StatusNotifierWatcher "$watcher_name" RegisteredStatusNotifierItems 2>/dev/null | grep -Fq "$item"; then
      return 0
    fi
    sleep 0.05
  done
  busctl --user get-property "$watcher_name" /StatusNotifierWatcher "$watcher_name" RegisteredStatusNotifierItems >&2 || true
  return 1
}

watcher_owner() {
  busctl --user call org.freedesktop.DBus /org/freedesktop/DBus org.freedesktop.DBus GetNameOwner s "$watcher_name" \
    | sed -n 's/^s "\([^"]*\)"$/\1/p'
}

start_provider() {
  local mode=$1 log=$2
  SNI_MARKER="$log.marker" "$python" "$provider" "$mode" >"$log" 2>&1 &
  provider_pid=$!
}

test ! -e "$runtime/bin/sni-provider.py"
test ! -e "$runtime/bin/sni-contract.sh"
grep -Fq 'if (item.status === Status.Passive) continue' "$compatibility_root/shell/plugins/bar/widgets/Tray.qml"

start_provider watcher "$test_root/watcher.log"
watcher_pid=$provider_pid
wait_for_name "$watcher_name"
owner=$(watcher_owner)
test -n "$owner"
busctl --user status "$watcher_name" | grep -Fq "$owner"
busctl --user get-property "$watcher_name" /StatusNotifierWatcher "$watcher_name" RegisteredStatusNotifierItems | grep -Fq ' 0'

start_provider item "$test_root/item.log"
active_item_pid=$provider_pid
wait_for_item "$item_name"
busctl --user get-property "$item_name" /StatusNotifierItem org.kde.StatusNotifierItem Status | grep -Fq 'Active'
busctl --user get-property "$item_name" /StatusNotifierItem org.kde.StatusNotifierItem IconName | grep -Fq 'network-wired'
busctl --user get-property "$item_name" /StatusNotifierItem org.kde.StatusNotifierItem Menu | grep -Fq '/Menu'
busctl --user call "$item_name" /Menu com.canonical.dbusmenu GetLayout iias 0 1 0 | grep -Fq 'Activate deterministic item'

start_provider passive-item "$test_root/passive-item.log"
passive_item_pid=$provider_pid
wait_for_item "$passive_item_name"
busctl --user get-property "$passive_item_name" /StatusNotifierItem org.kde.StatusNotifierItem Status | grep -Fq 'Passive'

busctl --user call "$item_name" /StatusNotifierItem org.kde.StatusNotifierItem Activate ii 0 0
wait_for_text "$test_root/item.log.marker" ACTIVATED
busctl --user call "$item_name" /Menu com.canonical.dbusmenu Event usva{sv} 0 clicked s "" 0
wait_for_text "$test_root/item.log.marker" MENU_CLICKED

start_provider rival-watcher "$test_root/rival-watcher.log"
rival_watcher_pid=$provider_pid
if wait "$rival_watcher_pid"; then
  printf '%s\n' 'competing watcher unexpectedly acquired the well-known name' >&2
  exit 1
fi
wait_for_name "$watcher_name"

kill "$watcher_pid"
wait "$watcher_pid" || true
for _ in $(seq 1 100); do
  if ! busctl --user status "$watcher_name" >/dev/null 2>&1; then
    break
  fi
  sleep 0.05
done

start_provider broken-watcher "$test_root/broken-watcher.log"
broken_watcher_pid=$provider_pid
wait_for_name "$watcher_name"
if busctl --user get-property "$watcher_name" /StatusNotifierWatcher "$watcher_name" RegisteredStatusNotifierItems >/dev/null 2>&1; then
  printf '%s\n' 'invalid watcher unexpectedly exposed the watcher object' >&2
  exit 1
fi
kill "$broken_watcher_pid"
wait "$broken_watcher_pid" || true

start_provider watcher-recovery "$test_root/watcher-recovery.log"
watcher_pid=$provider_pid
wait_for_name "$watcher_name"
wait_for_item "$item_name"

kill "$passive_item_pid"
wait "$passive_item_pid" || true
kill "$active_item_pid"
wait "$active_item_pid" || true

kill "$watcher_pid"
wait "$watcher_pid" || true

mkdir -p "$test_root/home" "$test_root/runtime"
cp "$compatibility_root/shell/plugins/bar/widgets/TrayModel.js" "$test_root/TrayModel.js"
cat > "$test_root/sni.qml" <<EOF
import QtQuick
import Quickshell
import Quickshell.Services.SystemTray
import "TrayModel.js" as TrayModel

ShellRoot {
  id: root
  property bool observed: false

  Timer {
    interval: 50
    repeat: true
    running: true
    onTriggered: {
      var active = false
      var passive = false
      var items = SystemTray.items.values
      if (TrayModel.ownedByOmarchy({id: "omanixy-deterministic-sni"}, {})) {
        console.log("SNI_OWNERSHIP_FAIL")
        Qt.quit()
        return
      }
      for (var i = 0; i < items.length; i++) {
        if (items[i].id === "omanixy-deterministic-sni") active = true
        if (items[i].id === "omanixy-passive-sni") passive = true
      }
      if (active && passive && !root.observed) {
        root.observed = true
        console.log("SNI_QUICKSHELL_OBSERVED")
      } else if (root.observed && !active) {
        console.log("SNI_QUICKSHELL_UNREGISTERED")
        Qt.quit()
      }
    }
  }
}
EOF

start_provider item "$test_root/quickshell-item.log"
active_item_pid=$provider_pid
start_provider passive-item "$test_root/quickshell-passive-item.log"
passive_item_pid=$provider_pid

QT_QPA_PLATFORM=offscreen HOME="$test_root/home" XDG_RUNTIME_DIR="$test_root/runtime" \
  timeout 15s "$quickshell" -n -p "$test_root/sni.qml" >"$test_root/quickshell.log" 2>&1 &
quickshell_pid=$!
wait_for_name "$watcher_name"
owner=$(watcher_owner)
test -n "$owner"
busctl --user status "$watcher_name" | grep -Fq "$owner"
wait_for_text "$test_root/quickshell.log" SNI_QUICKSHELL_OBSERVED

busctl --user call "$item_name" /StatusNotifierItem org.kde.StatusNotifierItem Activate ii 0 0
wait_for_text "$test_root/quickshell-item.log.marker" ACTIVATED
busctl --user call "$item_name" /Menu com.canonical.dbusmenu Event usva{sv} 0 clicked s "" 0
wait_for_text "$test_root/quickshell-item.log.marker" MENU_CLICKED

kill "$active_item_pid"
wait "$active_item_pid" || true
wait_for_text "$test_root/quickshell.log" SNI_QUICKSHELL_UNREGISTERED
wait "$quickshell_pid" || true

start_provider item "$test_root/restarted-item.log"
active_item_pid=$provider_pid
QT_QPA_PLATFORM=offscreen HOME="$test_root/home" XDG_RUNTIME_DIR="$test_root/runtime" \
  timeout 15s "$quickshell" -n -p "$test_root/sni.qml" >"$test_root/restarted-quickshell.log" 2>&1 &
quickshell_pid=$!
wait_for_name "$watcher_name"
owner=$(watcher_owner)
test -n "$owner"
busctl --user status "$watcher_name" | grep -Fq "$owner"
wait_for_text "$test_root/restarted-quickshell.log" SNI_QUICKSHELL_OBSERVED
test "$(busctl --user status "$watcher_name" | grep -c '^   [0-9a-f]* ' || true)" -ge 1

printf '%s\n' 'SNI contract passed'
