function normalizeDesktopId(value) {
  var id = String(value || "").trim()
  if (id.slice(-8) === ".desktop") id = id.slice(0, -8)
  return id
}

function isValidDesktopId(value) {
  var id = normalizeDesktopId(value)
  return /^[A-Za-z0-9][A-Za-z0-9 _.@+-]*$/.test(id)
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
  return "uwsm app -- gtk-launch " + shellQuote(id + ".desktop")
}

function entryIdentities(entry) {
  if (!entry) return []
  var values = [entry.id, entry.startupClass]
  var identities = []
  for (var i = 0; i < values.length; i++) {
    var identity = normalizeDesktopId(values[i])
    if (identity && identities.indexOf(identity) === -1) identities.push(identity)
  }
  return identities
}

function matchStrength(entry, appId) {
  var candidate = normalizeDesktopId(appId)
  if (!candidate) return 0
  var identities = entryIdentities(entry)
  for (var i = 0; i < identities.length; i++) {
    if (identities[i] === candidate) return 2
  }
  var folded = candidate.toLowerCase()
  for (var j = 0; j < identities.length; j++) {
    if (identities[j].toLowerCase() === folded) return 1
  }
  return 0
}

function findMatchingToplevel(entry, toplevels) {
  var values = toplevels || []
  var exact = []
  var folded = []
  for (var i = 0; i < values.length; i++) {
    var toplevel = values[i]
    var strength = matchStrength(entry, toplevel && toplevel.appId)
    if (strength === 2) exact.push(toplevel)
    else if (strength === 1) folded.push(toplevel)
  }
  if (exact.length === 1) return exact[0]
  if (exact.length > 1) return null
  return folded.length === 1 ? folded[0] : null
}

if (typeof module !== "undefined") {
  module.exports = {
    normalizeDesktopId,
    isValidDesktopId,
    canRemove,
    launchCommand,
    entryIdentities,
    matchStrength,
    findMatchingToplevel
  }
}
