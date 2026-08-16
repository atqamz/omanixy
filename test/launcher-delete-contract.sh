#!/usr/bin/env bash
set -euo pipefail

root=${1:?compatibility root path required}
runtime=${2:?runtime package path required}
node=${NODE:-node}

support="$root/shell/services/AppLibrarySupport.js"
test -f "$support"

"$node" - "$support" <<'NODE'
const assert = require("node:assert/strict")
const support = require(process.argv[2])

const userEntries = new Set(["org.example.User", "org.example.Space"])
assert.equal(support.isValidDesktopId("org.example.User"), true)
assert.equal(support.isValidDesktopId("../outside"), false)
assert.equal(support.isValidDesktopId(""), false)
assert.equal(support.canRemove("org.example.User", userEntries), true)
assert.equal(support.canRemove("org.example.System", userEntries), false)
assert.equal(support.canRemove("org.example.Missing", userEntries), false)
assert.equal(support.canRemove("org.example.Space.desktop", userEntries), true)
assert.equal(support.canRemove("org.example/Space", userEntries), false)
NODE

app_library="$root/shell/services/AppLibrary.qml"
menu="$root/shell/plugins/menu/Menu.qml"
grep -Fq 'canRemove' "$app_library"
grep -Fq 'root.appLibrary.canRemove' "$menu"
grep -Fq 'deleteConfirmOpen = true' "$menu"
grep -Fq 'deleteConfirm.handleKey' "$menu"
grep -Fq 'root.appLibrary.remove' "$menu"
grep -Fq 'appsChanged' "$app_library"
grep -Fq 'omarchy-remove-launcher-entry' "$app_library"
test -n "$runtime"

printf '%s\n' 'launcher delete contract passed'
