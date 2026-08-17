{ lib
, pkgs
, omarchy
, quickshellSrc
, nixpkgsRevision
, supportedSystems
, features ? null
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
  baselineConfig = builtins.removeAttrs baselineSource [ "featurePlugins" "featureDependencies" "featureOrder" "migrations" ];
  featureRuntimeInputs = with pkgs; {
    core = [ bash coreutils findutils gawk gnugrep gnused inotify-tools jq systemd util-linux ];
    network = [ iproute2 iputils iw networkmanager qrencode ];
    audio = [ pipewire pulseaudio wireplumber ];
    bluetooth = [ bluez util-linux ];
    screenshot = [ fontconfig grim hyprland hyprpicker procps slurp wl-clipboard ];
    clipboard = [ wl-clipboard wtype xdg-utils ];
    power = [ power-profiles-daemon upower ];
    monitor = [ brightnessctl fontconfig glib gtk3 hyprland libnotify procps ];
    weather = [ curl ];
    notification = [ libnotify ];
    launcher = [ desktop-file-utils gtk3 uwsm ];
  };
  allFeatures = featureSelection.featureNames;
  requestedFeatures = if features == null then allFeatures else features;
  selectedFeatures = featureSelection.select requestedFeatures;
  featureNamesValid = lib.assertMsg
    (featureSelection.validate requestedFeatures
      && lib.all (feature: builtins.hasAttr feature featureRuntimeInputs) selectedFeatures)
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

  theme = stdenvNoCC.mkDerivation {
    pname = "omanixy-shell-theme";
    version = lib.substring 0 12 omarchyRevision;
    src = "${omarchySource}/themes/tokyo-night";
    dontBuild = true;
    installPhase = ''
      mkdir -p "$out"
      install -Dm644 colors.toml "$out/colors.toml"
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

  omittedFeaturePlugins = lib.concatLists (map
    (feature: baselineSource.featurePlugins.${feature} or [ ])
    (lib.filter (feature: !builtins.elem feature selectedFeatures) (builtins.attrNames baselineSource.featurePlugins)));
  runtimeBlockedPlugins = lib.unique (baselineConfig.disabledPlugins ++ omittedFeaturePlugins);
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
            for plugin in audio bluetooth clock monitor network power weather wifiqr; do
              mkdir -p "$out/shell/plugins/panels/$plugin"
              cp -R "${omarchySource}/shell/plugins/panels/$plugin/." "$out/shell/plugins/panels/$plugin"
            done
            mkdir -p "$out/shell/plugins/services"
            cp -R ${omarchySource}/shell/plugins/services/media "$out/shell/plugins/services/media"

            chmod u+w "$out/shell/services" "$out/shell/services/PluginRegistry.qml" "$out/shell/services/AppLibrary.qml"
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
            chmod u+w "$out/shell/plugins/bar" "$out/shell/plugins/bar/Bar.qml"
            chmod u+w "$out/shell/plugins/panels/network/Model.js" "$out/shell/plugins/panels/network/Panel.qml"
            registry_file="$out/shell/services/PluginRegistry.qml"
            substituteInPlace "$registry_file" \
              --replace-fail '  property bool scanning: false' \
                '  property bool scanning: false
        readonly property var omanixyBlockedPlugins: ${blockedPluginIds}' \
              --replace-fail '    if (manifest) {' \
                '    if (isDisabled(config, key) || omanixyBlockedPlugins.indexOf(Util.canonicalWidgetId(String(key))) !== -1) return false
          if (manifest) {'
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
      inherit omarchySource safeMenu safeShellConfig selectedFeatures compatibilityHelpers runtimeBlockedPlugins;
    };
  };

  runtimeInputs = assert featureNamesValid; lib.unique (lib.concatMap (feature: featureRuntimeInputs.${feature}) selectedFeatures);

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
  helperFeatures = {
    omarchy-audio-input-set-default = "audio";
    omarchy-audio-output-set-default = "audio";
    omarchy-audio-output-sink = "audio";
    omarchy-audio-sink-availability = "audio";
    omarchy-battery-status = "power";
    omarchy-bluetooth-device = "bluetooth";
    omarchy-bluetooth-power = "bluetooth";
    omarchy-brightness-display = "monitor";
    omarchy-capture-screenshot = "screenshot";
    omarchy-clipboard-open = "clipboard";
    omarchy-clipboard-paste-file = "clipboard";
    omarchy-clipboard-paste-text = "clipboard";
    omarchy-display-text-size = "monitor";
    omarchy-dns = "network";
    omarchy-hyprland-monitor-scaling = "monitor";
    omarchy-menu-emoji-insert = "clipboard";
    omarchy-monitor-state = "monitor";
    omarchy-network-band = "network";
    omarchy-network-password = "network";
    omarchy-network-qr = "network";
    omarchy-network-status = "network";
    omarchy-notification-send = "notification";
    omarchy-powerprofiles-list = "power";
    omarchy-powerprofiles-set = "power";
    omarchy-remove-launcher-entry = "launcher";
    omarchy-system-stats = "core";
    omarchy-weather-location = "weather";
    omarchy-weather-status = "weather";
  };
  featureRoots = [
    { prefix = "shell/Commons/"; feature = "core"; }
    { prefix = "shell/Ui/"; feature = "core"; }
    { prefix = "shell/shell.qml"; feature = "core"; }
    { prefix = "shell/plugins/bar/"; feature = "core"; }
    { prefix = "shell/plugins/panels/audio/"; feature = "audio"; }
    { prefix = "shell/plugins/panels/bluetooth/"; feature = "bluetooth"; }
    { prefix = "shell/plugins/clipboard/"; feature = "clipboard"; }
    { prefix = "shell/plugins/emojis/"; feature = "clipboard"; }
    { prefix = "shell/plugins/menu/"; feature = "core"; }
    { prefix = "shell/plugins/osd/"; feature = "core"; }
    { prefix = "shell/plugins/services/"; feature = "core"; }
    { prefix = "shell/plugins/panels/clock/"; feature = "core"; }
    { prefix = "shell/plugins/panels/monitor/"; feature = "monitor"; }
    { prefix = "shell/plugins/panels/network/"; feature = "network"; }
    { prefix = "shell/plugins/panels/power/"; feature = "power"; }
    { prefix = "shell/plugins/panels/weather/"; feature = "weather"; }
    { prefix = "shell/plugins/panels/wifiqr/"; feature = "network"; }
    { prefix = "shell/services/"; feature = "launcher"; }
    { prefix = "default/omarchy/"; feature = "screenshot"; }
  ];
  featureSurface = builtins.toJSON {
    selectedFeatures = selectedFeatures;
    dependencies = featureSelection.dependencies;
    helperFeatures = helperFeatures // {
      omarchy-shell = "core";
    };
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
      { path = "shell/plugins/menu/Menu.qml"; helper = "omarchy-powerprofiles-list"; feature = "power"; }
      { path = "shell/plugins/menu/Menu.qml"; helper = "omarchy-powerprofiles-set"; feature = "power"; }
    ];
  };
  compatibilityHelpers = lib.filter
    (helper: builtins.elem (helperFeatures.${helper} or "core") selectedFeatures)
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
      ${pkgs.python3}/bin/python3 ${../../scripts/generate-postpatch-runtime-surface} \
        ${omarchyCompatibilityRoot} "$out" "$probes" ${quickshell}/bin/quickshell ${fontconfigFile} ${pkgs.bash}/bin/bash ${lib.escapeShellArg (builtins.toJSON helperConsumers)} ${lib.escapeShellArg featureSurface}
    '';
  };
  compatibilityProbes = compatibilityBin.probes;

  runtime = pkgs.writeShellApplication {
    name = "omanixy-shell-runtime";
    runtimeInputs = [ quickshell ] ++ runtimeInputs ++ [ compatAdapter compatibilityBin ];
    inheritPath = false;
    text = ''
      export FONTCONFIG_FILE=${fontconfigFile}
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
    ln -s ${theme} "$out/share/omarchy-theme"
  '';
  passthru = {
    inherit omarchyRevision quickshellRevision nixpkgsRevision omarchySource omarchyCompatibilityRoot compatibilityBin compatibilityProbes quickshell theme supportedSystems safeMenu safeShellConfig selectedFeatures compatibilityHelpers runtimeBlockedPlugins adapterSources adapterSourceHash featureSurface;
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
