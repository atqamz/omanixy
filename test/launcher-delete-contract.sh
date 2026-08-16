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
system_data="$test_root/system-data"
nix_data="$test_root/nix-store"
mkdir -p "$system_data/applications" "$nix_data/applications"
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
cat > "$home/.local/share/applications/org.example.User.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=User app
Exec=true
EOF
cat > "$home/.local/share/applications/org.example.Target.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Target app
Exec=true
EOF
cat > "$system_data/applications/org.example.System.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=System app
Exec=true
EOF
cat > "$nix_data/applications/org.example.Nix.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Nix app
Exec=true
EOF
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

cat > "$home/.local/share/applications/org.example.User.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=User app
Exec=true
EOF
cat > "$config_root/shell.qml" <<'EOF'
import QtQuick
import Quickshell
import Quickshell.Io

ShellRoot {
  Item {
    id: root
    property var appLibrary: null
  property bool handled: false
  property int attempts: 0

  function runScenario(menu) {
    if (handled || !root.appLibrary) return
    handled = true
    menu.shell = ({appLibrary: root.appLibrary})
    menu.openExistingMenu("apps")
    menu.filterText = "User"
    menu.rebuildDisplay()
    menu.selectedIndex = 0
    menu.cursorActive = true
    if (!root.appLibrary.canRemove("org.example.User") || !root.appLibrary.canRemove("org.example.System") || !root.appLibrary.canRemove("org.example.Nix")
        || !root.appLibrary.canRemove("org.example.Missing") || !root.appLibrary.canRemove("org.example.Symlink")
        || root.appLibrary.canRemove("../escape") || root.appLibrary.canRemove("../../escape")) {
      Qt.quit()
      return
    }
    if (root.appLibrary.userOwnedEntryIds["org.example.System"] === true
        || root.appLibrary.userOwnedEntryIds["org.example.Nix"] === true
        || root.appLibrary.userOwnedEntryIds["org.example.Symlink"] === true) {
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
    root.appLibrary.refreshUserOwnedEntries()
    result.running = true
  }

  Process {
    id: result
    command: ["bash", "-c", "printf '%s\\n' allowed > " + Quickshell.env("RESULT_LOG")]
    onExited: Qt.quit()
  }

  Loader {
    id: appLoader
    source: Quickshell.env("OMANIXY_APP_LIBRARY")
    onLoaded: root.appLibrary = item
  }

  Loader {
    id: menuLoader
    source: Quickshell.env("OMANIXY_MENU")
    onLoaded: {
      if (item && root.appLibrary && root.appLibrary.canRemove("org.example.User"))
        root.runScenario(item)
    }
  }

  Timer {
    id: scanTimer
    interval: 100
    running: true
    repeat: true
    onTriggered: {
      root.attempts++
      if (root.appLibrary && root.appLibrary.refreshUserOwnedEntries) root.appLibrary.refreshUserOwnedEntries()
      if (menuLoader.item && root.appLibrary && root.appLibrary.canRemove("org.example.User"))
        root.runScenario(menuLoader.item)
      else if (menuLoader.item && root.attempts >= 20)
        root.runScenario(menuLoader.item)
    }
  }

    Component.onCompleted: {
      appLoader.active = true
      menuLoader.active = true
      scanTimer.start()
    }
  }
}
EOF
RESULT_LOG="$test_root/result.log" \
  PATH="$test_root/bin:$root/bin:$runtime_path" \
  HOME="$home" XDG_DATA_HOME="$home/.local/share" \
  XDG_DATA_DIRS="$system_data:$nix_data" \
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
