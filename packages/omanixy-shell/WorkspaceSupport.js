function entries(workspaces, monitor) {
  if (!workspaces || !monitor) return []
  var visible = []
  for (var i = 0; i < workspaces.length; i++) {
    var workspace = workspaces[i]
    if (workspace && workspace.id > 0 && workspace.monitor === monitor) visible.push(workspace)
  }
  visible.sort(function(left, right) { return left.id - right.id })
  var result = []
  for (var j = 0; j < visible.length; j++) {
    result.push({
      id: visible[j].id,
      label: String(j + 1),
      workspace: visible[j]
    })
  }
  return result
}

if (typeof module !== "undefined") {
  module.exports = { entries }
}
