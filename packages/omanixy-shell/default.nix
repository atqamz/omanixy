{ lib
, pkgs
, omarchy
, quickshellSrc
, nixpkgsRevision
, supportedSystems
, features ? null
, security ? null
, launcher ? null
}:

assert lib.assertOneOf "omanixy supported system" pkgs.stdenv.hostPlatform.system supportedSystems;

let
  inherit (pkgs) stdenvNoCC;

  fontconfigFile = pkgs.makeFontsConf { fontDirectories = [ ]; };
  baselineSource = builtins.fromJSON (builtins.readFile ../../upstream/shell-baseline.json);
  featureSelection = import ../../lib/feature-selection.nix { inherit lib; baseline = baselineSource; };
  contractSource = builtins.fromJSON (builtins.readFile ../../upstream/compatibility-contracts.json);
  omarchyRevision = contractSource.pins.omarchy;
  quickshellRevision = contractSource.pins.quickshell;
  baselineConfig = builtins.removeAttrs baselineSource [ "featurePlugins" "featureDependencies" "featureOrder" "migrations" "featureCapabilities" "capabilityDependencies" ];
  launcherConfig = if launcher == null then { } else launcher;
  terminalPackage = launcherConfig.terminalPackage or pkgs.foot;
  terminalDesktop = launcherConfig.terminalDesktop or "foot.desktop";
  terminalDesktopValid = lib.assertMsg
    (builtins.isString terminalDesktop && terminalDesktop != "" && lib.hasSuffix ".desktop" terminalDesktop)
    "omanixy launcher terminal desktop must be a non-empty .desktop ID";
  capabilityRuntimeInputs = with pkgs; {
    "audio-control" = [ pipewire pulseaudio wireplumber ];
    "audio-default-output" = [ pipewire pulseaudio wireplumber ];
    "bluetooth-control" = [ bluez ];
    "clipboard-presentation" = [ gnugrep procps util-linux wl-clipboard wtype xdg-utils ];
    "core-runtime" = [ bash coreutils findutils fontconfig gawk gnugrep gnused hyprland inotify-tools jq procps systemd util-linux ];
    launcher = [ desktop-file-utils gtk3 uwsm terminalPackage xdg-terminal-exec ];
    "monitor-control" = [ brightnessctl fontconfig glib gtk3 hyprland libnotify procps ];
    "network-manager" = [ iproute2 iputils iw networkmanager qrencode ];
    "notification-send" = [ libnotify ];
    "power-control" = [ power-profiles-daemon upower ];
    "screenshot-capture" = [ fontconfig grim hyprland hyprpicker procps slurp ];
    "text-injection" = [ wtype ];
    "wayland-clipboard-write" = [ wl-clipboard ];
    "weather-network" = [ curl ];
  };
  lockEnabled = security != null && (security.lock or false);
  fingerprintEnabled = lockEnabled && security != null && (security.fingerprint or false);
  fingerprintPackage = if fingerprintEnabled then (security.fingerprintPackage or null) else null;
  fingerprintPackageValid = lib.assertMsg
    (!fingerprintEnabled || fingerprintPackage != null)
    "omanixy fingerprint security requires security.fingerprintPackage to be the NixOS-selected services.fprintd.package";
  polkitAgentEnabled = security != null && (security.polkitAgent or false);
  idleEnabled = security != null && (security.idle or false);
  idleRequiresLockValid = lib.assertMsg
    (!idleEnabled || lockEnabled)
    "omanixy idle security requires security.lock to also be true - Layer 6 owns no lock provider of its own";
  notificationDaemonEnabled = security != null && (security.notificationDaemon or false);
  managedEnabledSecurityPlugins = lib.optionals lockEnabled [ "omarchy.lock" ]
    ++ lib.optionals polkitAgentEnabled [ "omarchy.polkit" ]
    ++ lib.optionals idleEnabled [ "omarchy.idle" ]
    ++ lib.optionals notificationDaemonEnabled [ "omarchy.notifications" ];
  backgroundEnabled = security == null || (security.background or true);
  managedSecurityPluginIds = builtins.toJSON managedEnabledSecurityPlugins;
  externalExecutableCapabilities = contractSource.externalExecutableCapabilities or { };
  helperCapabilities = contractSource.helperCapabilities or { };
  allFeatures = featureSelection.featureNames;
  requestedFeatures = if features == null then allFeatures else features;
  selectedFeatures = featureSelection.select requestedFeatures;
  requestedPresentationFeatures = lib.filter (feature: feature != "core") selectedFeatures;
  selectedCapabilities = featureSelection.resolveCapabilities selectedFeatures;
  featureNamesValid = lib.assertMsg
    (featureSelection.validate requestedFeatures
      && lib.all (helper: builtins.hasAttr helper helperCapabilities) allCompatibilityHelpers
      && lib.all (capability: builtins.hasAttr capability capabilityRuntimeInputs) selectedCapabilities
      && lib.all (capability: builtins.hasAttr capability capabilityRuntimeInputs) (builtins.attrValues externalExecutableCapabilities)
      && lib.all (capability: builtins.hasAttr capability capabilityRuntimeInputs) (builtins.attrValues helperCapabilities)
      && !(lib.any (capability: capability == "host") (builtins.attrValues externalExecutableCapabilities)))
    "omanixy features must be a list of known feature names";

  quickshell = pkgs.quickshell.overrideAttrs (old: {
    pname = "quickshell-omanixy";
    version = "git-${lib.substring 0 7 quickshellRevision}";
    src = quickshellSrc;
    cmakeFlags =
      (lib.filter (flag: !(lib.hasInfix "GIT_REVISION" (toString flag))) (old.cmakeFlags or [ ]))
      ++ [ (lib.cmakeFeature "GIT_REVISION" quickshellRevision) ];
  });

  omarchySource = stdenvNoCC.mkDerivation {
    pname = "omarchy-quattro";
    version = lib.substring 0 12 omarchyRevision;
    src = omarchy;
    dontBuild = true;
    installPhase = ''
      mkdir -p "$out"
      cp -R ./. "$out/"
    '';
    meta = {
      description = "Pinned Omarchy Quattro source used by Omanixy";
      homepage = "https://github.com/basecamp/omarchy";
      license = lib.licenses.mit;
      platforms = supportedSystems;
    };
  };

  iconFont = stdenvNoCC.mkDerivation {
    pname = "omanixy-omarchy-icon-font";
    version = lib.substring 0 12 omarchyRevision;
    dontUnpack = true;
    installPhase = ''
      install -Dm644 ${omarchySource}/default/fonts/omarchy/omarchy.ttf "$out/share/fonts/omarchy/omarchy.ttf"
      install -Dm644 ${omarchySource}/default/fonts/omarchy/README.md "$out/share/doc/omanixy-omarchy-icon-font/README.md"
      install -Dm644 ${omarchySource}/LICENSE "$out/share/licenses/omanixy-omarchy-icon-font/LICENSE"
    '';
    meta = {
      description = "Pinned Omarchy icon font used by Omanixy Quattro";
      homepage = "https://github.com/basecamp/omarchy";
      license = lib.licenses.mit;
      platforms = supportedSystems;
    };
  };

  theme = stdenvNoCC.mkDerivation {
    pname = "omanixy-shell-theme";
    version = lib.substring 0 12 omarchyRevision;
    src = "${omarchySource}/themes/tokyo-night";
    dontBuild = true;
    installPhase = ''
      mkdir -p "$out"
      install -Dm644 colors.toml "$out/colors.toml"
      install -Dm644 backgrounds/1-quattro.jpg "$out/backgrounds/1-quattro.jpg"
      cat > "$out/shell.toml" <<'EOF'
      [bar]
      background = "background"
      background-alpha = 1.0
      text = "foreground"
      active = "urgent"

      [font]
      base-size = 12

      [spacing]
      scale = 1.0
      scale-with-font = true
      EOF
    '';
  };

  backgroundPatch = ../../scripts/patch-background;

  omittedFeaturePlugins = lib.concatLists (map
    (feature: baselineSource.featurePlugins.${feature} or [ ])
    (lib.filter (feature: !builtins.elem feature selectedFeatures) (builtins.attrNames baselineSource.featurePlugins)));
  runtimeBlockedPlugins = lib.subtractLists managedEnabledSecurityPlugins (lib.unique (baselineConfig.disabledPlugins ++ omittedFeaturePlugins ++ lib.optional (!backgroundEnabled) "omarchy.background"));
  blockedPluginIds = builtins.toJSON runtimeBlockedPlugins;
  safeMenuSource = builtins.fromJSON (builtins.readFile ./safe-menu.jsonc);
  safeMenuFeature = {
    apps = "launcher";
    "system.logout" = "launcher";
    "trigger.emoji" = "clipboard";
    "trigger.screenshot" = "screenshot";
  };
  selectedSafeMenu = lib.filterAttrs
    (name: _: !(builtins.hasAttr name safeMenuFeature)
      || builtins.elem safeMenuFeature.${name} selectedFeatures)
    safeMenuSource;
  safeMenu = pkgs.writeText "omanixy-safe-omarchy-menu.jsonc" (builtins.toJSON selectedSafeMenu);

  safeShellConfig = pkgs.writeText "omanixy-safe-shell.json" (builtins.toJSON baselineConfig);

  omarchyCompatibilityRoot = stdenvNoCC.mkDerivation {
    pname = "omanixy-omarchy-compat-root";
    version = lib.substring 0 12 omarchyRevision;
    dontUnpack = true;
    installPhase = ''
            empty=
            mkdir -p "$out/bin" "$out/config/omarchy" "$out/default/omarchy"
            mkdir -p "$out/shell"
            cp -R ${omarchySource}/shell/Commons "$out/shell/Commons"
            cp -R ${omarchySource}/shell/Ui "$out/shell/Ui"
            chmod u+w "$out/shell/Ui"
            chmod u+w "$out/shell/Ui/SpeedTestOverlay.qml"
            rm -f "$out/shell/Ui/SpeedTestOverlay.qml"
            cp -R ${omarchySource}/shell/services "$out/shell/services"
            install -Dm644 ${omarchySource}/shell/shell.qml "$out/shell/shell.qml"
            mkdir -p "$out/shell/plugins/bar/widgets"
            for file in Bar.qml BarModel.js manifest.json; do
              install -Dm644 "${omarchySource}/shell/plugins/bar/$file" "$out/shell/plugins/bar/$file"
            done
            for file in Spacer.qml Spacer.manifest.json Tray.qml Tray.manifest.json TrayModel.js Workspaces.qml Workspaces.manifest.json; do
              install -Dm644 "${omarchySource}/shell/plugins/bar/widgets/$file" "$out/shell/plugins/bar/widgets/$file"
            done

            for plugin in clipboard emojis menu osd; do
              cp -R "${omarchySource}/shell/plugins/$plugin" "$out/shell/plugins/$plugin"
            done
            mkdir -p "$out/shell/plugins/background"
            install -Dm644 ${omarchySource}/shell/plugins/background/manifest.json "$out/shell/plugins/background/manifest.json"
            install -Dm644 ${omarchySource}/shell/plugins/background/Background.qml "$out/shell/plugins/background/Background.qml"
            chmod u+w "$out/shell/plugins/background/Background.qml"
            ${pkgs.python3}/bin/python3 ${backgroundPatch} \
              "$out/shell/plugins/background/Background.qml"
            for plugin in audio bluetooth clock monitor network power weather wifiqr; do
              mkdir -p "$out/shell/plugins/panels/$plugin"
              cp -R "${omarchySource}/shell/plugins/panels/$plugin/." "$out/shell/plugins/panels/$plugin"
            done
            mkdir -p "$out/shell/plugins/services"
            cp -R ${omarchySource}/shell/plugins/services/media "$out/shell/plugins/services/media"
            ${lib.optionalString lockEnabled ''
            mkdir -p "$out/shell/plugins/lock"
            install -Dm644 ${omarchySource}/shell/plugins/lock/manifest.json "$out/shell/plugins/lock/manifest.json"
            install -Dm644 ${omarchySource}/shell/plugins/lock/LockView.qml "$out/shell/plugins/lock/LockView.qml"
            install -Dm644 ${omarchySource}/shell/plugins/lock/Service.qml "$out/shell/plugins/lock/Service.qml"
            chmod u+w "$out/shell/plugins/lock/Service.qml"
            ${lib.optionalString fingerprintEnabled ''
            install -Dm644 ${./FingerprintPolicy.js} "$out/shell/plugins/lock/FingerprintPolicy.js"
            ''}
            ${pkgs.python3}/bin/python3 ${../../scripts/patch-lock-service} \
              --fingerprint ${if fingerprintEnabled then "enabled" else "disabled"} \
              "$out/shell/plugins/lock/Service.qml"
            ''}
            ${lib.optionalString polkitAgentEnabled ''
            mkdir -p "$out/shell/plugins/polkit"
            install -Dm644 ${omarchySource}/shell/plugins/polkit/manifest.json "$out/shell/plugins/polkit/manifest.json"
            install -Dm644 ${omarchySource}/shell/plugins/polkit/PolkitAgent.qml "$out/shell/plugins/polkit/PolkitAgent.qml"
            install -Dm644 ${omarchySource}/shell/plugins/polkit/PolkitModel.js "$out/shell/plugins/polkit/PolkitModel.js"
            chmod u+w "$out/shell/plugins/polkit/PolkitAgent.qml" "$out/shell/plugins/polkit/PolkitModel.js"
            ${pkgs.python3}/bin/python3 ${../../scripts/patch-polkit-agent} \
              "$out/shell/plugins/polkit/PolkitAgent.qml" \
              "$out/shell/plugins/polkit/PolkitModel.js"
            ''}
            ${lib.optionalString idleEnabled ''
            mkdir -p "$out/shell/plugins/services/idle"
            install -Dm644 ${omarchySource}/shell/plugins/services/idle/manifest.json "$out/shell/plugins/services/idle/manifest.json"
            install -Dm644 ${omarchySource}/shell/plugins/services/idle/Service.qml "$out/shell/plugins/services/idle/Service.qml"
            install -Dm644 ${omarchySource}/shell/plugins/services/idle/IdleModel.js "$out/shell/plugins/services/idle/IdleModel.js"
            install -Dm644 ${./IdlePolicy.js} "$out/shell/plugins/services/idle/IdlePolicy.js"
            chmod u+w "$out/shell/plugins/services/idle/Service.qml" "$out/shell/plugins/services/idle/IdleModel.js"
            ${pkgs.python3}/bin/python3 ${../../scripts/patch-idle-service} \
              "$out/shell/plugins/services/idle/Service.qml" \
              "$out/shell/plugins/services/idle/IdleModel.js"
            ''}
            ${lib.optionalString notificationDaemonEnabled ''
            mkdir -p "$out/shell/plugins/notifications/components"
            install -Dm644 ${omarchySource}/shell/plugins/notifications/manifest.json "$out/shell/plugins/notifications/manifest.json"
            install -Dm644 ${omarchySource}/shell/plugins/notifications/Service.qml "$out/shell/plugins/notifications/Service.qml"
            install -Dm644 ${omarchySource}/shell/plugins/notifications/NotificationLogic.js "$out/shell/plugins/notifications/NotificationLogic.js"
            install -Dm644 ${omarchySource}/shell/plugins/notifications/components/NotificationCard.qml "$out/shell/plugins/notifications/components/NotificationCard.qml"
            chmod u+w "$out/shell/plugins/notifications/Service.qml" "$out/shell/plugins/notifications/NotificationLogic.js"
            ${pkgs.python3}/bin/python3 ${../../scripts/patch-notification-service} \
              "$out/shell/plugins/notifications/Service.qml" \
              "$out/shell/plugins/notifications/NotificationLogic.js"
            ''}

            chmod u+w "$out/shell" "$out/shell/shell.qml" "$out/shell/services" "$out/shell/services/PluginRegistry.qml" "$out/shell/services/AppLibrary.qml" "$out/shell/plugins/menu" "$out/shell/plugins/menu/BarWidget.qml"
            ${lib.optionalString (!builtins.elem "launcher" selectedFeatures) ''
            substituteInPlace "$out/shell/shell.qml" \
              --replace-fail '  property AppLibrary appLibrary: AppLibrary { }' \
                '  property AppLibrary appLibrary: null'
            ''}
            install -Dm644 ${./AppLibrarySupport.js} "$out/shell/services/AppLibrarySupport.js"
            ${pkgs.python3}/bin/python3 ${../../scripts/patch-app-library} \
              "$out/shell/services/AppLibrary.qml"
            substituteInPlace "$out/shell/services/AppLibrary.qml" \
              --replace-fail 'Util.execDetached("uwsm-app -- gtk-launch " + Util.shellQuote(id + ".desktop"))' \
                'var command = AppLibrarySupport.launchCommand(id)
          if (command) Util.execDetached(command)'
            chmod u+w "$out/shell/plugins/menu" "$out/shell/plugins/menu/Menu.qml"
            install -Dm644 ${./MenuDeleteSupport.js} "$out/shell/plugins/menu/MenuDeleteSupport.js"
            ${pkgs.python3}/bin/python3 ${../../scripts/patch-menu-font-provider} \
              "$out/shell/plugins/menu/Menu.qml"
            ${lib.optionalString (!builtins.elem "power" selectedFeatures) ''
            ${pkgs.python3}/bin/python3 ${../../scripts/patch-menu-power-provider} \
              "$out/shell/plugins/menu/Menu.qml"
            ''}
            substituteInPlace "$out/shell/plugins/menu/Menu.qml" \
              --replace-fail 'import "MenuModel.js" as MenuModel' \
                'import "MenuModel.js" as MenuModel
      import "MenuDeleteSupport.js" as MenuDeleteSupport' \
              --replace-fail '    if (!row || row.kind !== "app") return' \
                '    if (!MenuDeleteSupport.canRequestDelete(row, root.appLibrary)) return'
            ${lib.optionalString (!builtins.elem "launcher" selectedFeatures) ''
            ${pkgs.python3}/bin/python3 ${../../scripts/patch-menu-terminal-provider} \
              "$out/shell/plugins/menu/BarWidget.qml"
            ''}
            chmod u+w "$out/shell/plugins/bar" "$out/shell/plugins/bar/Bar.qml"
            chmod u+w "$out/shell/plugins/panels/network/Model.js" "$out/shell/plugins/panels/network/Panel.qml"
            registry_file="$out/shell/services/PluginRegistry.qml"
            substituteInPlace "$registry_file" \
              --replace-fail '  property bool scanning: false' \
                '  property bool scanning: false
        readonly property var omanixyBlockedPlugins: ${blockedPluginIds}
        readonly property var omanixyManagedSecurityPlugins: ${managedSecurityPluginIds}' \
              --replace-fail '    if (manifest) {' \
                '    if (omanixyManagedSecurityPlugins.indexOf(Util.canonicalWidgetId(String(key))) !== -1) return true
        if (isDisabled(config, key) || omanixyBlockedPlugins.indexOf(Util.canonicalWidgetId(String(key))) !== -1) return false
          if (manifest) {' \
              --replace-fail '    lastEnableError = ""' \
                '    lastEnableError = ""
        if (omanixyManagedSecurityPlugins.indexOf(key) !== -1) {
          if (!value) {
            lastEnableError = "managed by Omanixy/Nix configuration"
            return false
          }
          return true
        }'
            substituteInPlace "$out/shell/plugins/panels/network/Model.js" \
              --replace-fail 'function isProtected(security, openSecurity) {' \
                'function isEnterpriseSecurity(security, wpa2Eap, wpaEap) {
        return security === wpa2Eap || security === wpaEap
      }

      function supportedDnsProviders() {
        return ["DHCP", "Cloudflare", "Google"]
      }

      function filterWifiNetworks(networks, wpa2Eap, wpaEap) {
        var visible = []
        var values = Array.isArray(networks) ? networks : []
        for (var i = 0; i < values.length; i++) {
          if (values[i] && !isEnterpriseSecurity(values[i].security, wpa2Eap, wpaEap))
            visible.push(values[i])
        }
        return visible
      }

      function isProtected(security, openSecurity) {' \
              --replace-fail '    isProtected: isProtected,' \
                '    isEnterpriseSecurity: isEnterpriseSecurity,
          filterWifiNetworks: filterWifiNetworks,
          supportedDnsProviders: supportedDnsProviders,
          isProtected: isProtected,'
            substituteInPlace "$out/shell/plugins/panels/network/Panel.qml" \
              --replace-fail 'readonly property var dnsProviders: ["DHCP", "Cloudflare", "Google", "Custom"]' \
                'readonly property var dnsProviders: Model.supportedDnsProviders()' \
              --replace-fail 'function syncWifiNetworks() {
          var nets = []
          var networks = wifiNetworkObjects || []' \
                'function syncWifiNetworks() {
          var nets = []
          var networks = Model.filterWifiNetworks(wifiNetworkObjects, WifiSecurityType.Wpa2Eap, WifiSecurityType.WpaEap)' \
              --replace-fail 'return net.security !== WifiSecurityType.Wpa2Eap && net.security !== WifiSecurityType.WpaEap' \
                'return !Model.isEnterpriseSecurity(net.security, WifiSecurityType.Wpa2Eap, WifiSecurityType.WpaEap)'
            substituteInPlace "$out/shell/plugins/panels/clock/BarWidget.qml" \
              --replace-fail 'else if (b === Qt.MiddleButton) { if (root.bar) root.bar.run("omarchy-menu-timezone") }' \
                'else if (b === Qt.MiddleButton) root.togglePanel()'
            ${pkgs.python3}/bin/python3 ${../../scripts/patch-transparent-foreground-process} \
              "$out/shell/plugins/bar/Bar.qml"
            substituteInPlace "$out/shell/plugins/panels/network/Panel.qml" \
              --replace-fail 'readonly property int count: 4' \
                'readonly property int count: 3' \
              --replace-fail 'if (provider === "Custom") {
            var launcher = "omarchy-launch-floating-terminal-with-presentation"
            root.bar.run(launcher + " " + Util.shellQuote(root.dnsCommand(provider)))
            root.close()
            return
          }' \
                'if (provider === "Custom") return' \
              --replace-fail 'readonly property bool canRunSpeedTest: !!info.iface' \
                'readonly property bool canRunSpeedTest: false'
            substituteInPlace "$out/shell/plugins/panels/network/Panel.qml" \
              --replace-fail '          DnsProviderPill {
                  provider: "Custom"
                  index: 3
                  tooltipText: "Set custom DNS servers"
                  width: dnsRow.cellWidth
                  onClicked: root.setDns(provider)
                }
      ' "$empty"
            install -Dm644 ${safeShellConfig} "$out/config/omarchy/shell.json"
            install -Dm644 ${omarchySource}/default/omarchy/launcher.hides "$out/default/omarchy/launcher.hides"
            install -Dm644 ${safeMenu} "$out/default/omarchy/omarchy-menu.jsonc"
            for helper in ${lib.concatStringsSep " " compatibilityHelpers}; do
              cat > "$out/bin/$helper" <<EOF
      #!/bin/sh
      export COMPAT_ADAPTER_NAME=$helper
      exec omanixy-compat-adapter "\$@"
      EOF
              chmod 0555 "$out/bin/$helper"
            done
    '';
    passthru = {
      inherit omarchySource safeMenu safeShellConfig selectedFeatures compatibilityHelpers runtimeBlockedPlugins lockEnabled fingerprintEnabled polkitAgentEnabled idleEnabled notificationDaemonEnabled managedEnabledSecurityPlugins;
    };
  };

  runtimeInputs = assert terminalDesktopValid; assert featureNamesValid; assert fingerprintPackageValid; assert idleRequiresLockValid; lib.unique (
    (lib.concatMap (capability: capabilityRuntimeInputs.${capability}) selectedCapabilities)
    ++ lib.optional fingerprintEnabled fingerprintPackage
  );

  declaredRuntimeInputs = builtins.toJSON (builtins.sort (a: b: a < b) (map (p: "${p}") runtimeInputs));

  allCompatibilityHelpers = [
    "omarchy-shell"
    "omarchy-audio-input-set-default"
    "omarchy-audio-output-set-default"
    "omarchy-audio-output-sink"
    "omarchy-audio-sink-availability"
    "omarchy-battery-status"
    "omarchy-bluetooth-device"
    "omarchy-bluetooth-power"
    "omarchy-brightness-display"
    "omarchy-capture-screenshot"
    "omarchy-clipboard-open"
    "omarchy-clipboard-paste-file"
    "omarchy-clipboard-paste-text"
    "omarchy-display-text-size"
    "omarchy-dns"
    "omarchy-hyprland-monitor-scaling"
    "omarchy-menu-emoji-insert"
    "omarchy-monitor-state"
    "omarchy-network-band"
    "omarchy-network-password"
    "omarchy-network-qr"
    "omarchy-network-status"
    "omarchy-notification-send"
    "omarchy-powerprofiles-list"
    "omarchy-powerprofiles-set"
    "omarchy-remove-launcher-entry"
    "omarchy-system-stats"
    "omarchy-weather-location"
    "omarchy-weather-status"
  ];
  featureRoots = [
    { prefix = "shell/Commons/"; feature = "core"; }
    { prefix = "shell/Ui/"; feature = "core"; }
    { prefix = "shell/shell.qml"; feature = "core"; }
    { prefix = "shell/plugins/bar/"; feature = "core"; }
    { prefix = "shell/plugins/background/"; feature = "core"; }
    { prefix = "shell/plugins/panels/audio/"; feature = "audio"; }
    { prefix = "shell/plugins/panels/bluetooth/"; feature = "bluetooth"; }
    { prefix = "shell/plugins/clipboard/"; feature = "clipboard"; }
    { prefix = "shell/plugins/emojis/"; feature = "clipboard"; }
    { prefix = "shell/plugins/menu/"; feature = "core"; mixed = true; }
    { prefix = "shell/plugins/osd/"; feature = "core"; }
    { prefix = "shell/plugins/services/"; feature = "core"; }
    { prefix = "shell/plugins/panels/clock/"; feature = "core"; }
    { prefix = "shell/plugins/panels/monitor/"; feature = "monitor"; }
    { prefix = "shell/plugins/panels/network/"; feature = "network"; }
    { prefix = "shell/plugins/panels/power/"; feature = "power"; }
    { prefix = "shell/plugins/panels/weather/"; feature = "weather"; }
    { prefix = "shell/plugins/panels/wifiqr/"; feature = "network"; }
    { prefix = "shell/services/AppLibrary.qml"; feature = "launcher"; }
    { prefix = "shell/services/AppLibrarySupport.js"; feature = "launcher"; }
    { prefix = "shell/services/AppSearch.js"; feature = "launcher"; }
    { prefix = "shell/services/hidden-entries.sh"; feature = "launcher"; }
    { prefix = "shell/services/BarWidgetRegistry.qml"; feature = "core"; }
    { prefix = "shell/services/PluginRegistry.qml"; feature = "core"; }
    { prefix = "default/omarchy/omarchy-menu.jsonc"; feature = "core"; mixed = true; }
    { prefix = "config/omarchy/shell.json"; feature = "core"; }
  ];
  featureSurface = builtins.toJSON {
    requestedFeatures = requestedPresentationFeatures;
    selectedFeatures = selectedFeatures;
    selectedCapabilities = selectedCapabilities;
    runtimeCapabilities = selectedCapabilities;
    featureCapabilities = baselineSource.featureCapabilities;
    capabilityDependencies = baselineSource.capabilityDependencies;
    helperCapabilities = helperCapabilities;
    inherit externalExecutableCapabilities;
    inherit featureRoots;
    scannerNoise = contractSource.scannerNoise or [ ];
    consumerReferenceNoise = [
      {
        path = "shell/plugins/menu/MenuModel.js";
        helper = "omarchy-dns";
        line = "  \"omarchy-dns\"";
      }
    ];
    consumerFeatureOverrides = [
      { path = "shell/plugins/menu/Menu.qml"; executable = "bash"; shape = "resultProc.command = [\"bash\", \"-c\", \": > \" + Util.shellQuote(activeDoneFile)]"; feature = "core"; }
      { path = "shell/plugins/menu/Menu.qml"; executable = "bash"; shape = "resultProc.command = [\"bash\", \"-c\", \"printf '%s\\\\n' \" + Util.shellQuote(selection) + \" > \" + Util.shellQuote(activeSelectionFile) + \"; : > \" + Util.shellQuote(activeDoneFile)]"; feature = "core"; }
      { path = "shell/plugins/menu/Menu.qml"; executable = "bash"; shape = "providerProc.command = [\"bash\", \"-lc\", spec.script]"; feature = "core"; }
      { path = "shell/plugins/menu/Menu.qml"; executable = "bash"; shape = "guardProc.command = [\"bash\", \"-lc\", script]"; feature = "core"; }
      { path = "shell/plugins/menu/Menu.qml"; helper = "omarchy-powerprofiles-list"; shape = ''script: "current=$(powerprofilesctl get 2>/dev/null); omarchy-powerprofiles-list 2>/dev/null | while read -r p; do [[ -z $p ]] && continue; printf '%s\\t%s\\t%s\\n' "$p" "$p" "$current"; done",''; feature = "power"; }
      { path = "shell/plugins/menu/Menu.qml"; helper = "omarchy-powerprofiles-set"; shape = ''actionFor: function(value) { return "omarchy-powerprofiles-set autodetect " + Util.shellQuote(value) }''; feature = "power"; }
      { path = "shell/plugins/menu/Menu.qml"; executable = "powerprofilesctl"; shape = ''script: "current=$(powerprofilesctl get 2>/dev/null); omarchy-powerprofiles-list 2>/dev/null | while read -r p; do [[ -z $p ]] && continue; printf '%s\\t%s\\t%s\\n' "$p" "$p" "$current"; done",''; feature = "power"; }
      { path = "shell/services/AppLibrary.qml"; helper = "omarchy-remove-launcher-entry"; shape = ''Util.shellQuote(root.omarchyPath + "/bin/omarchy-remove-launcher-entry") + " " + Util.shellQuote(id) + " " + Util.shellQuote(String(name || id))''; feature = "launcher"; }
      { path = "default/omarchy/omarchy-menu.jsonc"; helper = "omarchy-capture-screenshot"; id = "trigger.screenshot"; field = "action"; feature = "screenshot"; }
      { path = "default/omarchy/omarchy-menu.jsonc"; helper = "omarchy-shell"; id = "trigger.emoji"; field = "action"; feature = "clipboard"; }
      { path = "default/omarchy/omarchy-menu.jsonc"; executable = "grim"; id = "trigger.screenshot"; field = "when"; feature = "screenshot"; }
      { path = "default/omarchy/omarchy-menu.jsonc"; executable = "gtk-launch"; id = "apps"; field = "when"; feature = "launcher"; }
      { path = "default/omarchy/omarchy-menu.jsonc"; executable = "hyprpicker"; id = "trigger.screenshot"; field = "when"; feature = "screenshot"; }
      { path = "default/omarchy/omarchy-menu.jsonc"; executable = "slurp"; id = "trigger.screenshot"; field = "when"; feature = "screenshot"; }
      { path = "default/omarchy/omarchy-menu.jsonc"; executable = "systemctl"; id = "system.reboot"; field = "action"; feature = "core"; }
      { path = "default/omarchy/omarchy-menu.jsonc"; executable = "systemctl"; id = "system.shutdown"; field = "action"; feature = "core"; }
      { path = "default/omarchy/omarchy-menu.jsonc"; executable = "systemctl"; id = "system.suspend"; field = "action"; feature = "core"; }
      { path = "default/omarchy/omarchy-menu.jsonc"; executable = "timeout"; id = "apps"; field = "when"; feature = "launcher"; }
      { path = "default/omarchy/omarchy-menu.jsonc"; executable = "timeout"; id = "system.logout"; field = "when"; feature = "launcher"; }
      { path = "default/omarchy/omarchy-menu.jsonc"; executable = "uwsm"; id = "apps"; field = "when"; feature = "launcher"; }
      { path = "default/omarchy/omarchy-menu.jsonc"; executable = "uwsm"; id = "system.logout"; field = "action"; feature = "launcher"; }
      { path = "default/omarchy/omarchy-menu.jsonc"; executable = "uwsm"; id = "system.logout"; field = "when"; feature = "launcher"; }
      { path = "default/omarchy/omarchy-menu.jsonc"; executable = "uwsm-app"; id = "apps"; field = "when"; feature = "launcher"; }
      { path = "default/omarchy/omarchy-menu.jsonc"; executable = "wl-copy"; id = "trigger.emoji"; field = "when"; feature = "clipboard"; }
      { path = "default/omarchy/omarchy-menu.jsonc"; executable = "wtype"; id = "trigger.emoji"; field = "when"; feature = "clipboard"; }
    ];
  };
  compatibilityHelpers = lib.filter
    (helper: builtins.elem (helperCapabilities.${helper} or "core-runtime") selectedCapabilities)
    allCompatibilityHelpers;
  helperConsumers = lib.mapAttrs
    (name: contract: {
      consumer = lib.findFirst
        (consumer: lib.hasSuffix "/" consumer || lib.hasSuffix ".qml" consumer)
        (throw "no executable QML consumer for ${name}")
        (if name == "omarchy-capture-screenshot"
        then [ "shell/plugins/" ]
        else contract.postPatchConsumer);
    })
    (lib.getAttrs compatibilityHelpers contractSource.helpers);
  adapterSources = [
    ./adapters/common.bash
    ./adapters/weather.bash
    ./adapters/audio.bash
    ./adapters/network.bash
    ./adapters/power.bash
    ./adapters/display.bash
    ./adapters/notification.bash
    ./adapters/clipboard.bash
    ./adapters/lock.bash
    ./adapters/idle.bash
    ./adapters/notification-state.bash
    ./compat-adapter.bash
  ];
  adapterSourceText = builtins.concatStringsSep "\n" (map builtins.readFile adapterSources);
  adapterSourceHash = builtins.hashString "sha256" adapterSourceText;

  ipc = pkgs.writeShellApplication {
    name = "omanixy-shell";
    runtimeInputs = [ pkgs.coreutils quickshell ];
    inheritPath = false;
    text = builtins.replaceStrings
      [ "@OMARCHY_PATH@" ]
      [ (toString omarchyCompatibilityRoot) ]
      (builtins.readFile ./ipc-wrapper.bash);
  };

  compatAdapter = pkgs.writeShellApplication {
    name = "omanixy-compat-adapter";
    runtimeInputs = runtimeInputs;
    inheritPath = false;
    text = builtins.replaceStrings
      [ "@IPC@" ]
      [ "${ipc}/bin/omanixy-shell" ]
      adapterSourceText;
  };

  compatibilityBin = stdenvNoCC.mkDerivation {
    pname = "omanixy-compatibility-bin";
    version = lib.substring 0 12 omarchyRevision;
    dontUnpack = true;
    outputs = [ "out" "probes" ];
    installPhase = ''
      mkdir -p "$out/bin" "$probes/bin"
      ln -s ${compatAdapter}/bin/omanixy-compat-adapter "$out/bin/omanixy-compat-adapter"
      for helper in ${lib.concatStringsSep " " compatibilityHelpers}; do
        ln -s ${compatAdapter}/bin/omanixy-compat-adapter "$out/bin/$helper"
      done
      ${lib.optionalString lockEnabled ''
      ln -s ${compatAdapter}/bin/omanixy-compat-adapter "$out/bin/omarchy-hyprland-session-locked"
      ''}
      ${lib.optionalString fingerprintEnabled ''
      ln -s ${compatAdapter}/bin/omanixy-compat-adapter "$out/bin/omarchy-lock-fingerprint-ready"
      ''}
      ${lib.optionalString idleEnabled ''
      ln -s ${compatAdapter}/bin/omanixy-compat-adapter "$out/bin/omanixy-idle-state"
      ''}
      ${lib.optionalString notificationDaemonEnabled ''
      ln -s ${compatAdapter}/bin/omanixy-compat-adapter "$out/bin/omanixy-notification-state"
      ''}
      ${pkgs.python3}/bin/python3 ${../../scripts/generate-postpatch-runtime-surface} \
        ${omarchyCompatibilityRoot} "$out" "$probes" ${quickshell}/bin/quickshell ${fontconfigFile} ${pkgs.bash}/bin/bash ${lib.escapeShellArg (builtins.toJSON helperConsumers)} ${lib.escapeShellArg featureSurface}
    '';
  };
  compatibilityProbes = compatibilityBin.probes;

  launcherDataDirs = builtins.concatStringsSep ":" [
    "${terminalPackage}/share"
    "${pkgs.xdg-terminal-exec}/share"
  ];

  runtime = pkgs.writeShellApplication {
    name = "omanixy-shell-runtime";
    runtimeInputs = [ quickshell ] ++ runtimeInputs ++ [ compatAdapter compatibilityBin ];
    inheritPath = false;
    text = ''
      ${lib.optionalString (builtins.elem "launcher" selectedFeatures) ''
      if [ -n "''${XDG_DATA_DIRS:-}" ]; then
        export XDG_DATA_DIRS=${lib.escapeShellArg launcherDataDirs}:"$XDG_DATA_DIRS"
      else
        export XDG_DATA_DIRS=${lib.escapeShellArg launcherDataDirs}
      fi
      ''}
      export OMARCHY_PATH=${lib.escapeShellArg "${omarchyCompatibilityRoot}"}
      export QS_DISABLE_FILE_WATCHER=1
      export QS_NO_RELOAD_POPUP=1
      exec quickshell -n -p "$OMARCHY_PATH/shell"
    '';
  };
in
pkgs.symlinkJoin {
  name = "omanixy-shell";
  paths = [ ipc runtime ];
  postBuild = ''
    mkdir -p "$out/bin" "$out/share"
    ln -s ${quickshell}/bin/quickshell "$out/bin/quickshell"
    ln -s ${quickshell}/bin/qs "$out/bin/qs"
    ln -s ${compatAdapter}/bin/omanixy-compat-adapter "$out/bin/omanixy-compat-adapter"
    ln -s ${pkgs.inotify-tools}/bin/inotifywait "$out/bin/inotifywait"
    ${lib.optionalString (builtins.elem "monitor" selectedFeatures || builtins.elem "screenshot" selectedFeatures) ''
    ln -s ${pkgs.hyprland}/bin/hyprctl "$out/bin/hyprctl"
    ''}
    ${lib.optionalString (builtins.elem "launcher" selectedFeatures) ''
    ln -s ${pkgs.gtk3}/bin/gtk-launch "$out/bin/gtk-launch"
    ''}
    for helper in ${lib.concatStringsSep " " compatibilityHelpers}; do
      if [ "$helper" = omarchy-shell ]; then
        continue
      fi
      ln -s ${compatibilityBin}/bin/$helper "$out/bin/$helper"
    done
    ${lib.optionalString lockEnabled ''
    ln -s ${compatibilityBin}/bin/omarchy-hyprland-session-locked "$out/bin/omarchy-hyprland-session-locked"
    ''}
    ${lib.optionalString fingerprintEnabled ''
    ln -s ${compatibilityBin}/bin/omarchy-lock-fingerprint-ready "$out/bin/omarchy-lock-fingerprint-ready"
    ''}
    ${lib.optionalString idleEnabled ''
    ln -s ${compatibilityBin}/bin/omanixy-idle-state "$out/bin/omanixy-idle-state"
    ''}
    ${lib.optionalString notificationDaemonEnabled ''
    ln -s ${compatibilityBin}/bin/omanixy-notification-state "$out/bin/omanixy-notification-state"
    ''}
    ln -s ${theme} "$out/share/omarchy-theme"
  '';
  passthru = {
    inherit omarchyRevision quickshellRevision nixpkgsRevision omarchySource iconFont omarchyCompatibilityRoot compatibilityBin compatibilityProbes quickshell theme supportedSystems safeMenu safeShellConfig selectedFeatures selectedCapabilities compatibilityHelpers runtimeBlockedPlugins adapterSources adapterSourceHash featureSurface lockEnabled fingerprintEnabled polkitAgentEnabled idleEnabled notificationDaemonEnabled managedEnabledSecurityPlugins declaredRuntimeInputs terminalPackage terminalDesktop;
    defaultBackground = "${theme}/backgrounds/1-quattro.jpg";
    inherit ipc compatAdapter runtime;
    buildProvenance = {
      inherit omarchyRevision quickshellRevision nixpkgsRevision;
    };
  };
  meta = {
    description = "Nix-native Omarchy Quattro runtime and IPC client";
    homepage = "https://github.com/atqamz/omanixy";
    license = with lib.licenses; [ mit lgpl3Only ];
    mainProgram = "omanixy-shell";
    platforms = supportedSystems;
  };
}
