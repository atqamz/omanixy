#!/usr/bin/env bash
set -euo pipefail

pinned_source=${1:?pinned source path required}
root=${2:?compatibility root path required}
patcher=${3:?workspace widget patcher path required}
quickshell=${4:?selected Quickshell executable required}
support="$root/shell/plugins/bar/widgets/WorkspaceSupport.js"
python=${PYTHON:-python3}
test_root=$(mktemp -d)
trap 'rm -rf "$test_root"' EXIT

fixture="$test_root/Workspaces.qml"
cp "$pinned_source/shell/plugins/bar/widgets/Workspaces.qml" "$fixture"
chmod u+w "$fixture"
"$python" "$patcher" "$fixture"
cp "$support" "$test_root/WorkspaceSupport.js"

node - "$support" <<'JS'
const assert = require("node:assert/strict")
const support = require(process.argv[2])

const internal = { name: "eDP-1" }
const external = { name: "DP-1" }
const first = { id: 1, monitor: internal, active: false }
const active = { id: 9, monitor: internal, active: true }
const entries = support.entries([
  { id: 101, monitor: external, active: true },
  active,
  { id: -99, monitor: internal, active: false },
  first,
  { id: 5, monitor: internal, active: false }
], internal)

assert.deepEqual(entries.map(entry => ({
  id: entry.id,
  label: entry.label,
  active: entry.workspace.active
})), [
  { id: 1, label: "1", active: false },
  { id: 5, label: "2", active: false },
  { id: 9, label: "3", active: true }
])
assert.equal(entries[0].workspace, first)
assert.equal(entries[2].workspace, active)
assert.deepEqual(support.entries(null, internal), [])
assert.deepEqual(support.entries([first], null), [])
JS

mkdir -p "$test_root/home" "$test_root/runtime"
ln -s "$root/shell" "$test_root/qs"
cat > "$test_root/shell.qml" <<EOF
import QtQuick
import Quickshell

ShellRoot {
  Item { id: internal }
  Item { id: external }
  Loader {
    id: workspaceLoader
    source: "$fixture"
  }
  Timer {
    interval: 100
    repeat: true
    running: true
    property int attempts: 0
    onTriggered: {
      attempts++
      if (!workspaceLoader.item) {
        if (attempts < 50) return
        console.log("WORKSPACES_WIDGET_FAIL", "widget did not load")
        Qt.quit()
        return
      }
      workspaceLoader.item.workspaceMonitor = internal
      workspaceLoader.item.workspaceValues = [
        { id: 101, monitor: external, active: true, toplevels: { values: [] } },
        { id: 9, monitor: internal, active: true, toplevels: { values: [] } },
        { id: 1, monitor: internal, active: false, toplevels: { values: [] } },
        { id: 5, monitor: internal, active: false, toplevels: { values: [{}] } }
      ]
      var entries = workspaceLoader.item.workspaceEntries()
      if (entries.length === 3
          && entries[0].id === 1 && entries[0].label === "1"
          && entries[1].id === 5 && entries[1].label === "2"
          && entries[2].id === 9 && entries[2].label === "3"
          && entries[2].workspace.active) {
        console.log("WORKSPACES_WIDGET_PASS")
      } else {
        console.log("WORKSPACES_WIDGET_FAIL", JSON.stringify(entries))
      }
      Qt.quit()
    }
  }
}
EOF
HOME="$test_root/home" XDG_RUNTIME_DIR="$test_root/runtime" QML2_IMPORT_PATH="$test_root" \
  QT_QPA_PLATFORM=offscreen timeout 10s "$quickshell" -n -p "$test_root" \
  >"$test_root/quickshell.log" 2>&1 || true
grep -Fq 'WORKSPACES_WIDGET_PASS' "$test_root/quickshell.log" || {
  cat "$test_root/quickshell.log" >&2
  exit 1
}

drift_fixture="$test_root/Workspaces-drift.qml"
cp "$pinned_source/shell/plugins/bar/widgets/Workspaces.qml" "$drift_fixture"
chmod u+w "$drift_fixture"
sed -i '0,/function workspaceIds()/s//function workspaceIdsDrift()/' "$drift_fixture"
if "$python" "$patcher" "$drift_fixture" 2>"$test_root/drift-error"; then
  printf '%s\n' 'exact Workspaces.qml patch accepted source-shape drift' >&2
  exit 1
fi

printf '%s\n' 'workspace widget behavior passed'
