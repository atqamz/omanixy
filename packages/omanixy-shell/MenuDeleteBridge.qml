import QtQuick
import "MenuDeleteSupport.js" as MenuDeleteSupport

Item {
  property var appLibrary
  property bool confirmationOpen: false
  property var pendingRow: null
  property int refreshCount: 0

  function requestDelete(row) {
    if (!MenuDeleteSupport.canRequestDelete(row, appLibrary)) return false
    pendingRow = row
    confirmationOpen = true
    return true
  }

  function cancelDelete() {
    pendingRow = null
    confirmationOpen = false
  }

  function confirmDelete() {
    if (!confirmationOpen || !pendingRow) return false
    var row = pendingRow
    pendingRow = null
    confirmationOpen = false
    appLibrary.remove(row.appId, row.label)
    refreshCount++
    return true
  }
}
