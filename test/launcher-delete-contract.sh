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
ln -s "$root/shell" "$test_root/qs"
ln -s "$root/shell/Commons" "$config_root/Commons"
ln -s "$root/shell/services" "$config_root/services"
printf '%s\n' '[Desktop Entry]' > "$home/.local/share/applications/org.example.User.desktop"
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

cat > "$config_root/shell.qml" <<'EOF'
import QtQuick
import Quickshell

Loader {
  source: Quickshell.env("OMANIXY_APP_LIBRARY")
  property int attempts: 0
  property bool requested: false
  onLoaded: {
    if (item) {
      item.omarchyPath = Quickshell.env("OMARCHY_PATH")
      item.userOwnedEntryIds = ({"org.example.User": true})
    }
  }
  Timer {
    interval: 50
    running: true
    repeat: true
    onTriggered: {
      attempts++
      if (!requested && item && item.canRemove("org.example.User")) {
        item.remove("org.example.User", "User app")
        requested = true
      } else if (requested && attempts >= 20) {
        Qt.quit()
      }
    }
  }
}
EOF
printf '%s\n' '[Desktop Entry]' > "$home/.local/share/applications/org.example.User.desktop"
PATH="$test_root/bin:$root/bin:$runtime_path" \
  HOME="$home" XDG_DATA_HOME="$home/.local/share" \
  XDG_RUNTIME_DIR="$runtime_dir" \
  QT_QPA_PLATFORM=offscreen \
  OMANIXY_APP_LIBRARY="$config_root/services/AppLibrary.qml" \
  OMARCHY_PATH="$root" \
  timeout 10s "$runtime/bin/quickshell" -n -p "$config_root"
for _ in {1..20}; do
  test ! -e "$home/.local/share/applications/org.example.User.desktop" && break
  sleep 0.1
done
test ! -e "$home/.local/share/applications/org.example.User.desktop"

printf '%s\n' 'launcher delete contract passed'
