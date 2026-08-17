#!/usr/bin/env bash
set -euo pipefail

root=${1:?compatibility root path required}
pinned_source=${2:?pinned source path required}
patcher=${3:?transparent-process patcher path required}
quickshell=${4:?selected Quickshell executable required}
menu_patcher=${5:?menu provider patcher path required}
python=${PYTHON:-python3}
test_root=$(mktemp -d)
trap 'chmod -R u+w "$test_root" 2>/dev/null || true; rm -rf "$test_root"' EXIT
mkdir -p "$test_root/home/.cache" "$test_root/runtime"

bar_fixture="$test_root/Bar.qml"
cp "$pinned_source/shell/plugins/bar/Bar.qml" "$bar_fixture"
chmod u+w "$bar_fixture"
"$python" "$patcher" "$bar_fixture"
test "$(grep -Fc 'id: transparentForegroundProc' "$bar_fixture")" -eq 0
test "$(grep -Fc 'omarchy-bar-text-color' "$bar_fixture")" -eq 0
test "$(grep -Fc 'id: barHiddenProbe' "$bar_fixture")" -eq 1
grep -Fq 'bar-off' "$bar_fixture"
pinned_processes=$(grep -Ec '^[[:space:]]*Process \{' "$pinned_source/shell/plugins/bar/Bar.qml")
patched_processes=$(grep -Ec '^[[:space:]]*Process \{' "$bar_fixture")
test "$patched_processes" -eq "$((pinned_processes - 1))"
sed -i 's/required property /property /g' "$bar_fixture"
"$python" - "$bar_fixture" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text()
replacements = {
    "component BarPanel: PanelWindow {": "component BarPanel: Item {",
    "component DragGhostPanel: PanelWindow {": "component DragGhostPanel: Item {",
    "component BarMoveGhostPanel: PanelWindow {": "component BarMoveGhostPanel: Item {",
    "    visible: !remapGuard.remapping": "    visible: true",
    "    ScreenMoveRemap {\n      id: remapGuard\n      window: barWindow\n    }\n\n": "",
    "    margins {\n      top: root.barHidden && root.position === \"top\" ? -root.barSize : 0\n      bottom: root.barHidden && root.position === \"bottom\" ? -root.barSize : 0\n      left: root.barHidden && root.position === \"left\" ? -root.barSize : 0\n      right: root.barHidden && root.position === \"right\" ? -root.barSize : 0\n    }\n\n": "",
    "    surfaceFormat.opaque: false\n": "",
    "    mask: Region {}\n": "",
    "    anchors {\n      top: root.position === \"top\" || root.vertical\n      bottom: root.position === \"bottom\" || root.vertical\n      left: root.position === \"left\" || !root.vertical\n      right: root.position === \"right\" || !root.vertical\n    }\n\n": "",
    "    anchors {\n      top: true\n      bottom: true\n      left: true\n      right: true\n    }\n\n": "",
}
for old, new in replacements.items():
    text = text.replace(old, new)
for prefix in ("    screen: modelData\n", "        screen: modelData\n", "        ghostScreen: modelData\n"):
    text = text.replace(prefix, "")
for line in (
    "    color: root.transparent ? \"transparent\" : root.background\n",
    "    color: \"transparent\"\n",
    "    exclusionMode: root.barHidden ? ExclusionMode.Ignore : ExclusionMode.Auto\n",
    "    exclusionMode: ExclusionMode.Ignore\n",
    "    WlrLayershell.namespace: \"omarchy-bar\"\n",
    "    WlrLayershell.namespace: \"omarchy-bar-drag-ghost\"\n",
    "    WlrLayershell.namespace: \"omarchy-bar-move-ghost\"\n",
    "    WlrLayershell.layer: WlrLayer.Top\n",
    "    WlrLayershell.layer: WlrLayer.Overlay\n",
    "    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None\n",
):
    text = text.replace(line, "")
path.write_text(text)
PY
cat > "$test_root/shell.qml" <<EOF
import QtQuick
import Quickshell
import Quickshell.Io
ShellRoot {
  id: root
  Item {
    Loader { id: bar; source: "$bar_fixture" }
    Timer {
      interval: 1000
      running: true
      onTriggered: {
        if (!bar.item || bar.item.transparentForeground !== bar.item.themeForeground || bar.item.barForeground !== bar.item.themeForeground)
          console.log("QML_PATCH_FAIL", bar.status, bar.item ? bar.item.transparentForeground : "no-item", bar.item ? bar.item.themeForeground : "no-item", bar.item ? bar.item.barForeground : "no-item")
        else
          console.log("QML_PATCH_PASS")
        Qt.quit()
      }
    }
  }
}
EOF
ln -s "$root/shell" "$test_root/qs"
cp -R "$root/shell/Commons" "$test_root/Commons"
cp -R "$root/shell/Ui" "$test_root/Ui"
cp "$root/shell/plugins/bar/BarModel.js" "$test_root/BarModel.js"
chmod -R u+w "$test_root/Commons" "$test_root/Ui" "$test_root/BarModel.js"
HOME="$test_root/home" XDG_RUNTIME_DIR="$test_root/runtime" QML2_IMPORT_PATH="$test_root" QT_QPA_PLATFORM=offscreen timeout 10s "$quickshell" -n -p "$test_root" >"$test_root/quickshell.log" 2>&1 || true
if ! grep -Fq 'QML_PATCH_PASS' "$test_root/quickshell.log"; then
  cat "$test_root/quickshell.log" >&2
  exit 1
fi

drift_fixture="$test_root/Bar-drift.qml"
cp "$pinned_source/shell/plugins/bar/Bar.qml" "$drift_fixture"
chmod u+w "$drift_fixture"
sed -i '0,/id: transparentForegroundProc/s//id: transparentForegroundProcDrift/' "$drift_fixture"
if "$python" "$patcher" "$drift_fixture" 2>"$test_root/drift-error"; then
  printf '%s\n' 'exact Bar.qml patch accepted source-shape drift' >&2
  exit 1
fi
grep -Fq 'expected exactly one transparent foreground Process block' "$test_root/drift-error"

menu_fixture="$test_root/Menu.qml"
cp "$pinned_source/shell/plugins/menu/Menu.qml" "$menu_fixture"
chmod u+w "$menu_fixture"
"$python" "$menu_patcher" "$menu_fixture"
test "$(grep -Fc 'omarchy-powerprofiles-list' "$menu_fixture")" -eq 0
test "$(grep -Fc 'omarchy-powerprofiles-set' "$menu_fixture")" -eq 0
test "$(grep -Fc 'omarchy-font-list' "$menu_fixture")" -eq 1

menu_drift_fixture="$test_root/Menu-drift.qml"
cp "$pinned_source/shell/plugins/menu/Menu.qml" "$menu_drift_fixture"
chmod u+w "$menu_drift_fixture"
sed -i '0,/powerprofilesctl get/s//powerprofilesctl get-drift/' "$menu_drift_fixture"
if "$python" "$menu_patcher" "$menu_drift_fixture" 2>"$test_root/menu-drift-error"; then
  printf '%s\n' 'exact Menu.qml patch accepted source-shape drift' >&2
  exit 1
fi
grep -Fq 'expected exactly one pinned power-profile provider block' "$test_root/menu-drift-error"

node - "$root" <<'NODE'
const assert = require("node:assert/strict")
const path = require("node:path")

const root = process.argv[2]
const model = require(path.join(root, "shell/plugins/panels/network/Model.js"))

assert.deepEqual(model.supportedDnsProviders(), ["DHCP", "Cloudflare", "Google"])
assert.deepEqual(
  model.filterWifiNetworks([
    { id: "open", security: 0 },
    { id: "enterprise-wpa2", security: 2 },
    { id: "enterprise-wpa", security: 3 },
    { id: "psk", security: 1 },
  ], 2, 3).map((network) => network.id),
  ["open", "psk"],
)
assert.equal(model.isEnterpriseSecurity(2, 2, 3), true)
assert.equal(model.isEnterpriseSecurity(1, 2, 3), false)

console.log("QML patch behavior checks passed")
NODE
