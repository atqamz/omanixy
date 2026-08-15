{ lib
, pkgs
, omarchy
, quickshellSrc
, nixpkgsRevision
, supportedSystems
}:

assert lib.assertOneOf "omanixy supported system" pkgs.stdenv.hostPlatform.system supportedSystems;

let
  inherit (pkgs) stdenvNoCC;

  omarchyRevision = "f0020448ca87329199de7cb12f2015ebc4a3e5e7";
  quickshellRevision = "28771c7c74b42e20afca0b1b63980cb46515537c";

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

  safeMenu = pkgs.writeText "omanixy-safe-omarchy-menu.jsonc" (builtins.readFile ./safe-menu.jsonc);

  safeShellConfig = pkgs.writeText "omanixy-safe-shell.json" ''
    {
      "version": 1,
      "bar": {
        "position": "top",
        "transparent": false,
        "centerAnchor": "omarchy.clock",
        "layout": {
          "left": [
            { "id": "omarchy.menu" },
            { "id": "omarchy.workspaces" }
          ],
          "center": [
            { "id": "omarchy.clock", "format": "dddd HH:mm" },
            { "id": "omarchy.weather" }
          ],
          "right": [
            { "id": "omarchy.tray" },
            { "id": "omarchy.media" },
            { "id": "omarchy.bluetooth" },
            { "id": "omarchy.network" },
            { "id": "omarchy.audio" },
            { "id": "omarchy.monitor" },
            { "id": "omarchy.power" }
          ]
        }
      },
      "disabledPlugins": [
        "omarchy.active-window",
        "omarchy.agents",
        "omarchy.background",
        "omarchy.battery",
        "omarchy.dev-gallery",
        "omarchy.disk-speedtest",
        "omarchy.dropbox",
        "omarchy.idle",
        "omarchy.image-picker",
        "omarchy.indicators",
        "omarchy.keyboard-layout",
        "omarchy.lock",
        "omarchy.microphone",
        "omarchy.nightlight",
        "omarchy.notifications",
        "omarchy.polkit",
        "omarchy.reminders",
        "omarchy.system-update",
        "omarchy.tailscale"
      ]
    }
  '';

  omarchyCompatibilityRoot = stdenvNoCC.mkDerivation {
    pname = "omanixy-omarchy-compat-root";
    version = lib.substring 0 12 omarchyRevision;
    dontUnpack = true;
    installPhase = ''
      mkdir -p "$out/bin" "$out/config/omarchy" "$out/default/omarchy"
      mkdir -p "$out/shell"
      cp -R ${omarchySource}/shell/Commons "$out/shell/Commons"
      cp -R ${omarchySource}/shell/Ui "$out/shell/Ui"
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
      for plugin in audio bluetooth clock monitor network power speedtest weather wifiqr; do
        mkdir -p "$out/shell/plugins/panels/$plugin"
        cp -R "${omarchySource}/shell/plugins/panels/$plugin/." "$out/shell/plugins/panels/$plugin"
      done
      mkdir -p "$out/shell/plugins/services"
      cp -R ${omarchySource}/shell/plugins/services/media "$out/shell/plugins/services/media"

      chmod u+w "$out/shell/services" "$out/shell/services/PluginRegistry.qml"
      sed -i '/^    if (manifest) {$/i\    if (isDisabled(config, key)) return false' \
        "$out/shell/services/PluginRegistry.qml"
      sed -i '/^      if (!network) continue$/a\      if (network.security === WifiSecurityType.Wpa2Eap || network.security === WifiSecurityType.WpaEap) continue' \
        "$out/shell/plugins/panels/network/Panel.qml"
      substituteInPlace "$out/shell/plugins/panels/clock/BarWidget.qml" \
        --replace-fail 'else if (b === Qt.MiddleButton) { if (root.bar) root.bar.run("omarchy-menu-timezone") }' \
          'else if (b === Qt.MiddleButton) root.togglePanel()'
      substituteInPlace "$out/shell/plugins/panels/network/Panel.qml" \
        --replace-fail 'readonly property var dnsProviders: ["DHCP", "Cloudflare", "Google", "Custom"]' \
          'readonly property var dnsProviders: ["DHCP", "Cloudflare", "Google"]' \
        --replace-fail 'readonly property int count: 4' \
          'readonly property int count: 3' \
        --replace-fail 'if (provider === "Custom") {
      var launcher = "omarchy-launch-floating-terminal-with-presentation"
      root.bar.run(launcher + " " + Util.shellQuote(root.dnsCommand(provider)))
      root.close()
      return
    }' \
          'if (provider === "Custom") return'
      shell_file="$out/shell/plugins/panels/network/Panel.qml"
      temporary="$shell_file.omanixy"
      chmod u+w "''${shell_file%/*}"
      chmod u+w "$shell_file"
      \${pkgs.gawk}/bin/awk '
        /^          DnsProviderPill \{$/ {
          block = $0
          if ((getline provider) <= 0) { print block; exit }
          if (provider ~ /provider: "Custom"/) {
            while ((getline line) > 0 && line !~ /^          \}$/) {}
            next
          }
          print block
          print provider
          next
        }
        { print }
      ' "$shell_file" > "$temporary"
      mv -f -- "$temporary" "$shell_file"
      install -Dm644 ${safeShellConfig} "$out/config/omarchy/shell.json"
      ln -s ${omarchySource}/default/omarchy/launcher.hides "$out/default/omarchy/launcher.hides"
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
      inherit omarchySource safeMenu safeShellConfig;
    };
  };

  runtimeInputs = with pkgs; [
    bash
    coreutils
    curl
    desktop-file-utils
    brightnessctl
    bluez
    findutils
    gawk
    gnugrep
    gnused
    grim
    gtk3
    inotify-tools
    fontconfig
    hyprland
    iproute2
    iputils
    iw
    jq
    libnotify
    networkmanager
    pipewire
    power-profiles-daemon
    procps
    qrencode
    quickshell
    systemd
    upower
    util-linux
    wireplumber
    wl-clipboard
    wtype
    xdg-utils
  ];

  compatibilityHelpers = [
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
    "omarchy-network-speedtest"
    "omarchy-notification-send"
    "omarchy-powerprofiles-list"
    "omarchy-powerprofiles-set"
    "omarchy-remove-launcher-entry"
    "omarchy-system-stats"
    "omarchy-weather-location"
    "omarchy-weather-status"
    "uwsm-app"
  ];

  ipc = pkgs.writeShellApplication {
    name = "omanixy-shell";
    runtimeInputs = with pkgs; [ coreutils quickshell ];
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
      (builtins.readFile ./compat-adapter.bash);
  };

  compatibilityBin = stdenvNoCC.mkDerivation {
    pname = "omanixy-compatibility-bin";
    version = lib.substring 0 12 omarchyRevision;
    dontUnpack = true;
    installPhase = ''
      mkdir -p "$out/bin"
      for helper in ${lib.concatStringsSep " " compatibilityHelpers}; do
        ln -s ${compatAdapter}/bin/omanixy-compat-adapter "$out/bin/$helper"
      done
    '';
  };

  runtime = pkgs.writeShellApplication {
    name = "omanixy-shell-runtime";
    runtimeInputs = runtimeInputs ++ [ compatAdapter compatibilityBin ];
    inheritPath = false;
    text = ''
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
    ln -s ${pkgs.inotify-tools}/bin/inotifywait "$out/bin/inotifywait"
    ln -s ${pkgs.hyprland}/bin/hyprctl "$out/bin/hyprctl"
    ln -s ${pkgs.gtk3}/bin/gtk-launch "$out/bin/gtk-launch"
    for helper in ${lib.concatStringsSep " " compatibilityHelpers}; do
      ln -s ${compatibilityBin}/bin/$helper "$out/bin/$helper"
    done
    ln -s ${theme} "$out/share/omarchy-theme"
  '';
  passthru = {
    inherit omarchyRevision quickshellRevision nixpkgsRevision omarchySource omarchyCompatibilityRoot compatibilityBin quickshell theme supportedSystems;
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
