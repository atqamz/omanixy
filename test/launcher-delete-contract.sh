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
cp -R "$root/shell/plugins/menu" "$config_root/menu"
chmod -R u+w "$config_root/menu"
sed -i '0,/PanelWindow {/s//Item {/' "$config_root/menu/Menu.qml"
sed -i -e '/color: "transparent"/d' -e '/WlrLayershell\./d' \
  -e '/exclusionMode:/d' -e '/layer:/d' -e '/keyboardFocus:/d' \
  -e '/anchors { top: true; bottom: true; left: true; right: true }/d' "$config_root/menu/Menu.qml"
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

Loader {
  id: root
  source: Quickshell.env("OMANIXY_APP_LIBRARY")
  property bool handled: false
  property int attempts: 0

  function runScenario(menu) {
    if (handled || !item) return
    handled = true
    menu.shell = ({appLibrary: item})
    menu.openExistingMenu("apps")
    menu.filterText = "User"
    menu.rebuildDisplay()
    menu.selectedIndex = 0
    menu.cursorActive = true
    if (!item.canRemove("org.example.Missing") || !item.canRemove("org.example.Symlink")
        || item.canRemove("../escape") || item.canRemove("../../escape")) {
      Qt.quit()
      return
    }
    menu.requestDeleteSelected()
    if (!menu.deleteConfirmOpen) {
      Qt.quit()
      return
    }
    menu.cancelDelete()
    menu.openExistingMenu("apps")
    menu.filterText = "User"
    menu.rebuildDisplay()
    menu.selectedIndex = 0
    menu.cursorActive = true
    menu.requestDeleteSelected()
    if (!menu.deleteConfirmOpen) {
      Qt.quit()
      return
    }
    menu.confirmDelete()
    item.refreshUserOwnedEntries()
    result.running = true
  }

  Process {
    id: result
    command: ["bash", "-c", "printf '%s\\n' allowed > " + Quickshell.env("RESULT_LOG")]
    onExited: Qt.quit()
  }

  Loader {
    id: menuLoader
    source: Quickshell.env("OMANIXY_MENU")
    onLoaded: {
      if (item && root.item) root.item.loadUserOwnedEntries("org.example.User.desktop\\n")
      if (item && root.item) root.runScenario(item)
    }
  }

  Timer {
    interval: 100
    running: true
    repeat: true
    onTriggered: {
      attempts++
      if (item && attempts === 10 && item.loadUserOwnedEntries)
        item.loadUserOwnedEntries("org.example.User.desktop\\n")
      if (menuLoader.item && item && (item.userOwnedEntryIds["org.example.User"] === true || attempts >= 10))
        root.runScenario(menuLoader.item)
    }
  }
}
EOF
RESULT_LOG="$test_root/result.log" \
  PATH="$test_root/bin:$root/bin:$runtime_path" \
  HOME="$home" XDG_DATA_HOME="$home/.local/share" \
  XDG_RUNTIME_DIR="$runtime_dir" \
  QT_QPA_PLATFORM=offscreen \
  OMANIXY_APP_LIBRARY="$config_root/services/AppLibrary.qml" \
  OMANIXY_MENU="$config_root/menu/Menu.qml" \
  OMARCHY_PATH="$root" \
  timeout 10s "$runtime/bin/quickshell" -n -p "$config_root"
test -f "$test_root/result.log"
grep -Fxq allowed "$test_root/result.log"
test ! -e "$home/.local/share/applications/org.example.User.desktop"

printf '%s\n' 'launcher delete contract passed'
