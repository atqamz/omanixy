#!/usr/bin/env bash
set -euo pipefail

root=${1:?compatibility root path required}
runtime=${2:?runtime package path required}

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
import qs.Commons

ShellRoot {
  Item {
    id: root
    property var appLibrary: null
  property bool handled: false
  property int attempts: 0
  property int deleteAttempts: 0
  property string failureReason: ""

  function fail(reason) {
    if (failure.running || result.running) return
    handled = true
    failureReason = reason
    failure.command = ["bash", "-c", "printf '%s\\n' " + Util.shellQuote(root.failureReason) + " > " + Util.shellQuote(Quickshell.env("RESULT_LOG"))]
    failure.running = true
  }

  function runScenario(menu) {
    if (handled) return
    if (!root.appLibrary) {
      root.fail("app-library-not-loaded")
      return
    }
    handled = true
    menu.shell = ({appLibrary: root.appLibrary})
    menu.openExistingMenu("apps")
    menu.filterText = "User"
    menu.rebuildDisplay()
    menu.selectedIndex = 0
    menu.cursorActive = true
    if (!root.appLibrary.canRemove("org.example.User") || root.appLibrary.canRemove("org.example.System") || root.appLibrary.canRemove("org.example.Nix")
        || root.appLibrary.canRemove("org.example.Missing") || root.appLibrary.canRemove("org.example.Symlink")
        || root.appLibrary.canRemove("../escape") || root.appLibrary.canRemove("../../escape")) {
      root.fail("ownership-scan")
      return
    }
    if (root.appLibrary.userOwnedEntryIds["org.example.System"] === true
        || root.appLibrary.userOwnedEntryIds["org.example.Nix"] === true
        || root.appLibrary.userOwnedEntryIds["org.example.Symlink"] === true) {
      root.fail("ownership-classification")
      return
    }
    menu.requestDeleteSelected()
    if (!menu.deleteConfirmOpen) {
      root.fail("confirmation-not-open")
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
      root.fail("confirmation-not-reopen")
      return
    }
    menu.confirmDelete()
    root.appLibrary.refreshUserOwnedEntries()
    deletionTimer.start()
  }

  Process {
    id: result
    command: ["bash", "-c", "printf '%s\\n' allowed > " + Quickshell.env("RESULT_LOG")]
    onExited: Qt.quit()
  }

  Process {
    id: failure
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
    id: deletionTimer
    interval: 100
    repeat: true
    onTriggered: {
      root.deleteAttempts++
      if (!root.appLibrary.canRemove("org.example.User")) {
        stop()
        result.running = true
      } else if (root.deleteAttempts >= 50) {
        stop()
        root.fail("delete-not-refreshed")
      }
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
      else if (root.attempts >= 20)
        root.fail(menuLoader.item ? "app-library-not-loaded" : "menu-not-loaded")
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
  QML2_IMPORT_PATH="$test_root" \
  OMANIXY_APP_LIBRARY="$config_root/services/AppLibrary.qml" \
  OMANIXY_MENU="$config_root/menu/Menu.qml" \
  OMARCHY_PATH="$root" \
  timeout 10s "$runtime/bin/quickshell" -n -p "$config_root"
test -f "$test_root/result.log"
if ! grep -Fxq allowed "$test_root/result.log"; then
  cat "$test_root/result.log" >&2
  exit 1
fi
test ! -e "$home/.local/share/applications/org.example.User.desktop"

printf '%s\n' 'launcher delete contract passed'
