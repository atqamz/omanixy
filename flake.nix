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
      nixpkgsRevision = "241313f4e8e508cb9b13278c2b0fa25b9ca27163";
      forEachSystem = nixpkgs.lib.genAttrs supportedSystems;
      runtimeFor = system:
        assert nixpkgs.lib.assertOneOf "omanixy supported system" system supportedSystems;
        import ./packages/omanixy-shell {
          inherit omarchy;
          lib = nixpkgs.lib;
          pkgs = nixpkgs.legacyPackages.${system};
          quickshellSrc = quickshell;
          inherit nixpkgsRevision supportedSystems;
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
        _module.args.omanixyRuntime = runtimeFor pkgs.stdenv.hostPlatform.system;
        imports = [ ./modules/home/default.nix ];
      };
      nixosModules.default = ./modules/nixos/default.nix;
      packages = forEachSystem (system: {
        omanixy-shell = runtimeFor system;
      });
      formatter = forEachSystem (system: nixpkgs.legacyPackages.${system}.nixpkgs-fmt);
      checks = forEachSystem (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          runtime = runtimeFor system;
          runtimeClosureInfo = pkgs.closureInfo { rootPaths = [ runtime ]; };
          compatibilityRoot = runtime.passthru.omarchyCompatibilityRoot;
          storeConfig = "${runtime.passthru.omarchySource}/config/omarchy/shell.json";
          malformedStoreConfig = pkgs.writeText "omanixy-malformed-store-shell-config" ''{"disabledPlugins":'';
          homeConfiguration = homeConfigurationFor system { };
          customHomeConfiguration = homeConfigurationFor system {
            programs.omanixy.shell.config = {
              version = 1;
              custom = true;
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
            builtins.deepSeq (runtimeFor "x86_64-darwin") true
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
          service = homeConfiguration.config.systemd.user.services.omanixy-shell;
          activationScript = pkgs.writeShellScript "omanixy-shell-state-activation" homeConfiguration.config.home.activation.omanixyShellState.data;
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
          pin-invariants = pkgs.runCommand "omanixy-pin-invariants" {
            nativeBuildInputs = [ pkgs.bash pkgs.gnugrep pkgs.jq pkgs.ripgrep ];
          } ''
            ${pkgs.bash}/bin/bash ${./test/pin-invariants.sh} ${./.}
            touch "$out"
          '';
          ipc-wrapper = pkgs.runCommand "omanixy-ipc-wrapper" {
            nativeBuildInputs = [ pkgs.bash pkgs.coreutils pkgs.gnugrep pkgs.gnused pkgs.python3 ];
          } ''
            PYTHON=${pkgs.python3}/bin/python3 ${pkgs.bash}/bin/bash ${./test/ipc-wrapper.sh} ${./.}
            touch "$out"
          '';
          runtime-closure = pkgs.runCommand "omanixy-runtime-closure" {
            closurePaths = "${runtimeClosureInfo}/store-paths";
            nativeBuildInputs = [ pkgs.bash pkgs.coreutils pkgs.gnugrep pkgs.gnused pkgs.findutils ];
          } ''
            ${pkgs.bash}/bin/bash ${./test/runtime-closure.sh} ${runtime} "$closurePaths" ${runtime.passthru.quickshell} ${runtime.passthru.omarchySource} ${compatibilityRoot} ${runtime.passthru.compatibilityBin}
            touch "$out"
          '';
          config-ownership = pkgs.runCommand "omanixy-config-ownership" {
            activation = activationScript;
            customActivation = customActivationScript;
            malformedStoreConfig = malformedStoreConfig;
            nativeBuildInputs = [ pkgs.bash pkgs.coreutils pkgs.diffutils pkgs.jq ];
          } ''
            ${pkgs.bash}/bin/bash ${./test/config-ownership.sh} "$activation" "$customActivation" /build/omanixy-test /build/omanixy-custom-test /build/omanixy-store-link-test ${storeConfig} "$malformedStoreConfig"
            touch "$out"
          '';
          service-unit = pkgs.runCommand "omanixy-service-unit" {
            nativeBuildInputs = [ pkgs.bash pkgs.coreutils pkgs.gnugrep pkgs.systemd ];
          } ''
            unit_dir=$(mktemp -d)
            cp ${serviceUnit} "$unit_dir/omanixy-shell.service"
            ${pkgs.bash}/bin/bash ${./test/service-unit.sh} "$unit_dir/omanixy-shell.service" ${runtime} ${runtime.passthru.omarchySource} ${compatibilityRoot}
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
          stale-text = pkgs.runCommand "omanixy-stale-text" {
            nativeBuildInputs = [ pkgs.bash pkgs.gnugrep pkgs.ripgrep ];
          } ''
            ${pkgs.bash}/bin/bash ${./test/stale-text.sh} ${./.}
            touch "$out"
          '';
          configuration-contract = pkgs.runCommand "omanixy-configuration-contract" {
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
          home-manager-evaluation = pkgs.runCommand "omanixy-home-manager-evaluation" {
            activation = homeConfiguration.activationPackage;
          } ''
            test -x "$activation/activate"
            touch "$out"
          '';
          nixos-evaluation = pkgs.runCommand "omanixy-nixos-evaluation" { } ''
            test "${nixosConfiguration.config.system.stateVersion}" = 26.11
            touch "$out"
          '';
          quattro-contract-audit = pkgs.runCommand "omanixy-quattro-contract-audit" {
            nativeBuildInputs = [ pkgs.bash pkgs.coreutils pkgs.diffutils pkgs.jq pkgs.python3 ];
          } ''
            generated="$TMPDIR/quattro-contracts.json"
            ${pkgs.python3}/bin/python3 ${./scripts/audit-quattro-contracts} ${runtime.passthru.omarchySource} > "$generated"
            cmp "$generated" ${./upstream/quattro-contracts.json}
            ${pkgs.bash}/bin/bash ${./test/quattro-contract-audit.sh} ${./.}
            touch "$out"
          '';
          compat-adapters = pkgs.runCommand "omanixy-compat-adapters" {
            nativeBuildInputs = [ pkgs.bash pkgs.coreutils pkgs.gawk pkgs.gnugrep pkgs.gnused pkgs.jq ];
          } ''
            bash -n ${./packages/omanixy-shell/compat-adapter.bash}
            ${pkgs.bash}/bin/bash ${./test/compat-adapters.sh} ${./.}
            touch "$out"
          '';
          safe-menu-contract = pkgs.runCommand "omanixy-safe-menu-contract" {
            nativeBuildInputs = [ pkgs.bash pkgs.coreutils pkgs.gnugrep pkgs.gnused pkgs.jq ];
          } ''
            ${pkgs.bash}/bin/bash ${./test/safe-menu-contract.sh} ${runtime} ${compatibilityRoot}
            touch "$out"
          '';
        });
    };
}
