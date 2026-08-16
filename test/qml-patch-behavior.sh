#!/usr/bin/env bash
set -euo pipefail

root=${1:?compatibility root path required}
pinned_source=${2:?pinned source path required}
patcher=${3:?transparent-process patcher path required}
quickshell=${4:?selected Quickshell executable required}
python=${PYTHON:-python3}
test_root=$(mktemp -d)
trap 'chmod -R u+w "$test_root" 2>/dev/null || true; rm -rf "$test_root"' EXIT
mkdir -p "$test_root/home/.cache" "$test_root/runtime"

bar_fixture="$test_root/Bar.qml"
cp "$pinned_source/shell/plugins/bar/Bar.qml" "$bar_fixture"
chmod u+w "$bar_fixture"
"$python" "$patcher" "$bar_fixture"
sed -i 's/required property /property /g' "$bar_fixture"
sed -i -e 's/PanelWindow {/Item {/g' -e '/WlrLayershell\./d' -e '/exclusionMode:/d' -e '/layer:/d' -e '/keyboardFocus:/d' -e '/surfaceFormat:/d' "$bar_fixture"
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
find "$test_root/Ui" -type f -name '*.qml' -exec sed -i '/surfaceFormat:/d' {} +
sed -i '/surfaceFormat:/d' "$bar_fixture"
HOME="$test_root/home" XDG_RUNTIME_DIR="$test_root/runtime" QML2_IMPORT_PATH="$test_root" QT_QPA_PLATFORM=offscreen timeout 10s "$quickshell" -n -p "$test_root" >"$test_root/quickshell.log" 2>&1 || true
if ! grep -Fq 'QML_PATCH_PASS' "$test_root/quickshell.log"; then
  cat "$test_root/quickshell.log" >&2
  exit 1
fi

drift_fixture="$test_root/Bar-drift.qml"
cp "$pinned_source/shell/plugins/bar/Bar.qml" "$drift_fixture"
chmod u+w "$drift_fixture"
sed -i '0,/id: transparentForegroundProc/s//id: transparentForegroundProcDrift/' "$drift_fixture"
if "$python" "$patcher" "$drift_fixture"; then
  printf '%s\n' 'exact Bar.qml patch accepted source-shape drift' >&2
  exit 1
fi

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
