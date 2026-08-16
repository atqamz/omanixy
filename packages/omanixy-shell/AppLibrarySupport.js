function normalizeDesktopId(value) {
  var id = String(value || "").trim()
  if (id.slice(-8) === ".desktop") id = id.slice(0, -8)
  return id
}

function isValidDesktopId(value) {
  return /^[A-Za-z0-9][A-Za-z0-9_.@+-]*$/.test(normalizeDesktopId(value))
}

function hasEntry(entries, id) {
  if (!entries) return false
  if (typeof entries.has === "function") return entries.has(id)
  return entries[id] === true
}

function canRemove(value, entries) {
  var id = normalizeDesktopId(value)
  return isValidDesktopId(id) && hasEntry(entries, id)
}

function shellQuote(value) {
  return "'" + String(value).replace(/'/g, "'\\''") + "'"
}

function launchCommand(value) {
  var id = normalizeDesktopId(value)
  if (!isValidDesktopId(id)) return ""
  return "uwsm-app -- gtk-launch " + shellQuote(id + ".desktop")
}

if (typeof module !== "undefined") {
  module.exports = { normalizeDesktopId, isValidDesktopId, canRemove, launchCommand }
}
