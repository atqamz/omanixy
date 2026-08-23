#!/usr/bin/env bash
set -euo pipefail

daemon_compat_root=${1:?daemon-enabled compatibility root required}
daemon_quickshell=${2:?daemon-enabled quickshell executable required}
disabled_compat_root=${3:?daemon-disabled compatibility root required}
disabled_quickshell=${4:?daemon-disabled quickshell executable required}

# Layer 7 (notifications) mirror of test/security-idle-managed-plugin.sh:
# proves the Nix-managed PluginRegistry.qml override with real QML behavior
# against the real generated file, and separately drives the real rescan()
# scan-and-merge algorithm against real fixture directories.

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
    shellConfigProvider: function() { return { disabledPlugins: ["omarchy.notifications"] } }
    shellConfigMutator: function(fn) { root.mutatorCalledNoManifest = true }
  }

  // A hostile local plugin claiming the "omarchy.notifications" id, shaped
  // as a bar option so it would otherwise short-circuit isEnabled through a
  // different branch entirely - the managed override must still win.
  property var registryShadow: PluginRegistry {
    installedPlugins: ({
      "omarchy.notifications": { id: "omarchy.notifications", kinds: ["bar"], __isFirstParty: false }
    })
    shellConfigProvider: function() { return { disabledPlugins: ["omarchy.notifications"], bar: { id: "omarchy.bar" } } }
    shellConfigMutator: function(fn) { root.mutatorCalledShadow = true }
  }

  Component.onCompleted: {
    var enabledNoManifest = registryNoManifest.isEnabled("omarchy.notifications")
    var disableNoManifest = registryNoManifest.setEnabled("omarchy.notifications", false, {})
    var errorNoManifest = registryNoManifest.lastEnableError
    var enableNoManifest = registryNoManifest.setEnabled("omarchy.notifications", true, {})

    var enabledShadow = registryShadow.isEnabled("omarchy.notifications")
    var disableShadow = registryShadow.setEnabled("omarchy.notifications", false, {})
    var errorShadow = registryShadow.lastEnableError
    var enableShadow = registryShadow.setEnabled("omarchy.notifications", true, {})

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
    // remove: the notifications plugin simply does not exist when the
    // capability is off, so isEnabled must be false with or without user
    // shell.json edits.
    var enabled = registry.isEnabled("omarchy.notifications")
    if (enabled === false) console.log("MANAGED_PLUGIN_DISABLED_PASS")
    else console.log("MANAGED_PLUGIN_DISABLED_FAIL", enabled)
    Qt.quit()
  }
}
'

run_harness enabled "$daemon_compat_root" "$daemon_quickshell" "$enabled_shell_qml" MANAGED_PLUGIN_PASS
run_harness disabled "$disabled_compat_root" "$disabled_quickshell" "$disabled_shell_qml" MANAGED_PLUGIN_DISABLED_PASS

# Drive the REAL PluginRegistry.qml scan-and-merge algorithm (rescan() -> the
# bash find/cat scanner it spawns -> parseScanOutput()) with real fixture
# directories. A hostile third-party plugin claims the reserved
# "omarchy.notifications" id; the real merge must reject it and keep the
# real first-party notifications manifest as the winner.
run_registry_scan_harness() {
  local compat_root=$1 quickshell=$2
  local dir="$test_root/registry-scan"
  mkdir -p "$dir/services" "$dir/home" "$dir/runtime" "$dir/firstparty" "$dir/thirdparty/evil-notifications"
  cp -R "$compat_root/shell/Commons" "$dir/Commons"
  chmod -R u+w "$dir/Commons"
  ln -s "$compat_root/shell" "$dir/qs"
  cp "$compat_root/shell/services/PluginRegistry.qml" "$dir/services/PluginRegistry.qml"

  # The real first-party notifications manifest and source tree, copied
  # verbatim - not a hand-authored stand-in for it.
  cp -R "$compat_root/shell/plugins/notifications" "$dir/firstparty/notifications"
  chmod -R u+w "$dir/firstparty/notifications"

  cat >"$dir/thirdparty/evil-notifications/manifest.json" <<'EOF'
{
  "schemaVersion": 1,
  "id": "omarchy.notifications",
  "name": "Evil Notifications",
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
      var manifest = registry.installedPlugins["omarchy.notifications"]
      var url = manifest ? registry.entryPointUrl(manifest, "service") : ""
      var ok = manifest !== undefined
        && manifest.name === "Notifications"
        && manifest.__isFirstParty === true
        && manifest.__sourceDir === "$dir/firstparty/notifications"
        && url.indexOf("$dir/firstparty/notifications/") !== -1
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

run_registry_scan_harness "$daemon_compat_root" "$daemon_quickshell"

printf '%s\n' 'security notifications managed-plugin checks passed'
