#!/usr/bin/env bash
set -euo pipefail

lock_compat_root=${1:?lock-enabled compatibility root required}
lock_quickshell=${2:?lock-enabled quickshell executable required}
disabled_compat_root=${3:?lock-disabled compatibility root required}
disabled_quickshell=${4:?lock-disabled quickshell executable required}


test_root=$(mktemp -d)
trap 'rm -rf "$test_root"' EXIT

run_harness() {
  local name=$1 compat_root=$2 quickshell=$3 shell_qml=$4 marker=$5
  local dir="$test_root/$name"
  mkdir -p "$dir/services" "$dir/home" "$dir/runtime"
  cp -R "$compat_root/shell/Commons" "$dir/Commons"
  chmod -R u+w "$dir/Commons"
  ln -s "$compat_root/shell" "$dir/qs"
  cp "$compat_root/shell/services/PluginRegistry.qml" "$dir/services/PluginRegistry.qml"
  printf '%s' "$shell_qml" >"$dir/shell.qml"
  HOME="$dir/home" XDG_RUNTIME_DIR="$dir/runtime" QML2_IMPORT_PATH="$dir" QT_QPA_PLATFORM=offscreen \
    timeout 10s "$quickshell" -n -p "$dir" >"$dir/quickshell.log" 2>&1 || true
  if ! grep -Fq "$marker" "$dir/quickshell.log"; then
    cat "$dir/quickshell.log" >&2
    exit 1
  fi
}

enabled_shell_qml='import QtQuick
import Quickshell
import qs.Commons
import "services"

ShellRoot {
  id: root
  property bool mutatorCalledNoManifest: false
  property bool mutatorCalledShadow: false

  property var registryNoManifest: PluginRegistry {
    installedPlugins: ({})
    shellConfigProvider: function() { return { disabledPlugins: ["omarchy.lock"] } }
    shellConfigMutator: function(fn) { root.mutatorCalledNoManifest = true }
  }

  // A hostile local plugin claiming the "omarchy.lock" id, shaped as a bar
  // option so it would otherwise short-circuit isEnabled through a
  // different branch entirely - the managed override must still win.
  property var registryShadow: PluginRegistry {
    installedPlugins: ({
      "omarchy.lock": { id: "omarchy.lock", kinds: ["bar"], __isFirstParty: false }
    })
    shellConfigProvider: function() { return { disabledPlugins: ["omarchy.lock"], bar: { id: "omarchy.bar" } } }
    shellConfigMutator: function(fn) { root.mutatorCalledShadow = true }
  }

  Component.onCompleted: {
    var enabledNoManifest = registryNoManifest.isEnabled("omarchy.lock")
    var disableNoManifest = registryNoManifest.setEnabled("omarchy.lock", false, {})
    var errorNoManifest = registryNoManifest.lastEnableError
    var enableNoManifest = registryNoManifest.setEnabled("omarchy.lock", true, {})

    var enabledShadow = registryShadow.isEnabled("omarchy.lock")
    var disableShadow = registryShadow.setEnabled("omarchy.lock", false, {})
    var errorShadow = registryShadow.lastEnableError
    var enableShadow = registryShadow.setEnabled("omarchy.lock", true, {})

    var ok = enabledNoManifest === true && disableNoManifest === false
      && errorNoManifest === "managed by Omanixy/Nix configuration"
      && root.mutatorCalledNoManifest === false && enableNoManifest === true
      && enabledShadow === true && disableShadow === false
      && errorShadow === "managed by Omanixy/Nix configuration"
      && root.mutatorCalledShadow === false && enableShadow === true

    if (ok) console.log("MANAGED_PLUGIN_PASS")
    else console.log("MANAGED_PLUGIN_FAIL", JSON.stringify([
      enabledNoManifest, disableNoManifest, errorNoManifest, root.mutatorCalledNoManifest, enableNoManifest,
      enabledShadow, disableShadow, errorShadow, root.mutatorCalledShadow, enableShadow,
    ]))
    Qt.quit()
  }
}
'

disabled_shell_qml='import QtQuick
import Quickshell
import qs.Commons
import "services"

ShellRoot {
  property var registry: PluginRegistry {
    installedPlugins: ({})
    shellConfigProvider: function() { return {} }
    shellConfigMutator: function(fn) {}
  }
  Component.onCompleted: {
    // No manifest, no shell.json entry, and nothing in disabledPlugins to
    // remove: the lock plugin simply does not exist when the capability is
    // off, so isEnabled must be false with or without user shell.json edits.
    var enabled = registry.isEnabled("omarchy.lock")
    if (enabled === false) console.log("MANAGED_PLUGIN_DISABLED_PASS")
    else console.log("MANAGED_PLUGIN_DISABLED_FAIL", enabled)
    Qt.quit()
  }
}
'

run_harness enabled "$lock_compat_root" "$lock_quickshell" "$enabled_shell_qml" MANAGED_PLUGIN_PASS
run_harness disabled "$disabled_compat_root" "$disabled_quickshell" "$disabled_shell_qml" MANAGED_PLUGIN_DISABLED_PASS

run_registry_scan_harness() {
  local compat_root=$1 quickshell=$2
  local dir="$test_root/registry-scan"
  mkdir -p "$dir/services" "$dir/home" "$dir/runtime" "$dir/firstparty" "$dir/thirdparty/evil-lock"
  cp -R "$compat_root/shell/Commons" "$dir/Commons"
  chmod -R u+w "$dir/Commons"
  ln -s "$compat_root/shell" "$dir/qs"
  cp "$compat_root/shell/services/PluginRegistry.qml" "$dir/services/PluginRegistry.qml"

  cp -R "$compat_root/shell/plugins/lock" "$dir/firstparty/lock"
  chmod -R u+w "$dir/firstparty/lock"

  cat >"$dir/thirdparty/evil-lock/manifest.json" <<'EOF'
{
  "schemaVersion": 1,
  "id": "omarchy.lock",
  "name": "Evil Lock",
  "version": "1.0.0",
  "kinds": ["service"],
  "entryPoints": { "service": "Hostile.qml" }
}
EOF

  local shell_qml
  shell_qml=$(cat <<QMLEOF
import QtQuick
import Quickshell
import qs.Commons
import "services"

ShellRoot {
  id: root
  property var registry: PluginRegistry {
    firstPartyDir: "$dir/firstparty"
    pluginsDir: "$dir/thirdparty"
    shellConfigProvider: function() { return {} }
    shellConfigMutator: function(fn) {}
  }
  Component.onCompleted: {
    registry.scanFinished.connect(function() {
      var manifest = registry.installedPlugins["omarchy.lock"]
      var url = manifest ? registry.entryPointUrl(manifest, "service") : ""
      var ok = manifest !== undefined
        && manifest.name === "Lock Screen"
        && manifest.__isFirstParty === true
        && manifest.__sourceDir === "$dir/firstparty/lock"
        && url.indexOf("$dir/firstparty/lock/") !== -1
        && url.indexOf("thirdparty") === -1
      if (ok) console.log("REGISTRY_SCAN_PASS")
      else console.log("REGISTRY_SCAN_FAIL", JSON.stringify({manifest: manifest, url: url}))
      Qt.quit()
    })
    registry.rescan()
  }
}
QMLEOF
)
  printf '%s' "$shell_qml" >"$dir/shell.qml"
  HOME="$dir/home" XDG_RUNTIME_DIR="$dir/runtime" QML2_IMPORT_PATH="$dir" QT_QPA_PLATFORM=offscreen \
    timeout 10s "$quickshell" -n -p "$dir" >"$dir/quickshell.log" 2>&1 || true
  if ! grep -Fq REGISTRY_SCAN_PASS "$dir/quickshell.log"; then
    cat "$dir/quickshell.log" >&2
    exit 1
  fi
}

run_registry_scan_harness "$lock_compat_root" "$lock_quickshell"

printf '%s\n' 'security lock managed-plugin checks passed'
