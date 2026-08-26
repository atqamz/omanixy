{
  description = "Standalone public Omanixy consumer fixture";

  inputs = {
    omanixy.url = "path:../..";
    nixpkgs.follows = "omanixy/nixpkgs";
    home-manager.follows = "omanixy/home-manager";
  };

  outputs = { omanixy, nixpkgs, home-manager, ... }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      lib = nixpkgs.lib;
      username = "omanixy";
      homeDirectory = "/home/${username}";
      homeIdentity = {
        home.username = username;
        home.homeDirectory = homeDirectory;
        home.stateVersion = "25.11";
      };
      standaloneHome = home-manager.lib.homeManagerConfiguration {
        inherit pkgs;
        modules = [
          omanixy.homeManagerModules.default
          ./home.nix
          homeIdentity
        ];
      };
      defaultHome = home-manager.lib.homeManagerConfiguration {
        inherit pkgs;
        modules = [
          omanixy.homeManagerModules.default
          homeIdentity
          {
            programs.omanixy.enable = true;
          }
        ];
      };
      invalidStandaloneLock = home-manager.lib.homeManagerConfiguration {
        inherit pkgs;
        modules = [
          omanixy.homeManagerModules.default
          ./home.nix
          homeIdentity
          {
            programs.omanixy.security.lock.enable = lib.mkForce true;
          }
        ];
      };
      integratedNixos = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          omanixy.nixosModules.default
          home-manager.nixosModules.home-manager
          ./configuration.nix
          {
            nixpkgs.hostPlatform = system;
            users.users.${username} = {
              isNormalUser = true;
              home = homeDirectory;
            };
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.users.${username} = {
              imports = [
                omanixy.homeManagerModules.default
                ./home.nix
              ];
              home.username = username;
              home.homeDirectory = homeDirectory;
              home.stateVersion = "25.11";
              programs.omanixy.security.lock.enable = lib.mkForce true;
            };
          }
        ];
      };
      standaloneService = standaloneHome.config.systemd.user.services.omanixy-shell;
      standaloneSecurity = standaloneHome.config.programs.omanixy.security;
      standaloneActivationClosure = pkgs.closureInfo {
        rootPaths = [ standaloneHome.activationPackage ];
      };
      runtime = builtins.head standaloneHome.config.home.packages;
      runtimeClosure = pkgs.closureInfo {
        rootPaths = [ runtime ];
      };
      renderedService = pkgs.writeText "omanixy-standalone-service-unit" ''
        [Unit]
        Description=${standaloneService.Unit.Description}
        PartOf=${nixpkgs.lib.concatStringsSep " " standaloneService.Unit.PartOf}
        After=${nixpkgs.lib.concatStringsSep " " standaloneService.Unit.After}
        StartLimitIntervalSec=${standaloneService.Unit.StartLimitIntervalSec}
        StartLimitBurst=${toString standaloneService.Unit.StartLimitBurst}

        [Service]
        ExecStart=${nixpkgs.lib.concatStringsSep " " standaloneService.Service.ExecStart}
        Restart=${standaloneService.Service.Restart}
        RestartSec=${standaloneService.Service.RestartSec}
        TimeoutStopSec=${standaloneService.Service.TimeoutStopSec}
        ${nixpkgs.lib.concatMapStringsSep "\n" (environment: "Environment=" + environment) standaloneService.Service.Environment}

        [Install]
        WantedBy=${nixpkgs.lib.concatStringsSep " " standaloneService.Install.WantedBy}
      '';
      defaultActivation = pkgs.writeShellScript "omanixy-standalone-default-activation" defaultHome.config.home.activation.omanixyShellState.data;
      customActivation = pkgs.writeShellScript "omanixy-standalone-custom-activation" standaloneHome.config.home.activation.omanixyShellState.data;
      storeConfig = pkgs.writeText "omanixy-standalone-store-config" (builtins.readFile ../../upstream/shell-baseline-v1.json);
      explicitStoreConfig = pkgs.writeText "omanixy-standalone-explicit-store-config" ''{"version":1,"disabledPlugins":["omarchy.audio","omarchy.network"]}'';
      malformedStoreConfig = pkgs.writeText "omanixy-standalone-malformed-store-config" ''{"disabledPlugins":'';
      customStoreConfig = pkgs.writeText "omanixy-standalone-custom-store-config" ''{"version":1,"custom":true}'';
      integratedHome = integratedNixos.config.home-manager.users.${username};
      integratedService = integratedHome.systemd.user.services.omanixy-shell;
      invalidLockEvaluation = builtins.tryEval (builtins.deepSeq invalidStandaloneLock.activationPackage true);
      invalidLockDiagnosticSource = builtins.readFile ../../modules/home/default.nix;
      invalidLockDiagnosticOk =
        !invalidLockEvaluation.success
        && lib.hasInfix "standalone (no NixOS osConfig is" invalidLockDiagnosticSource
        && lib.hasInfix "programs.omanixy.security.pam.password" invalidLockDiagnosticSource;
      serviceContractOk =
        builtins.elem "${runtime}/bin/omanixy-shell-runtime" standaloneService.Service.ExecStart
        && standaloneService.Service.Restart == "on-failure"
        && standaloneService.Service.RestartSec == "2s"
        && standaloneService.Service.TimeoutStopSec == "10s"
        && builtins.elem "graphical-session.target" standaloneService.Unit.PartOf
        && builtins.elem "graphical-session.target" standaloneService.Unit.After
        && builtins.elem "graphical-session.target" standaloneService.Install.WantedBy
        && lib.any (value: lib.hasPrefix "OMARCHY_PATH=/nix/store/" value) standaloneService.Service.Environment
        && builtins.elem "QS_DISABLE_FILE_WATCHER=1" standaloneService.Service.Environment
        && builtins.elem "QS_NO_RELOAD_POPUP=1" standaloneService.Service.Environment;
      safeOwnershipOk =
        !standaloneSecurity.lock.enable
        && !standaloneSecurity.lock.fingerprint.enable
        && !standaloneSecurity.polkit.agent.enable
        && !standaloneSecurity.idle.enable
        && !standaloneSecurity.notifications.daemon.enable
        && standaloneHome.config.services.mako.enable;
      overrideContractOk =
        !(builtins.elem "clipboard" standaloneHome.config.programs.omanixy.features)
        && standaloneHome.config.programs.omanixy.shell.config.custom
        && builtins.elem "omarchy.bluetooth" standaloneHome.config.programs.omanixy.shell.config.disabledPlugins;
      hostCapabilitiesOk =
        integratedNixos.config.networking.networkmanager.enable
        && integratedNixos.config.hardware.bluetooth.enable
        && integratedNixos.config.services.pipewire.enable
        && integratedNixos.config.services.pipewire.pulse.enable
        && integratedNixos.config.services.upower.enable
        && integratedNixos.config.services.power-profiles-daemon.enable
        && integratedNixos.config.programs.hyprland.enable;
      integratedContractOk =
        integratedNixos.config.programs.omanixy.security.pam.password.enable
        && integratedHome.programs.omanixy.security.lock.enable
        && builtins.elem "${runtime}/bin/omanixy-shell-runtime" integratedService.Service.ExecStart;
      pamService = integratedNixos.config.environment.etc."pam.d/omarchy-lock-password".source;
      nixosToplevel = integratedNixos.config.system.build.toplevel.drvPath;
    in
    {
      homeConfigurations.default = standaloneHome;
      nixosConfigurations.default = integratedNixos;

      checks.${system} = {
        home-manager = standaloneHome.activationPackage;

        adoption-contract = pkgs.runCommand "omanixy-standalone-adoption-contract"
          {
            inherit pamService nixosToplevel;
            omanixySource = omanixy.outPath;
            activationStorePaths = "${standaloneActivationClosure}/store-paths";
            runtimeStorePaths = "${runtimeClosure}/store-paths";
            runtimePath = runtime;
            compatibilityRoot = runtime.passthru.omarchyCompatibilityRoot;
            compatibilityBin = runtime.passthru.compatibilityBin;
            quickshellPath = runtime.passthru.quickshell;
            inherit renderedService defaultActivation customActivation storeConfig explicitStoreConfig malformedStoreConfig customStoreConfig;
            serviceContract = if serviceContractOk then "true" else "false";
            safeOwnership = if safeOwnershipOk then "true" else "false";
            overrideContract = if overrideContractOk then "true" else "false";
            hostCapabilities = if hostCapabilitiesOk then "true" else "false";
            integratedContract = if integratedContractOk then "true" else "false";
            invalidLockDiagnostic = if invalidLockDiagnosticOk then "true" else "false";
            nativeBuildInputs = [ pkgs.bash pkgs.coreutils pkgs.gawk pkgs.gnugrep pkgs.gnused pkgs.jq pkgs.ripgrep pkgs.systemd ];
          } ''
          test "$serviceContract" = true
          test "$safeOwnership" = true
          test "$overrideContract" = true
          test "$hostCapabilities" = true
          test "$integratedContract" = true
          test "$invalidLockDiagnostic" = true
          test -n "$nixosToplevel"
          test -s "$pamService"
          grep -Fq 'pam_unix.so' "$pamService"
          grep -Fxq "$runtimePath" "$runtimeStorePaths"
          grep -Fxq "$quickshellPath" "$runtimeStorePaths"
          grep -Fxq "$compatibilityRoot" "$runtimeStorePaths"
          grep -Fxq "$compatibilityBin" "$runtimeStorePaths"
          ${pkgs.bash}/bin/bash ${../../test/service-unit.sh} "$renderedService" "$runtimePath" "$compatibilityRoot"
          unit_dir=$(mktemp -d)
          trap 'rm -rf "$unit_dir"' EXIT
          cp "$renderedService" "$unit_dir/omanixy-shell.service"
          printf '%s\n' '[Unit]' > "$unit_dir/sysinit.target"
          printf '%s\n' '[Unit]' > "$unit_dir/basic.target"
          XDG_RUNTIME_DIR="$unit_dir" SYSTEMD_UNIT_PATH="$unit_dir" SYSTEMD_SYSTEM_UNIT_PATH="$unit_dir" SYSTEMD_USER_UNIT_PATH="$unit_dir" \
            systemd-analyze --user verify "$unit_dir/omanixy-shell.service"
          ${pkgs.bash}/bin/bash ${../../test/config-ownership.sh} \
            "$defaultActivation" "$customActivation" /build/omanixy-test /build/omanixy-custom /build/omanixy-store \
            "$storeConfig" "$explicitStoreConfig" "$malformedStoreConfig" "$customStoreConfig" ${../../upstream/shell-baseline-v1.json}
          if grep -Fq 'universe' "$activationStorePaths"; then
            exit 1
          fi
          if grep -R -n -E '/home/atqa|sfx14|pavg15|~/dotfiles|atqamz/universe|Hand|private paths' ${./.}; then
            exit 1
          fi
          grep -Fq '## What Omanixy is' "$omanixySource/README.md"
          grep -Fq '## Prerequisites and session assumptions' "$omanixySource/README.md"
          grep -Fq '## Install with flakes' "$omanixySource/README.md"
          grep -Fq '## Feature and support matrix' "$omanixySource/README.md"
          grep -Fq '## Troubleshooting' "$omanixySource/README.md"
          grep -Fq '## Upgrades and releases' "$omanixySource/README.md"
          touch "$out"
        '';
      };
    };
}
