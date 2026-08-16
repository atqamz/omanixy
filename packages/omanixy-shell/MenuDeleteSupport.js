function canRequestDelete(row, appLibrary) {
  return !!row && row.kind === "app" && !!appLibrary && appLibrary.canRemove(row.appId)
}

if (typeof module !== "undefined") {
  module.exports = { canRequestDelete }
}
