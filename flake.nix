{
  description = "Nix-native integration layer for the Omarchy Quattro desktop shell";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    omarchy = {
      url = "github:basecamp/omarchy/f0020448ca87329199de7cb12f2015ebc4a3e5e7";
      flake = false;
    };
    quickshell = {
      url = "github:quickshell-mirror/quickshell/28771c7c74b42e20afca0b1b63980cb46515537c";
      flake = false;
    };
    home-manager = {
      url = "github:nix-community/home-manager/3ee51fbdac8c8bdfe1e7e1fcaba6520a563f394f";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, omarchy, quickshell, home-manager, ... }:
    let
      supportedSystems = [ "x86_64-linux" "aarch64-linux" ];
      contractSource = builtins.fromJSON (builtins.readFile ./upstream/compatibility-contracts.json);
      nixpkgsRevision = contractSource.pins.nixpkgs;
      forEachSystem = nixpkgs.lib.genAttrs supportedSystems;
      runtimeFor = system: features:
        assert nixpkgs.lib.assertOneOf "omanixy supported system" system supportedSystems;
        import ./packages/omanixy-shell {
          inherit omarchy;
          lib = nixpkgs.lib;
          pkgs = nixpkgs.legacyPackages.${system};
          quickshellSrc = quickshell;
          inherit nixpkgsRevision supportedSystems;
          inherit features;
        };
      homeConfigurationFor = system: extra: home-manager.lib.homeManagerConfiguration {
        pkgs = nixpkgs.legacyPackages.${system};
        modules = [
          self.homeManagerModules.default
          {
            home.username = "omanixy-test";
            home.homeDirectory = "/build/omanixy-test";
            home.stateVersion = "25.11";
            programs.omanixy.enable = true;
          }
          extra
        ];
      };
    in
    {
      homeManagerModules.default = { pkgs, ... }: {
        _module.args.omanixyRuntimeFor = features: runtimeFor pkgs.stdenv.hostPlatform.system features;
        imports = [ ./modules/home/default.nix ];
      };
      nixosModules.default = ./modules/nixos/default.nix;
      packages = forEachSystem (system: {
        omanixy-shell = runtimeFor system null;
      });
      formatter = forEachSystem (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        pkgs.writeShellApplication {
          name = "omanixy-nix-fmt";
          runtimeInputs = [ pkgs.findutils pkgs.nixpkgs-fmt ];
          text = builtins.readFile ./scripts/nix-fmt;
        }
      );
      checks = forEachSystem (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          runtime = runtimeFor system null;
          clipboardRuntime = runtimeFor system [ "clipboard" ];
          bluetoothRuntime = runtimeFor system [ "bluetooth" ];
          weatherRuntime = runtimeFor system [ "weather" ];
          audioRuntime = runtimeFor system [ "audio" ];
          networkRuntime = runtimeFor system [ "network" ];
          launcherRuntime = runtimeFor system [ "launcher" ];
          screenshotRuntime = runtimeFor system [ "screenshot" ];
          coreRuntime = runtimeFor system [ "core" ];
          monitorRuntime = runtimeFor system [ "monitor" ];
          powerRuntime = runtimeFor system [ "power" ];
          notificationRuntime = runtimeFor system [ "notification" ];
          capabilityRuntimePaths = pkgs.writeText "omanixy-capability-runtime-paths" (builtins.toJSON {
            "audio-control" = toString audioRuntime;
            "audio-default-output" = toString audioRuntime;
            "bluetooth-control" = toString bluetoothRuntime;
            "clipboard-presentation" = toString clipboardRuntime;
            "core-runtime" = toString coreRuntime;
            launcher = toString launcherRuntime;
            "monitor-control" = toString monitorRuntime;
            "network-manager" = toString networkRuntime;
            "notification-send" = toString notificationRuntime;
            "power-control" = toString powerRuntime;
            "screenshot-capture" = toString screenshotRuntime;
            "text-injection" = toString clipboardRuntime;
            "wayland-clipboard-write" = toString networkRuntime;
            "weather-network" = toString weatherRuntime;
          });
          clipboardHomeConfiguration = homeConfigurationFor system {
            programs.omanixy.features = [ "clipboard" ];
          };
          coreHomeConfiguration = homeConfigurationFor system {
            programs.omanixy.features = [ "core" ];
          };
          audioHomeConfiguration = homeConfigurationFor system {
            programs.omanixy.features = [ "audio" ];
          };
          weatherHomeConfiguration = homeConfigurationFor system {
            programs.omanixy.features = [ "weather" ];
          };
          networkHomeConfiguration = homeConfigurationFor system {
            programs.omanixy.features = [ "network" ];
          };
          runtimeClosureInfo = pkgs.closureInfo { rootPaths = [ runtime ]; };
          compatibilityRoot = runtime.passthru.omarchyCompatibilityRoot;
          baselineConfigForTests = builtins.removeAttrs
            (builtins.fromJSON (builtins.readFile ./upstream/shell-baseline.json))
            [ "featurePlugins" "featureDependencies" "featureOrder" "migrations" "featureCapabilities" "capabilityDependencies" ];
          storeConfig = pkgs.writeText "omanixy-historical-shell-config" (builtins.readFile ./upstream/shell-baseline-v1.json);
          explicitStoreConfig = pkgs.writeText "omanixy-explicit-store-shell-config" (builtins.toJSON (baselineConfigForTests // {
            disabledPlugins = nixpkgs.lib.unique (baselineConfigForTests.disabledPlugins ++ [
              "omarchy.audio"
              "omarchy.network"
            ]);
          }));
          customStoreConfig = pkgs.writeText "omanixy-custom-store-shell-config" ''{"version":1,"custom":true}'';
          malformedStoreConfig = pkgs.writeText "omanixy-malformed-store-shell-config" ''{"disabledPlugins":'';
          homeConfiguration = homeConfigurationFor system { };
          customHomeConfiguration = homeConfigurationFor system {
            programs.omanixy.shell.config = {
              version = 1;
              custom = true;
              disabledPlugins = [ "omarchy.audio" ];
            };
          };
          invalidHomeConfiguration = builtins.tryEval (
            builtins.deepSeq
              (homeConfigurationFor system {
                programs.omanixy.shell.config = {
                  version = 2;
                };
              }).activationPackage
              true
          );
          invalidDisabledPluginsType = builtins.tryEval (
            builtins.deepSeq
              (homeConfigurationFor system {
                programs.omanixy.shell.config = {
                  version = 1;
                  disabledPlugins = "omarchy.lock";
                };
              }).activationPackage
              true
          );
          invalidDisabledPluginMember = builtins.tryEval (
            builtins.deepSeq
              (homeConfigurationFor system {
                programs.omanixy.shell.config = {
                  version = 1;
                  disabledPlugins = [ "omarchy.lock" 1 ];
                };
              }).activationPackage
              true
          );
          unsupportedPlatform = builtins.tryEval (
            builtins.deepSeq (runtimeFor "x86_64-darwin" null) true
          );
          nixosConfiguration = nixpkgs.lib.nixosSystem {
            inherit system;
            modules = [
              self.nixosModules.default
              {
                nixpkgs.hostPlatform = system;
                system.stateVersion = "26.11";
              }
            ];
          };
          pamPasswordNixosConfiguration = nixpkgs.lib.nixosSystem {
            inherit system;
            modules = [
              self.nixosModules.default
              {
                nixpkgs.hostPlatform = system;
                system.stateVersion = "26.11";
                programs.omanixy.security.pam.password.enable = true;
              }
            ];
          };
          pamPasswordServiceFile = "${pamPasswordNixosConfiguration.config.environment.etc."pam.d/omarchy-lock-password".source}";
          service = homeConfiguration.config.systemd.user.services.omanixy-shell;
          activationScript = pkgs.writeShellScript "omanixy-shell-state-activation" homeConfiguration.config.home.activation.omanixyShellState.data;
          clipboardActivationScript = pkgs.writeShellScript "omanixy-shell-clipboard-state-activation" clipboardHomeConfiguration.config.home.activation.omanixyShellState.data;
          coreActivationScript = pkgs.writeShellScript "omanixy-shell-core-state-activation" coreHomeConfiguration.config.home.activation.omanixyShellState.data;
          audioActivationScript = pkgs.writeShellScript "omanixy-shell-audio-state-activation" audioHomeConfiguration.config.home.activation.omanixyShellState.data;
          weatherActivationScript = pkgs.writeShellScript "omanixy-shell-weather-state-activation" weatherHomeConfiguration.config.home.activation.omanixyShellState.data;
          networkActivationScript = pkgs.writeShellScript "omanixy-shell-network-state-activation" networkHomeConfiguration.config.home.activation.omanixyShellState.data;
          customActivationScript = pkgs.writeShellScript "omanixy-shell-custom-state-activation" customHomeConfiguration.config.home.activation.omanixyShellState.data;
          serviceUnit = pkgs.writeText "omanixy-shell.service" ''
            [Unit]
            Description=${service.Unit.Description}
            PartOf=${nixpkgs.lib.concatStringsSep " " service.Unit.PartOf}
            After=${nixpkgs.lib.concatStringsSep " " service.Unit.After}
            StartLimitIntervalSec=${service.Unit.StartLimitIntervalSec}
            StartLimitBurst=${toString service.Unit.StartLimitBurst}

            [Service]
            ExecStart=${nixpkgs.lib.concatStringsSep " " service.Service.ExecStart}
            Restart=${service.Service.Restart}
            RestartSec=${service.Service.RestartSec}
            TimeoutStopSec=${service.Service.TimeoutStopSec}
            ${nixpkgs.lib.concatMapStringsSep "\n" (environment: "Environment=" + environment) service.Service.Environment}

            [Install]
            WantedBy=${nixpkgs.lib.concatStringsSep " " service.Install.WantedBy}
          '';
        in
        {
          pin-invariants = pkgs.runCommand "omanixy-pin-invariants"
            {
              nativeBuildInputs = [ pkgs.bash pkgs.gnugrep pkgs.jq pkgs.ripgrep (pkgs.python3.withPackages (ps: [ ps.pyyaml ])) ];
            } ''
            ${pkgs.bash}/bin/bash ${./test/pin-invariants.sh} ${./.} '${builtins.toJSON supportedSystems}'
            touch "$out"
          '';
          ipc-wrapper = pkgs.runCommand "omanixy-ipc-wrapper"
            {
              nativeBuildInputs = [ pkgs.bash pkgs.coreutils pkgs.gnugrep pkgs.gnused pkgs.python3 ];
            } ''
            PYTHON=${pkgs.python3}/bin/python3 ${pkgs.bash}/bin/bash ${./test/ipc-wrapper.sh} ${./.}
            touch "$out"
          '';
          runtime-closure = pkgs.runCommand "omanixy-runtime-closure"
            {
              closurePaths = "${runtimeClosureInfo}/store-paths";
              nativeBuildInputs = [ pkgs.bash pkgs.coreutils pkgs.gnugrep pkgs.gnused pkgs.findutils pkgs.jq pkgs.python3 ];
            } ''
            ${pkgs.bash}/bin/bash ${./test/runtime-closure.sh} ${runtime} "$closurePaths" ${runtime.passthru.quickshell} ${runtime.passthru.omarchySource} ${compatibilityRoot} ${runtime.passthru.compatibilityBin} ${runtime.passthru.compatibilityProbes} ${./upstream/compatibility-contracts.json}
            touch "$out"
          '';
          feature-dependencies = pkgs.runCommand "omanixy-feature-dependencies"
            {
              nativeBuildInputs = [ pkgs.bash pkgs.coreutils pkgs.jq ];
            } ''
            jq -e '.selectedFeatures == ["core", "network"] and (.selectedCapabilities | index("network-manager") != null) and (.selectedCapabilities | index("wayland-clipboard-write") != null) and (.selectedCapabilities | index("clipboard-presentation") == null)' ${networkRuntime.passthru.compatibilityBin}/feature-surface.json >/dev/null
            jq -e 'has("trigger.emoji") | not' ${networkRuntime.passthru.safeMenu} >/dev/null
            test -e ${clipboardRuntime.passthru.compatibilityBin}/bin/omarchy-menu-emoji-insert
            test ! -e ${clipboardRuntime.passthru.compatibilityBin}/bin/omarchy-network-status
            test -e ${networkRuntime.passthru.compatibilityBin}/bin/omarchy-network-status
            test ! -e ${networkRuntime.passthru.compatibilityBin}/bin/omarchy-clipboard-open
            test ! -e ${networkRuntime.passthru.compatibilityBin}/bin/omarchy-menu-emoji-insert
            test -e ${bluetoothRuntime.passthru.compatibilityBin}/bin/omarchy-audio-output-set-default
            test ! -e ${bluetoothRuntime.passthru.compatibilityBin}/bin/omarchy-audio-input-set-default
            test ! -e ${bluetoothRuntime.passthru.compatibilityBin}/bin/omarchy-audio-output-sink
            test ! -e ${bluetoothRuntime.passthru.compatibilityBin}/bin/omarchy-audio-sink-availability
            jq -e '.selectedFeatures == ["core", "bluetooth"] and (.selectedCapabilities | index("audio-default-output") != null) and (.selectedCapabilities | index("audio-control") == null)' ${bluetoothRuntime.passthru.compatibilityBin}/feature-surface.json >/dev/null
            test ! -e ${networkRuntime.passthru.compatibilityBin}/bin/omarchy-clipboard-open
            test ! -e ${networkRuntime.passthru.compatibilityBin}/bin/omarchy-menu-emoji-insert
            clipboard_path=$(sed -n 's/^export PATH="\(.*\)"$/\1/p' ${clipboardRuntime}/bin/omanixy-shell-runtime)
            PATH="$clipboard_path" command -v wl-copy >/dev/null
            if PATH="$clipboard_path" command -v nmcli >/dev/null; then
              exit 1
            fi
            bluetooth_path=$(sed -n 's/^export PATH="\(.*\)"$/\1/p' ${bluetoothRuntime}/bin/omanixy-shell-runtime)
            PATH="$bluetooth_path" command -v pactl >/dev/null
            network_path=$(sed -n 's/^export PATH="\(.*\)"$/\1/p' ${networkRuntime}/bin/omanixy-shell-runtime)
            PATH="$network_path" command -v wl-copy >/dev/null
            jq -e '.selectedFeatures == ["core", "weather"] and (.selectedCapabilities | index("notification-send") != null)' ${weatherRuntime.passthru.compatibilityBin}/feature-surface.json >/dev/null
            jq -e '.selectedFeatures == ["core", "screenshot"] and (.selectedCapabilities | index("notification-send") != null)' ${screenshotRuntime.passthru.compatibilityBin}/feature-surface.json >/dev/null
            test -e ${weatherRuntime.passthru.compatibilityBin}/bin/omarchy-notification-send
            test -e ${screenshotRuntime.passthru.compatibilityBin}/bin/omarchy-notification-send
            jq -e '
              has("trigger.emoji")
              and (has("apps") | not)
              and (has("trigger.screenshot") | not)
              and (has("system.logout") | not)
            ' ${clipboardRuntime.passthru.safeMenu} >/dev/null
            jq -e '.disabledPlugins | index("omarchy.network") == null and index("omarchy.audio") == null' ${clipboardRuntime.passthru.safeShellConfig} >/dev/null
            touch "$out"
          '';
          feature-runtime-inputs = pkgs.runCommand "omanixy-feature-runtime-inputs"
            {
              nativeBuildInputs = [ pkgs.bash pkgs.coreutils pkgs.gnused pkgs.jq ];
            } ''
            ${pkgs.bash}/bin/bash ${./test/feature-runtime-inputs.sh} ${./upstream/compatibility-contracts.json} ${capabilityRuntimePaths}
            touch "$out"
          '';
          feature-closure = pkgs.runCommand "omanixy-feature-closure"
            {
              nativeBuildInputs = [ pkgs.bash pkgs.coreutils pkgs.gnugrep pkgs.gnused pkgs.jq ];
            } ''
            ${pkgs.bash}/bin/bash ${./test/feature-closure.sh} \
              ${weatherRuntime} ${bluetoothRuntime} ${audioRuntime} ${launcherRuntime} \
              ${screenshotRuntime} ${coreRuntime} ${monitorRuntime}
            touch "$out"
          '';
          feature-consumer-closure = pkgs.runCommand "omanixy-feature-consumer-closure"
            {
              nativeBuildInputs = [ pkgs.bash pkgs.coreutils pkgs.jq pkgs.python3 ];
            } ''
            PYTHONPATH=${./scripts} ${pkgs.bash}/bin/bash ${./test/feature-consumer-closure.sh} \
              ${./.} ${runtime.passthru.omarchySource} \
              ${runtime.passthru.omarchyCompatibilityRoot} \
              ${runtime.passthru.compatibilityBin} \
              ${weatherRuntime.passthru.omarchyCompatibilityRoot} \
              ${weatherRuntime.passthru.compatibilityBin} \
              ${clipboardRuntime.passthru.omarchyCompatibilityRoot} \
              ${clipboardRuntime.passthru.compatibilityBin} \
              ${coreRuntime.passthru.omarchyCompatibilityRoot} \
              ${coreRuntime.passthru.compatibilityBin} \
              ${launcherRuntime.passthru.omarchyCompatibilityRoot} \
              ${launcherRuntime.passthru.compatibilityBin} \
              ${screenshotRuntime.passthru.omarchyCompatibilityRoot} \
              ${screenshotRuntime.passthru.compatibilityBin} \
              ${./scripts/check-feature-consumer-closure}
            touch "$out"
          '';
          feature-lifecycle = pkgs.runCommand "omanixy-feature-lifecycle"
            {
              nativeBuildInputs = [ pkgs.bash pkgs.coreutils pkgs.gnugrep pkgs.gnused pkgs.diffutils pkgs.findutils pkgs.jq ];
            } ''
            ${pkgs.bash}/bin/bash ${./test/feature-lifecycle.sh} \
              ${activationScript} ${clipboardActivationScript} ${coreActivationScript} \
              ${runtime} ${clipboardRuntime} ${coreRuntime} \
            ${runtime.passthru.omarchyCompatibilityRoot} \
              ${clipboardRuntime.passthru.omarchyCompatibilityRoot} \
              ${coreRuntime.passthru.omarchyCompatibilityRoot} \
              ${runtime.passthru.quickshell}/bin/quickshell \
              ${audioActivationScript} ${weatherActivationScript} ${networkActivationScript} \
              ${audioRuntime} ${weatherRuntime} ${networkRuntime} \
              ${audioRuntime.passthru.omarchyCompatibilityRoot} \
              ${weatherRuntime.passthru.omarchyCompatibilityRoot} \
              ${networkRuntime.passthru.omarchyCompatibilityRoot} \
              ${bluetoothRuntime.passthru.omarchyCompatibilityRoot} \
              ${screenshotRuntime.passthru.omarchyCompatibilityRoot}
            touch "$out"
          '';
          config-ownership = pkgs.runCommand "omanixy-config-ownership"
            {
              activation = activationScript;
              customActivation = customActivationScript;
              malformedStoreConfig = malformedStoreConfig;
              nativeBuildInputs = [ pkgs.bash pkgs.coreutils pkgs.diffutils pkgs.jq ];
            } ''
            ${pkgs.bash}/bin/bash ${./test/config-ownership.sh} "$activation" "$customActivation" /build/omanixy-test /build/omanixy-custom-test /build/omanixy-store-link-test ${storeConfig} ${explicitStoreConfig} "$malformedStoreConfig" ${customStoreConfig} ${./upstream/shell-baseline-v1.json}
            touch "$out"
          '';
          service-unit = pkgs.runCommand "omanixy-service-unit"
            {
              nativeBuildInputs = [ pkgs.bash pkgs.coreutils pkgs.gnugrep pkgs.systemd ];
            } ''
            unit_dir=$(mktemp -d)
            cp ${serviceUnit} "$unit_dir/omanixy-shell.service"
            ${pkgs.bash}/bin/bash ${./test/service-unit.sh} "$unit_dir/omanixy-shell.service" ${runtime} ${compatibilityRoot}
            printf '%s\n' '[Unit]' > "$unit_dir/sysinit.target"
            printf '%s\n' '[Unit]' > "$unit_dir/basic.target"
            XDG_RUNTIME_DIR="$unit_dir" \
              SYSTEMD_UNIT_PATH="$unit_dir" \
              SYSTEMD_SYSTEM_UNIT_PATH="$unit_dir" \
              SYSTEMD_USER_UNIT_PATH="$unit_dir" \
              systemd-analyze --user verify "$unit_dir/omanixy-shell.service" || {
                status=$?
                cat "$unit_dir/omanixy-shell.service"
                exit "$status"
              }
            touch "$out"
          '';
          stale-text = pkgs.runCommand "omanixy-stale-text"
            {
              nativeBuildInputs = [ pkgs.bash pkgs.gnugrep pkgs.jq pkgs.ripgrep (pkgs.python3.withPackages (ps: [ ps.pyyaml ])) ];
            } ''
            ${pkgs.bash}/bin/bash ${./test/stale-text.sh} ${./.}
            touch "$out"
          '';
          configuration-contract = pkgs.runCommand "omanixy-configuration-contract"
            {
              invalidConfiguration = if invalidHomeConfiguration.success then "true" else "false";
              invalidDisabledPluginsType = if invalidDisabledPluginsType.success then "true" else "false";
              invalidDisabledPluginMember = if invalidDisabledPluginMember.success then "true" else "false";
              unsupportedPlatform = if unsupportedPlatform.success then "true" else "false";
            } ''
            test "$invalidConfiguration" = false
            test "$invalidDisabledPluginsType" = false
            test "$invalidDisabledPluginMember" = false
            test "$unsupportedPlatform" = false
            touch "$out"
          '';
          home-manager-evaluation = pkgs.runCommand "omanixy-home-manager-evaluation"
            {
              activation = homeConfiguration.activationPackage;
            } ''
            test -x "$activation/activate"
            touch "$out"
          '';
          nixos-evaluation = pkgs.runCommand "omanixy-nixos-evaluation" { } ''
            test "${nixosConfiguration.config.system.stateVersion}" = 26.11
            touch "$out"
          '';
          security-pam = pkgs.runCommand "omanixy-security-pam"
            {
              disabledHasPasswordService = if builtins.hasAttr "pam.d/omarchy-lock-password" nixosConfiguration.config.environment.etc then "true" else "false";
              disabledHasFingerprintService = if builtins.hasAttr "pam.d/omarchy-lock-fingerprint" nixosConfiguration.config.environment.etc then "true" else "false";
              enabledHasFingerprintService = if builtins.hasAttr "pam.d/omarchy-lock-fingerprint" pamPasswordNixosConfiguration.config.environment.etc then "true" else "false";
              enabledPolkitEnabled = if pamPasswordNixosConfiguration.config.security.polkit.enable then "true" else "false";
              disabledPolkitEnabled = if nixosConfiguration.config.security.polkit.enable then "true" else "false";
              serviceFile = pamPasswordServiceFile;
              nativeBuildInputs = [ pkgs.bash pkgs.coreutils pkgs.gnugrep pkgs.ripgrep ];
            } ''
            ${pkgs.bash}/bin/bash ${./test/security-pam.sh} ${./.} "$serviceFile" \
              "$disabledHasPasswordService" "$disabledHasFingerprintService" \
              "$enabledHasFingerprintService" "$enabledPolkitEnabled" "$disabledPolkitEnabled"
            touch "$out"
          '';
          quattro-contract-audit = pkgs.runCommand "omanixy-quattro-contract-audit"
            {
              nativeBuildInputs = [ pkgs.bash pkgs.coreutils pkgs.diffutils pkgs.jq pkgs.python3 ];
            } ''
            generated="$TMPDIR/quattro-contracts.json"
            PYTHONPATH=${./scripts} ${pkgs.python3}/bin/python3 ${./scripts/audit-quattro-contracts} ${runtime.passthru.omarchySource} > "$generated"
            cmp "$generated" ${./upstream/quattro-contracts.json}
            ${pkgs.bash}/bin/bash ${./test/quattro-contract-audit.sh} ${./.}
            touch "$out"
          '';
          security-contracts = pkgs.runCommand "omanixy-security-contracts"
            {
              nativeBuildInputs = [ pkgs.bash pkgs.coreutils pkgs.gnugrep pkgs.jq pkgs.ripgrep (pkgs.python3.withPackages (ps: [ ps.pyyaml ])) ];
            } ''
            PYTHON=${pkgs.python3.withPackages (ps: [ ps.pyyaml ])}/bin/python ${pkgs.bash}/bin/bash ${./test/security-contracts.sh} ${./.} ${runtime.passthru.omarchyCompatibilityRoot}
            touch "$out"
          '';
          contract-closure = pkgs.runCommand "omanixy-contract-closure"
            {
              nativeBuildInputs = [ pkgs.bash pkgs.coreutils pkgs.gawk pkgs.gnugrep pkgs.gnused pkgs.jq pkgs.procps pkgs.python3 pkgs.util-linux ];
            } ''
            PYTHONPATH=${./scripts} ${pkgs.python3}/bin/python3 ${./scripts/check-contract-closure} \
              ${./.} ${runtime.passthru.omarchySource} ${compatibilityRoot} ${runtime.passthru.compatibilityBin} ${runtime.passthru.compatibilityProbes} ${runtime} \
              ${./upstream/compatibility-contracts.json} ${./upstream/quattro-contracts.json} \
              ${./test/compat-adapters.sh} ${./packages/omanixy-shell/compat-adapter.bash} ${./scripts/audit-quattro-contracts}
            touch "$out"
          '';
          contract-closure-adversarial = pkgs.runCommand "omanixy-contract-closure-adversarial"
            {
              nativeBuildInputs = [ pkgs.bash pkgs.coreutils pkgs.gawk pkgs.gnugrep pkgs.gnused pkgs.jq pkgs.procps pkgs.python3 pkgs.util-linux ];
            } ''
            OMANIXY_RUNTIME=${runtime} PYTHON=${pkgs.python3}/bin/python3 ${pkgs.bash}/bin/bash ${./test/contract-closure.sh} \
              ${./.} ${runtime.passthru.omarchySource} ${compatibilityRoot} ${runtime.passthru.compatibilityBin} ${runtime.passthru.compatibilityProbes}
            touch "$out"
          '';
          compat-adapters = pkgs.runCommand "omanixy-compat-adapters"
            {
              nativeBuildInputs = [ pkgs.bash pkgs.coreutils pkgs.gawk pkgs.gnugrep pkgs.gnused pkgs.jq pkgs.procps pkgs.util-linux ];
            } ''
            bash -n ${./packages/omanixy-shell/compat-adapter.bash}
            ${pkgs.bash}/bin/bash ${./test/compat-adapters.sh} ${./.} ${compatibilityRoot}
            touch "$out"
          '';
          compatibility-test-matrix = pkgs.runCommand "omanixy-compatibility-test-matrix"
            {
              nativeBuildInputs = [ pkgs.bash pkgs.coreutils pkgs.gawk pkgs.gnugrep pkgs.gnused pkgs.jq pkgs.procps pkgs.python3 pkgs.util-linux ];
            } ''
            PYTHON=${pkgs.python3}/bin/python3 ${pkgs.bash}/bin/bash ${./test/compatibility-test-matrix.sh} ${./.} ${compatibilityRoot} ${./upstream/compatibility-test-matrix.json} ${runtime}/bin
            touch "$out"
          '';
          safe-menu-contract = pkgs.runCommand "omanixy-safe-menu-contract"
            {
              nativeBuildInputs = [ pkgs.bash pkgs.coreutils pkgs.gnugrep pkgs.gnused pkgs.jq pkgs.python3 pkgs.nodejs ];
            } ''
            ${pkgs.bash}/bin/bash ${./test/safe-menu-contract.sh} ${runtime} ${compatibilityRoot} ${./test/uwsm-integration.sh} ${runtime}/bin/quickshell
            touch "$out"
          '';
          qml-patch-behavior = pkgs.runCommand "omanixy-qml-patch-behavior"
            {
              nativeBuildInputs = [ pkgs.bash pkgs.nodejs pkgs.python3 pkgs.coreutils pkgs.gnugrep pkgs.gnused ];
            } ''
            PYTHON=${pkgs.python3}/bin/python3 ${pkgs.bash}/bin/bash ${./test/qml-patch-behavior.sh} ${compatibilityRoot} ${runtime.passthru.omarchySource} ${./scripts/patch-transparent-foreground-process} ${runtime}/bin/quickshell ${./scripts/patch-menu-power-provider} ${./scripts/patch-menu-font-provider} ${./scripts/patch-menu-terminal-provider}
            touch "$out"
          '';
          launcher-delete-contract = pkgs.runCommand "omanixy-launcher-delete-contract"
            {
              nativeBuildInputs = [ pkgs.bash pkgs.nodejs pkgs.gnugrep pkgs.coreutils ];
            } ''
            ${pkgs.bash}/bin/bash ${./test/launcher-delete-contract.sh} ${compatibilityRoot} ${runtime}
            touch "$out"
          '';
          uwsm-integration = pkgs.runCommand "omanixy-uwsm-integration"
            {
              nativeBuildInputs = [ pkgs.bash pkgs.coreutils pkgs.gnugrep pkgs.gnused pkgs.nodejs ];
            } ''
            ${pkgs.bash}/bin/bash ${./test/uwsm-integration.sh} ${runtime} ${compatibilityRoot} ${runtime}/bin/quickshell
            touch "$out"
          '';
        });
    };
}
