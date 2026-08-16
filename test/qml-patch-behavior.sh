#!/usr/bin/env bash
set -euo pipefail

root=${1:?compatibility root path required}
pinned_source=${2:?pinned source path required}
patcher=${3:?transparent-process patcher path required}
python=${PYTHON:-python3}
test_root=$(mktemp -d)
trap 'rm -rf "$test_root"' EXIT

bar_fixture="$test_root/Bar.qml"
cp "$pinned_source/shell/plugins/bar/Bar.qml" "$bar_fixture"
chmod u+w "$bar_fixture"
"$python" "$patcher" "$bar_fixture"
if grep -Fq 'id: transparentForegroundProc' "$bar_fixture"; then
  printf '%s\n' 'exact Bar.qml patch left transparentForegroundProc in place' >&2
  exit 1
fi
grep -Fq 'id: barHiddenProbe' "$bar_fixture"

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
