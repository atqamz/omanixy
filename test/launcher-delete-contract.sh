#!/usr/bin/env bash
set -euo pipefail

root=${1:?compatibility root path required}
runtime=${2:?runtime package path required}
repo=${3:?repository path required}

test -n "$runtime"
runtime_path=$(sed -n 's/^export PATH="\(.*\)"$/\1/p' "$runtime/bin/omanixy-shell-runtime")
test -n "$runtime_path"
test_root=$(mktemp -d)
trap 'rm -rf "$test_root"' EXIT
home="$test_root/home"
runtime_dir="$test_root/runtime"
config_root="$test_root/config"
mkdir -p "$home/.local/share/applications" "$test_root/bin" "$runtime_dir" "$config_root"
ln -s "$root/shell" "$test_root/qs"
ln -s "$root/shell/Commons" "$config_root/Commons"
ln -s "$root/shell/services" "$config_root/services"
ln -s "$root/shell/Ui" "$config_root/Ui"
ln -s "$root/shell/plugins" "$config_root/plugins"
ln -s "$root/shell/plugins/menu/MenuDeleteSupport.js" "$config_root/MenuDeleteSupport.js"
ln -s "$root/shell/plugins/menu/MenuDeleteBridge.qml" "$config_root/MenuDeleteBridge.qml"
printf '%s\n' '[Desktop Entry]' > "$home/.local/share/applications/org.example.User.desktop"
printf '%s\n' '[Desktop Entry]' > "$home/.local/share/applications/org.example.Target.desktop"
ln -s "$home/.local/share/applications/org.example.Target.desktop" \
  "$home/.local/share/applications/org.example.Symlink.desktop"
cat > "$test_root/bin/update-desktop-database" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$test_root/bin/update-desktop-database"
sed -i "1c#!$(command -v bash)" "$test_root/bin/update-desktop-database"
PATH="$test_root/bin:$root/bin:$runtime_path" \
  HOME="$home" XDG_DATA_HOME="$home/.local/share" \
  XDG_RUNTIME_DIR="$runtime_dir" \
  QT_QPA_PLATFORM=offscreen \
  QML2_IMPORT_PATH="$test_root" \
  "$root/bin/omarchy-remove-launcher-entry" org.example.User 'User app'
test ! -e "$home/.local/share/applications/org.example.User.desktop"
if PATH="$test_root/bin:$root/bin:$runtime_path" HOME="$home" XDG_DATA_HOME="$home/.local/share" \
  "$root/bin/omarchy-remove-launcher-entry" org.example.System 'System app'; then
  printf '%s\n' 'non-user launcher unexpectedly removed' >&2
  exit 1
fi

printf '%s\n' '[Desktop Entry]' > "$home/.local/share/applications/org.example.User.desktop"
cat > "$config_root/shell.qml" <<'EOF'
import QtQuick
import Quickshell
import Quickshell.Io
import "MenuDeleteSupport.js" as MenuDeleteSupport
Loader {
  id: root
  source: Quickshell.env("OMANIXY_APP_LIBRARY")
  property bool handled: false
  property string removedId: ""
  property bool confirmationOpen: false
  property var pendingRow: null
  property int refreshCount: 0
  function requestDelete(row) {
    if (!MenuDeleteSupport.canRequestDelete(row, item)) return false
    pendingRow = row
    confirmationOpen = true
    return true
  }
  function cancelDelete() {
    pendingRow = null
    confirmationOpen = false
  }
  function confirmDelete() {
    if (!confirmationOpen || !pendingRow) return false
    var row = pendingRow
    pendingRow = null
    confirmationOpen = false
    item.remove(row.appId, row.label)
    refreshCount++
    return true
  }
  function runScenario(appLibrary) {
    if (handled) return
    handled = true
    var userRow = ({kind: "app", appId: "org.example.User", label: "User app"})
    var systemRow = ({kind: "app", appId: "org.example.System", label: "System app"})
    var malformedRow = ({kind: "app", appId: "../escape", label: "Escape"})
    var missingRow = ({kind: "app", appId: "org.example.Missing", label: "Missing"})
    var traversalRow = ({kind: "app", appId: "../../escape", label: "Traversal"})
    var symlinkRow = ({kind: "app", appId: "org.example.Symlink", label: "Symlink"})
    var actionRow = ({kind: "action", appId: "org.example.User", label: "Action"})
    appLibrary.userOwnedEntryIds = ({})
    if (root.requestDelete(userRow) || root.requestDelete(systemRow)
        || root.requestDelete(malformedRow) || root.requestDelete(missingRow)
        || root.requestDelete(traversalRow) || root.requestDelete(symlinkRow)
        || root.requestDelete(actionRow) || root.confirmationOpen) {
      Qt.quit()
      return
    }
    appLibrary.userOwnedEntryIds = ({"org.example.User": true})
    if (!root.requestDelete(userRow) || !root.confirmationOpen) {
      Qt.quit()
      return
    }
    root.cancelDelete()
    if (root.confirmationOpen || !root.requestDelete(userRow) || !root.confirmDelete()
        || root.confirmationOpen || root.refreshCount !== 1) {
      Qt.quit()
      return
    }
    result.running = true
  }
  Process {
    id: result
    command: ["bash", "-c", "printf '%s\\n' allowed > " + Quickshell.env("RESULT_LOG")]
    running: true
    onExited: Qt.quit()
  }
  onLoaded: root.runScenario(item)
  Timer {
    interval: 2000
    running: true
    repeat: false
    onTriggered: {
      if (!handled && item)
        root.runScenario(item)
      if (!handled) Qt.quit()
    }
  }
}
EOF
printf '%s\n' '[Desktop Entry]' > "$home/.local/share/applications/org.example.User.desktop"
printf '%s\n' '[Desktop Entry]' > "$home/.local/share/applications/org.example.User.desktop"
RESULT_LOG="$test_root/result.log" \
  PATH="$test_root/bin:$root/bin:$runtime_path" \
  HOME="$home" XDG_DATA_HOME="$home/.local/share" \
  XDG_RUNTIME_DIR="$runtime_dir" \
  QT_QPA_PLATFORM=offscreen \
  OMANIXY_APP_LIBRARY="$config_root/services/AppLibrary.qml" \
  OMANIXY_MENU_BRIDGE="$config_root/MenuDeleteBridge.qml" \
  OMARCHY_PATH="$root" \
  timeout 10s "$runtime/bin/quickshell" -n -p "$config_root"
test -f "$test_root/result.log"
grep -Fxq allowed "$test_root/result.log"
test ! -e "$home/.local/share/applications/org.example.User.desktop"

printf '%s\n' 'launcher delete contract passed'
