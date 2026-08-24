function semanticDesktopId(value) {
  return String(value || "")
}

function normalizeDesktopId(value) {
  return semanticDesktopId(value).trim()
}

function desktopFileId(value) {
  var id = semanticDesktopId(value)
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
  var id = semanticDesktopId(value)
  if (!id) return ""
  return "uwsm app -- gtk-launch " + shellQuote(id + ".desktop")
}

function entryIdentities(entry) {
  if (!entry) return []
  var values = [entry.id, entry.startupClass]
  var identities = []
  for (var i = 0; i < values.length; i++) {
    var identity = semanticDesktopId(values[i])
    if (identity && identities.indexOf(identity) === -1) identities.push(identity)
  }
  return identities
}

function matchStrength(entry, appId) {
  var candidate = semanticDesktopId(appId)
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

function matchingToplevels(entry, toplevels) {
  var values = toplevels || []
  var exact = []
  var folded = []
  for (var i = 0; i < values.length; i++) {
    var toplevel = values[i]
    var strength = matchStrength(entry, toplevel && toplevel.appId)
    if (strength === 2) exact.push(toplevel)
    else if (strength === 1) folded.push(toplevel)
  }
  return exact.length > 0 ? exact : folded
}

function findMatchingToplevel(entry, toplevels) {
  var matches = matchingToplevels(entry, toplevels)
  return matches.length === 1 ? matches[0] : null
}

function activationSucceeded(target, activeToplevel) {
  return !!target && (!!target.activated || activeToplevel === target)
}

function coldLaunchSucceeded(entry, toplevels, initialMatches, initialActiveToplevel, activeToplevel) {
  var matches = matchingToplevels(entry, toplevels)
  var initial = initialMatches || []
  for (var i = 0; i < matches.length; i++) {
    if (initial.indexOf(matches[i]) === -1) return true
  }
  return !!activeToplevel
    && activeToplevel !== initialActiveToplevel
    && matches.indexOf(activeToplevel) !== -1
}

if (typeof module !== "undefined") {
  module.exports = {
    semanticDesktopId,
    normalizeDesktopId,
    desktopFileId,
    isValidDesktopId,
    canRemove,
    launchCommand,
    entryIdentities,
    matchStrength,
    matchingToplevels,
    findMatchingToplevel,
    activationSucceeded,
    coldLaunchSucceeded
  }
}
