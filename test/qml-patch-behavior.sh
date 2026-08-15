#!/usr/bin/env bash
set -euo pipefail

root=${1:?compatibility root path required}
node - "$root" <<'NODE'
const assert = require("node:assert/strict")
const fs = require("node:fs")
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

const registry = fs.readFileSync(path.join(root, "shell/services/PluginRegistry.qml"), "utf8")
const disabledGuard = registry.indexOf("omanixyBlockedPlugins.indexOf(Util.canonicalWidgetId(String(key))) !== -1")
const firstPartyEnable = registry.indexOf("if (manifest.__isFirstParty) return true")
assert.ok(disabledGuard >= 0 && disabledGuard < firstPartyEnable)
assert.match(registry, /omanixyBlockedPlugins = \[.*omarchy\.lock.*omarchy\.polkit/)

const clock = fs.readFileSync(path.join(root, "shell/plugins/panels/clock/BarWidget.qml"), "utf8")
assert.match(clock, /else if \(b === Qt\.MiddleButton\) root\.togglePanel\(\)/)
assert.doesNotMatch(clock, /omarchy-menu-timezone/)

const networkPanel = fs.readFileSync(path.join(root, "shell/plugins/panels/network/Panel.qml"), "utf8")
assert.match(networkPanel, /readonly property bool canRunSpeedTest: false/)
assert.doesNotMatch(networkPanel, /omarchy-launch-floating-terminal-with-presentation/)

const bar = fs.readFileSync(path.join(root, "shell/plugins/bar/Bar.qml"), "utf8")
assert.match(bar, /transparentForeground = themeForeground/)
assert.doesNotMatch(bar, /omarchy-bar-text-color/)
assert.doesNotMatch(bar, /transparentForegroundProc/)

const menu = fs.readFileSync(path.join(root, "shell/plugins/menu/Menu.qml"), "utf8")
assert.doesNotMatch(menu, /root\.requestDeleteSelected\(\)/)
assert.match(menu, /if \(event\.key === Qt\.Key_Delete\) \{\s+event\.accepted = true\s+\}/)

console.log("QML patch behavior checks passed")
NODE
