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
      runtimeForSecurity = system: features: security:
        assert nixpkgs.lib.assertOneOf "omanixy supported system" system supportedSystems;
        import ./packages/omanixy-shell {
          inherit omarchy;
          lib = nixpkgs.lib;
          pkgs = nixpkgs.legacyPackages.${system};
          quickshellSrc = quickshell;
          inherit nixpkgsRevision supportedSystems;
          inherit features security;
        };
      runtimeFor = system: features: runtimeForSecurity system features null;
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
        _module.args.omanixyRuntimeFor = features: security: runtimeForSecurity pkgs.stdenv.hostPlatform.system features security;
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
          lib = nixpkgs.lib;
          releasePython = pkgs.python3.withPackages (ps: [ ps.pyyaml ]);
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
          lockRuntime = runtimeForSecurity system null { lock = true; };
          lockFingerprintRuntime = runtimeForSecurity system null { lock = true; fingerprint = true; fingerprintPackage = pkgs.fprintd; };
          coreLockRuntime = runtimeForSecurity system [ "core" ] { lock = true; };
          polkitRuntime = runtimeForSecurity system null { polkitAgent = true; };
          corePolkitRuntime = runtimeForSecurity system [ "core" ] { polkitAgent = true; };
          idleRuntime = runtimeForSecurity system null { lock = true; idle = true; };
          coreLockIdleRuntime = runtimeForSecurity system [ "core" ] { lock = true; idle = true; };
          notificationDaemonRuntime = runtimeForSecurity system null { notificationDaemon = true; };
          coreNotificationDaemonRuntime = runtimeForSecurity system [ "core" ] { notificationDaemon = true; };
          notificationClientAndDaemonRuntime = runtimeForSecurity system [ "notification" ] { notificationDaemon = true; };
          allSecurityWithoutNotificationDaemonRuntime = runtimeForSecurity system null {
            lock = true;
            fingerprint = true;
            fingerprintPackage = pkgs.fprintd;
            polkitAgent = true;
            idle = true;
          };
          allSecurityWithNotificationDaemonRuntime = runtimeForSecurity system null {
            lock = true;
            fingerprint = true;
            fingerprintPackage = pkgs.fprintd;
            polkitAgent = true;
            idle = true;
            notificationDaemon = true;
          };
          packageIdleWithoutLockEval = builtins.tryEval (
            builtins.seq (runtimeForSecurity system null { idle = true; lock = false; }).drvPath true
          );
          packageIdleWithLockEval = builtins.tryEval (
            builtins.seq (runtimeForSecurity system null { idle = true; lock = true; }).drvPath true
          );
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
          sniPython = pkgs.python3.withPackages (ps: [ ps.dbus-next ]);
          lockRuntimeClosureInfo = pkgs.closureInfo { rootPaths = [ lockRuntime ]; };
          lockFingerprintRuntimeClosureInfo = pkgs.closureInfo { rootPaths = [ lockFingerprintRuntime ]; };
          coreLockRuntimeClosureInfo = pkgs.closureInfo { rootPaths = [ coreLockRuntime ]; };
          polkitRuntimeClosureInfo = pkgs.closureInfo { rootPaths = [ polkitRuntime ]; };
          corePolkitRuntimeClosureInfo = pkgs.closureInfo { rootPaths = [ corePolkitRuntime ]; };
          coreRuntimeClosureInfo = pkgs.closureInfo { rootPaths = [ coreRuntime ]; };
          coreLockIdleRuntimeClosureInfo = pkgs.closureInfo { rootPaths = [ coreLockIdleRuntime ]; };
          coreNotificationDaemonRuntimeClosureInfo = pkgs.closureInfo { rootPaths = [ coreNotificationDaemonRuntime ]; };
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
          nestedPositionHomeConfiguration = homeConfigurationFor system {
            programs.omanixy.shell.config = {
              bar.position = "bottom";
            };
          };
          nestedLayoutHomeConfiguration = homeConfigurationFor system {
            programs.omanixy.shell.config = {
              bar.layout.right = [{ id = "custom.right"; }];
            };
          };
          nestedFloorHomeConfiguration = homeConfigurationFor system {
            programs.omanixy.shell.config = {
              bar.transparent = true;
              disabledPlugins = [ "omarchy.audio" ];
            };
          };
          disabledBackgroundHomeConfiguration = homeConfigurationFor system {
            programs.omanixy.background.enable = false;
          };
          disabledBackgroundRuntime = lib.findFirst
            (p: (p.name or "") == "omanixy-shell")
            (throw "disabled background runtime package not found")
            disabledBackgroundHomeConfiguration.config.home.packages;
          fontOverrideHomeConfiguration = homeConfigurationFor system {
            fonts.fontconfig.defaultFonts.monospace = [ "DejaVu Sans Mono" ];
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
          bootableStub = {
            fileSystems."/" = {
              device = "/dev/null";
              fsType = "ext4";
            };
            boot.loader.grub.devices = [ "/dev/null" ];
          };
          toplevelForced = nixosConfig: (builtins.tryEval (builtins.seq nixosConfig.config.system.build.toplevel.drvPath true)).success;
          pamPasswordNixosConfiguration = nixpkgs.lib.nixosSystem {
            inherit system;
            modules = [
              self.nixosModules.default
              bootableStub
              {
                nixpkgs.hostPlatform = system;
                system.stateVersion = "26.11";
                programs.omanixy.security.pam.password.enable = true;
              }
            ];
          };
          pamPasswordServiceFile = "${pamPasswordNixosConfiguration.config.environment.etc."pam.d/omarchy-lock-password".source}";
          pamPasswordAdversarialNixosConfiguration = nixpkgs.lib.nixosSystem {
            inherit system;
            modules = [
              self.nixosModules.default
              bootableStub
              {
                nixpkgs.hostPlatform = system;
                system.stateVersion = "26.11";
                programs.omanixy.security.pam.password.enable = true;
              }
              (
                { config, ... }:
                {
                  security.pam.services."omarchy-lock-password".text = ''
                    auth sufficient ${config.security.pam.package}/lib/security/pam_permit.so
                  '';
                }
              )
            ];
          };
          pamPasswordAdversarialServiceFile = "${pamPasswordAdversarialNixosConfiguration.config.environment.etc."pam.d/omarchy-lock-password".source}";
          pamPasswordEnableConflictNixosConfiguration = nixpkgs.lib.nixosSystem {
            inherit system;
            modules = [
              self.nixosModules.default
              bootableStub
              {
                nixpkgs.hostPlatform = system;
                system.stateVersion = "26.11";
                programs.omanixy.security.pam.password.enable = true;
              }
              {
                security.pam.services."omarchy-lock-password".enable = false;
              }
            ];
          };
          pamPasswordEnableConflictServiceFile = "${pamPasswordEnableConflictNixosConfiguration.config.environment.etc."pam.d/omarchy-lock-password".source}";
          pamPasswordStrongConflictNixosConfiguration = nixpkgs.lib.nixosSystem {
            inherit system;
            modules = [
              self.nixosModules.default
              bootableStub
              {
                nixpkgs.hostPlatform = system;
                system.stateVersion = "26.11";
                programs.omanixy.security.pam.password.enable = true;
              }
              (
                { config, lib, ... }:
                {
                  security.pam.services."omarchy-lock-password".text = lib.mkForce ''
                    auth sufficient ${config.security.pam.package}/lib/security/pam_permit.so
                  '';
                }
              )
            ];
          };
          pamPasswordStrongConflictServiceFile = "${pamPasswordStrongConflictNixosConfiguration.config.environment.etc."pam.d/omarchy-lock-password".source}";
          pamFingerprintNixosConfiguration = nixpkgs.lib.nixosSystem {
            inherit system;
            modules = [
              self.nixosModules.default
              bootableStub
              {
                nixpkgs.hostPlatform = system;
                system.stateVersion = "26.11";
                programs.omanixy.security.pam.fingerprint.enable = true;
              }
            ];
          };
          pamFingerprintServiceFile = "${pamFingerprintNixosConfiguration.config.environment.etc."pam.d/omarchy-lock-fingerprint".source}";
          pamFingerprintAdversarialNixosConfiguration = nixpkgs.lib.nixosSystem {
            inherit system;
            modules = [
              self.nixosModules.default
              bootableStub
              {
                nixpkgs.hostPlatform = system;
                system.stateVersion = "26.11";
                programs.omanixy.security.pam.fingerprint.enable = true;
              }
              {
                security.pam.services."omarchy-lock-fingerprint".text = ''
                  auth sufficient /run/wrappers/bin/pam_permit_placeholder.so
                '';
              }
            ];
          };
          pamFingerprintAdversarialServiceFile = "${pamFingerprintAdversarialNixosConfiguration.config.environment.etc."pam.d/omarchy-lock-fingerprint".source}";
          pamFingerprintEnableConflictNixosConfiguration = nixpkgs.lib.nixosSystem {
            inherit system;
            modules = [
              self.nixosModules.default
              bootableStub
              {
                nixpkgs.hostPlatform = system;
                system.stateVersion = "26.11";
                programs.omanixy.security.pam.fingerprint.enable = true;
              }
              {
                security.pam.services."omarchy-lock-fingerprint".enable = false;
              }
            ];
          };
          pamFingerprintEnableConflictServiceFile = "${pamFingerprintEnableConflictNixosConfiguration.config.environment.etc."pam.d/omarchy-lock-fingerprint".source}";
          pamFingerprintStrongConflictNixosConfiguration = nixpkgs.lib.nixosSystem {
            inherit system;
            modules = [
              self.nixosModules.default
              bootableStub
              {
                nixpkgs.hostPlatform = system;
                system.stateVersion = "26.11";
                programs.omanixy.security.pam.fingerprint.enable = true;
              }
              (
                { lib, ... }:
                {
                  security.pam.services."omarchy-lock-fingerprint".text = lib.mkForce ''
                    auth sufficient /run/wrappers/bin/pam_permit_placeholder.so
                  '';
                }
              )
            ];
          };
          pamFingerprintStrongConflictServiceFile = "${pamFingerprintStrongConflictNixosConfiguration.config.environment.etc."pam.d/omarchy-lock-fingerprint".source}";
          pamFingerprintFprintdEnableConflictNixosConfiguration = nixpkgs.lib.nixosSystem {
            inherit system;
            modules = [
              self.nixosModules.default
              bootableStub
              {
                nixpkgs.hostPlatform = system;
                system.stateVersion = "26.11";
                programs.omanixy.security.pam.fingerprint.enable = true;
                services.fprintd.enable = true;
                services.openssh.enable = true;
                security.polkit.enable = true;
              }
            ];
          };
          pamFingerprintNoWideningNixosConfiguration = nixpkgs.lib.nixosSystem {
            inherit system;
            modules = [
              self.nixosModules.default
              bootableStub
              {
                nixpkgs.hostPlatform = system;
                system.stateVersion = "26.11";
                programs.omanixy.security.pam.fingerprint.enable = true;
                services.openssh.enable = true;
                security.polkit.enable = true;
              }
            ];
          };
          standaloneLockDisabledEval = builtins.tryEval (
            builtins.seq (homeConfigurationFor system { }).activationPackage.drvPath true
          );
          standaloneLockEnabledEval = builtins.tryEval (
            builtins.seq
              (homeConfigurationFor system {
                programs.omanixy.security.lock.enable = true;
              }).activationPackage.drvPath
              true
          );
          standaloneFingerprintLockDisabledEval = builtins.tryEval (
            builtins.seq
              (homeConfigurationFor system {
                programs.omanixy.security.lock.fingerprint.enable = true;
              }).activationPackage.drvPath
              true
          );
          standaloneFingerprintLockEnabledEval = builtins.tryEval (
            builtins.seq
              (homeConfigurationFor system {
                programs.omanixy.security.lock.enable = true;
                programs.omanixy.security.lock.fingerprint.enable = true;
              }).activationPackage.drvPath
              true
          );
          integratedHomeManagerNixosConfigurationFor = pamEnabled: lockEnabled: nixpkgs.lib.nixosSystem {
            inherit system;
            modules = [
              self.nixosModules.default
              bootableStub
              home-manager.nixosModules.home-manager
              {
                nixpkgs.hostPlatform = system;
                system.stateVersion = "26.11";
                programs.omanixy.security.pam.password.enable = pamEnabled;
                users.users."omanixy-test" = {
                  isNormalUser = true;
                  home = "/build/omanixy-test";
                };
                home-manager.useGlobalPkgs = true;
                home-manager.useUserPackages = true;
                home-manager.users."omanixy-test" = {
                  imports = [ self.homeManagerModules.default ];
                  home.username = "omanixy-test";
                  home.homeDirectory = "/build/omanixy-test";
                  home.stateVersion = "25.11";
                  programs.omanixy.enable = true;
                  programs.omanixy.security.lock.enable = lockEnabled;
                };
              }
            ];
          };
          integratedPamOffLockOffNixosConfiguration = integratedHomeManagerNixosConfigurationFor false false;
          integratedPamOnLockOffNixosConfiguration = integratedHomeManagerNixosConfigurationFor true false;
          integratedPamOffLockOnNixosConfiguration = integratedHomeManagerNixosConfigurationFor false true;
          integratedPamOnLockOnNixosConfiguration = integratedHomeManagerNixosConfigurationFor true true;
          integratedFingerprintHomeManagerNixosConfigurationFor = pamPasswordEnabled: pamFingerprintEnabled: hmFingerprintEnabled: nixpkgs.lib.nixosSystem {
            inherit system;
            modules = [
              self.nixosModules.default
              bootableStub
              home-manager.nixosModules.home-manager
              {
                nixpkgs.hostPlatform = system;
                system.stateVersion = "26.11";
                programs.omanixy.security.pam.password.enable = pamPasswordEnabled;
                programs.omanixy.security.pam.fingerprint.enable = pamFingerprintEnabled;
                users.users."omanixy-test" = {
                  isNormalUser = true;
                  home = "/build/omanixy-test";
                };
                home-manager.useGlobalPkgs = true;
                home-manager.useUserPackages = true;
                home-manager.users."omanixy-test" = {
                  imports = [ self.homeManagerModules.default ];
                  home.username = "omanixy-test";
                  home.homeDirectory = "/build/omanixy-test";
                  home.stateVersion = "25.11";
                  programs.omanixy.enable = true;
                  programs.omanixy.security.lock.enable = true;
                  programs.omanixy.security.lock.fingerprint.enable = hmFingerprintEnabled;
                };
              }
            ];
          };
          integratedFingerprintPamOffFingerprintOffNixosConfiguration = integratedFingerprintHomeManagerNixosConfigurationFor false false true;
          integratedFingerprintPamOnFingerprintOffNixosConfiguration = integratedFingerprintHomeManagerNixosConfigurationFor true false true;
          integratedFingerprintPamOffFingerprintOnNixosConfiguration = integratedFingerprintHomeManagerNixosConfigurationFor false true true;
          integratedFingerprintPamOnFingerprintOnNixosConfiguration = integratedFingerprintHomeManagerNixosConfigurationFor true true true;
          integratedFingerprintPamOnFingerprintOnHmDisabledNixosConfiguration = integratedFingerprintHomeManagerNixosConfigurationFor true true false;
          customFprintdPackage = pkgs.fprintd.overrideAttrs (old: {
            pname = "omanixy-test-fprintd";
          });
          integratedFingerprintCustomPackageNixosConfiguration = nixpkgs.lib.nixosSystem {
            inherit system;
            modules = [
              self.nixosModules.default
              bootableStub
              home-manager.nixosModules.home-manager
              {
                nixpkgs.hostPlatform = system;
                system.stateVersion = "26.11";
                programs.omanixy.security.pam.password.enable = true;
                programs.omanixy.security.pam.fingerprint.enable = true;
                services.fprintd.package = customFprintdPackage;
                users.users."omanixy-test" = {
                  isNormalUser = true;
                  home = "/build/omanixy-test";
                };
                home-manager.useGlobalPkgs = true;
                home-manager.useUserPackages = true;
                home-manager.users."omanixy-test" = {
                  imports = [ self.homeManagerModules.default ];
                  home.username = "omanixy-test";
                  home.homeDirectory = "/build/omanixy-test";
                  home.stateVersion = "25.11";
                  programs.omanixy.enable = true;
                  programs.omanixy.security.lock.enable = true;
                  programs.omanixy.security.lock.fingerprint.enable = true;
                };
              }
            ];
          };
          integratedFingerprintCustomPackageServiceFile = "${integratedFingerprintCustomPackageNixosConfiguration.config.environment.etc."pam.d/omarchy-lock-fingerprint".source}";
          integratedFingerprintCustomPackageRuntime = builtins.elemAt
            integratedFingerprintCustomPackageNixosConfiguration.config.home-manager.users."omanixy-test".home.packages
            0;
          polkitSystemNixosConfiguration = nixpkgs.lib.nixosSystem {
            inherit system;
            modules = [
              self.nixosModules.default
              bootableStub
              {
                nixpkgs.hostPlatform = system;
                system.stateVersion = "26.11";
                programs.omanixy.security.polkit.system.enable = true;
              }
            ];
          };
          plainPolkitNixosConfiguration = nixpkgs.lib.nixosSystem {
            inherit system;
            modules = [
              self.nixosModules.default
              bootableStub
              {
                nixpkgs.hostPlatform = system;
                system.stateVersion = "26.11";
                security.polkit.enable = true;
              }
            ];
          };
          polkitSystemAdversarialNixosConfiguration = nixpkgs.lib.nixosSystem {
            inherit system;
            modules = [
              self.nixosModules.default
              bootableStub
              {
                nixpkgs.hostPlatform = system;
                system.stateVersion = "26.11";
                programs.omanixy.security.polkit.system.enable = true;
              }
              (
                { lib, ... }:
                {
                  security.polkit.enable = lib.mkForce false;
                }
              )
            ];
          };
          standalonePolkitAgentEnabledEval = builtins.tryEval (
            builtins.seq
              (homeConfigurationFor system {
                programs.omanixy.security.polkit.agent.enable = true;
              }).activationPackage.drvPath
              true
          );
          standaloneNotificationDaemonEnabledEval = builtins.tryEval (
            builtins.seq
              (homeConfigurationFor system {
                programs.omanixy.security.notifications.daemon.enable = true;
              }).activationPackage.drvPath
              true
          );
          standaloneNotificationDaemonMakoConflictEval = builtins.tryEval (
            builtins.deepSeq
              (homeConfigurationFor system {
                programs.omanixy.security.notifications.daemon.enable = true;
                services.mako.enable = true;
              }).activationPackage
              true
          );
          standaloneNotificationDaemonDunstConflictEval = builtins.tryEval (
            builtins.deepSeq
              (homeConfigurationFor system {
                programs.omanixy.security.notifications.daemon.enable = true;
                services.dunst.enable = true;
              }).activationPackage
              true
          );
          standaloneNotificationDaemonSwayncConflictEval = builtins.tryEval (
            builtins.deepSeq
              (homeConfigurationFor system {
                programs.omanixy.security.notifications.daemon.enable = true;
                services.swaync.enable = true;
              }).activationPackage
              true
          );
          standaloneNotificationDaemonFnottConflictEval = builtins.tryEval (
            builtins.deepSeq
              (homeConfigurationFor system {
                programs.omanixy.security.notifications.daemon.enable = true;
                services.fnott.enable = true;
              }).activationPackage
              true
          );
          standaloneNotificationDaemonOffAllConflictsOnEval = builtins.tryEval (
            builtins.seq
              (homeConfigurationFor system {
                services.mako.enable = true;
                services.dunst.enable = true;
                services.swaync.enable = true;
                services.fnott.enable = true;
              }).activationPackage.drvPath
              true
          );
          standaloneNotificationDaemonWithClientFeatureEval = builtins.tryEval (
            builtins.seq
              (homeConfigurationFor system {
                programs.omanixy.features = [ "notification" ];
                programs.omanixy.security.notifications.daemon.enable = true;
              }).activationPackage.drvPath
              true
          );
          integratedPolkitHomeManagerNixosConfigurationFor = systemEnabled: agentEnabled: hyprpolkitagentEnabled: polkitGnomeEnabled: nixpkgs.lib.nixosSystem {
            inherit system;
            modules = [
              self.nixosModules.default
              bootableStub
              home-manager.nixosModules.home-manager
              {
                nixpkgs.hostPlatform = system;
                system.stateVersion = "26.11";
                programs.omanixy.security.polkit.system.enable = systemEnabled;
                users.users."omanixy-test" = {
                  isNormalUser = true;
                  home = "/build/omanixy-test";
                };
                home-manager.useGlobalPkgs = true;
                home-manager.useUserPackages = true;
                home-manager.users."omanixy-test" = {
                  imports = [ self.homeManagerModules.default ];
                  home.username = "omanixy-test";
                  home.homeDirectory = "/build/omanixy-test";
                  home.stateVersion = "25.11";
                  programs.omanixy.enable = true;
                  programs.omanixy.security.polkit.agent.enable = agentEnabled;
                  services.hyprpolkitagent.enable = hyprpolkitagentEnabled;
                  services.polkit-gnome.enable = polkitGnomeEnabled;
                };
              }
            ];
          };
          integratedPolkitOffOffNixosConfiguration = integratedPolkitHomeManagerNixosConfigurationFor false false false false;
          integratedPolkitOnOffNixosConfiguration = integratedPolkitHomeManagerNixosConfigurationFor true false false false;
          integratedPolkitOffOnNixosConfiguration = integratedPolkitHomeManagerNixosConfigurationFor false true false false;
          integratedPolkitOnOnNixosConfiguration = integratedPolkitHomeManagerNixosConfigurationFor true true false false;
          integratedPolkitOnOnHyprConflictNixosConfiguration = integratedPolkitHomeManagerNixosConfigurationFor true true true false;
          integratedPolkitOnOnGnomeConflictNixosConfiguration = integratedPolkitHomeManagerNixosConfigurationFor true true false true;
          integratedPolkitAgentOffHyprNixosConfiguration = integratedPolkitHomeManagerNixosConfigurationFor false false true false;
          integratedPolkitAgentOffGnomeNixosConfiguration = integratedPolkitHomeManagerNixosConfigurationFor false false false true;
          integratedIdleHomeManagerNixosConfigurationFor = lockEnabled: idleEnabled: hypridleEnabled: swayidleEnabled: fingerprintEnabled: polkitAgentEnabled: nixpkgs.lib.nixosSystem {
            inherit system;
            modules = [
              self.nixosModules.default
              bootableStub
              home-manager.nixosModules.home-manager
              {
                nixpkgs.hostPlatform = system;
                system.stateVersion = "26.11";
                programs.omanixy.security.pam.password.enable = lockEnabled;
                programs.omanixy.security.pam.fingerprint.enable = fingerprintEnabled;
                programs.omanixy.security.polkit.system.enable = polkitAgentEnabled;
                users.users."omanixy-test" = {
                  isNormalUser = true;
                  home = "/build/omanixy-test";
                };
                home-manager.useGlobalPkgs = true;
                home-manager.useUserPackages = true;
                home-manager.users."omanixy-test" = {
                  imports = [ self.homeManagerModules.default ];
                  home.username = "omanixy-test";
                  home.homeDirectory = "/build/omanixy-test";
                  home.stateVersion = "25.11";
                  programs.omanixy.enable = true;
                  programs.omanixy.security.lock.enable = lockEnabled;
                  programs.omanixy.security.lock.fingerprint.enable = fingerprintEnabled;
                  programs.omanixy.security.idle.enable = idleEnabled;
                  programs.omanixy.security.polkit.agent.enable = polkitAgentEnabled;
                  services.hypridle.enable = hypridleEnabled;
                  services.swayidle.enable = swayidleEnabled;
                };
              }
            ];
          };
          integratedIdleAllOffNixosConfiguration = integratedIdleHomeManagerNixosConfigurationFor false false false false false false;
          integratedIdleOnLockOffNixosConfiguration = integratedIdleHomeManagerNixosConfigurationFor false true false false false false;
          integratedIdleOnLockOnNixosConfiguration = integratedIdleHomeManagerNixosConfigurationFor true true false false false false;
          integratedIdleOnHypridleConflictNixosConfiguration = integratedIdleHomeManagerNixosConfigurationFor true true true false false false;
          integratedIdleOnSwayidleConflictNixosConfiguration = integratedIdleHomeManagerNixosConfigurationFor true true false true false false;
          integratedIdleOnBothConflictNixosConfiguration = integratedIdleHomeManagerNixosConfigurationFor true true true true false false;
          integratedIdleOffBothDaemonsOnNixosConfiguration = integratedIdleHomeManagerNixosConfigurationFor false false true true false false;
          integratedIdleOnFingerprintOnNixosConfiguration = integratedIdleHomeManagerNixosConfigurationFor true true false false true false;
          integratedIdleOnPolkitOnNixosConfiguration = integratedIdleHomeManagerNixosConfigurationFor true true false false false true;
          integratedIdleOffLockOnNixosConfiguration = integratedIdleHomeManagerNixosConfigurationFor true false false false false false;
          pamFingerprintPolkitSystemNixosConfiguration = nixpkgs.lib.nixosSystem {
            inherit system;
            modules = [
              self.nixosModules.default
              bootableStub
              {
                nixpkgs.hostPlatform = system;
                system.stateVersion = "26.11";
                programs.omanixy.security.pam.fingerprint.enable = true;
                programs.omanixy.security.polkit.system.enable = true;
              }
            ];
          };
          pamFingerprintPolkitSystemServiceFile = "${pamFingerprintPolkitSystemNixosConfiguration.config.environment.etc."pam.d/omarchy-lock-fingerprint".source}";
          todDriverPackage = pkgs.runCommand "omanixy-test-tod-driver"
            {
              passthru.driverPath = "/lib/libfprint-2/tod-1";
            } "mkdir -p \"$out\"";
          pamFingerprintTodNixosConfiguration = nixpkgs.lib.nixosSystem {
            inherit system;
            modules = [
              self.nixosModules.default
              bootableStub
              {
                nixpkgs.hostPlatform = system;
                system.stateVersion = "26.11";
                programs.omanixy.security.pam.fingerprint.enable = true;
                services.fprintd.tod.enable = true;
                services.fprintd.tod.driver = todDriverPackage;
              }
            ];
          };
          pamFingerprintTodServiceFile = "${pamFingerprintTodNixosConfiguration.config.environment.etc."pam.d/omarchy-lock-fingerprint".source}";
          service = homeConfiguration.config.systemd.user.services.omanixy-shell;
          activationScript = pkgs.writeShellScript "omanixy-shell-state-activation" homeConfiguration.config.home.activation.omanixyShellState.data;
          disabledBackgroundActivationScript = pkgs.writeShellScript "omanixy-shell-disabled-background-state-activation" disabledBackgroundHomeConfiguration.config.home.activation.omanixyShellState.data;
          clipboardActivationScript = pkgs.writeShellScript "omanixy-shell-clipboard-state-activation" clipboardHomeConfiguration.config.home.activation.omanixyShellState.data;
          coreActivationScript = pkgs.writeShellScript "omanixy-shell-core-state-activation" coreHomeConfiguration.config.home.activation.omanixyShellState.data;
          audioActivationScript = pkgs.writeShellScript "omanixy-shell-audio-state-activation" audioHomeConfiguration.config.home.activation.omanixyShellState.data;
          weatherActivationScript = pkgs.writeShellScript "omanixy-shell-weather-state-activation" weatherHomeConfiguration.config.home.activation.omanixyShellState.data;
          networkActivationScript = pkgs.writeShellScript "omanixy-shell-network-state-activation" networkHomeConfiguration.config.home.activation.omanixyShellState.data;
          customActivationScript = pkgs.writeShellScript "omanixy-shell-custom-state-activation" customHomeConfiguration.config.home.activation.omanixyShellState.data;
          nestedPositionActivationScript = pkgs.writeShellScript "omanixy-shell-nested-position-state-activation" nestedPositionHomeConfiguration.config.home.activation.omanixyShellState.data;
          nestedLayoutActivationScript = pkgs.writeShellScript "omanixy-shell-nested-layout-state-activation" nestedLayoutHomeConfiguration.config.home.activation.omanixyShellState.data;
          nestedFloorActivationScript = pkgs.writeShellScript "omanixy-shell-nested-floor-state-activation" nestedFloorHomeConfiguration.config.home.activation.omanixyShellState.data;
          defaultFontConfig = homeConfiguration.config.xdg.configFile."fontconfig/conf.d/52-hm-default-fonts.conf".source;
          overrideFontConfig = fontOverrideHomeConfiguration.config.xdg.configFile."fontconfig/conf.d/52-hm-default-fonts.conf".source;
          fontPackageProvisioned = builtins.elem pkgs.nerd-fonts.jetbrains-mono homeConfiguration.config.home.packages;
          lockEnabledActivationScript = pkgs.writeShellScript "omanixy-shell-lock-state-activation"
            integratedPamOnLockOnNixosConfiguration.config.home-manager.users."omanixy-test".home.activation.omanixyShellState.data;
          polkitEnabledActivationScript = pkgs.writeShellScript "omanixy-shell-polkit-state-activation"
            integratedPolkitOnOnNixosConfiguration.config.home-manager.users."omanixy-test".home.activation.omanixyShellState.data;
          idleEnabledActivationScript = pkgs.writeShellScript "omanixy-shell-idle-state-activation"
            integratedIdleOnLockOnNixosConfiguration.config.home-manager.users."omanixy-test".home.activation.omanixyShellState.data;
          notificationDaemonHomeConfiguration = homeConfigurationFor system {
            programs.omanixy.security.notifications.daemon.enable = true;
          };
          notificationDaemonEnabledActivationScript = pkgs.writeShellScript "omanixy-shell-notification-daemon-state-activation"
            notificationDaemonHomeConfiguration.config.home.activation.omanixyShellState.data;
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
          sni-contract = pkgs.runCommand "omanixy-sni-contract"
            {
              nativeBuildInputs = [ pkgs.bash pkgs.coreutils pkgs.dbus pkgs.gnugrep pkgs.systemd sniPython ];
            } ''
            DBUS_SESSION_CONFIG=${pkgs.dbus}/share/dbus-1/session.conf \
              PYTHON=${sniPython}/bin/python ${pkgs.bash}/bin/bash ${./test/sni-contract.sh} \
              ${./test/sni-provider.py} ${runtime}/bin/quickshell ${runtime} ${compatibilityRoot}
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
              nestedPositionActivation = nestedPositionActivationScript;
              nestedLayoutActivation = nestedLayoutActivationScript;
              nestedFloorActivation = nestedFloorActivationScript;
              malformedStoreConfig = malformedStoreConfig;
              nativeBuildInputs = [ pkgs.bash pkgs.coreutils pkgs.diffutils pkgs.jq ];
            } ''
            ${pkgs.bash}/bin/bash ${./test/config-ownership.sh} "$activation" "$customActivation" /build/omanixy-test /build/omanixy-custom-test /build/omanixy-store-link-test ${storeConfig} ${explicitStoreConfig} "$malformedStoreConfig" ${customStoreConfig} ${./upstream/shell-baseline-v1.json} "$nestedPositionActivation" "$nestedLayoutActivation" "$nestedFloorActivation"
            touch "$out"
          '';
          presentation-ownership = pkgs.runCommand "omanixy-presentation-ownership"
            {
              nativeBuildInputs = [ pkgs.bash pkgs.coreutils pkgs.gnugrep pkgs.jq pkgs.fontconfig ];
            } ''
            ${pkgs.bash}/bin/bash ${./test/presentation-ownership.sh} \
              ${activationScript} ${disabledBackgroundActivationScript} \
              ${defaultFontConfig} ${overrideFontConfig} \
              ${pkgs.nerd-fonts.jetbrains-mono} ${pkgs.dejavu_fonts} \
              ${runtime.passthru.defaultBackground} ${runtime.passthru.omarchyCompatibilityRoot} ${disabledBackgroundRuntime.passthru.omarchyCompatibilityRoot} \
              ${if fontPackageProvisioned then "true" else "false"} ${pkgs.fontconfig}/bin/fc-match
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
          security-polkit-system = pkgs.runCommand "omanixy-security-polkit-system"
            {
              disabledPolkitEnabled = if nixosConfiguration.config.security.polkit.enable then "true" else "false";
              systemEnabledPolkitEnable = if polkitSystemNixosConfiguration.config.security.polkit.enable then "true" else "false";
              systemEnabledPolkit1PamEnable = if polkitSystemNixosConfiguration.config.security.pam.services."polkit-1".enable then "true" else "false";
              systemEnabledPkexecWrapper = if polkitSystemNixosConfiguration.config.security.polkit.enablePkexecWrapper then "true" else "false";
              disabledPkexecWrapper = if nixosConfiguration.config.security.polkit.enablePkexecWrapper then "true" else "false";
              adversarialToplevelForced = if toplevelForced polkitSystemAdversarialNixosConfiguration then "true" else "false";
              plainPolkitToplevelForced = if toplevelForced plainPolkitNixosConfiguration then "true" else "false";
              plainPolkitEnable = if plainPolkitNixosConfiguration.config.security.polkit.enable then "true" else "false";
              systemdServicesMatch =
                if (builtins.attrNames polkitSystemNixosConfiguration.config.systemd.services)
                  == (builtins.attrNames plainPolkitNixosConfiguration.config.systemd.services)
                then "true" else "false";
              dbusPackagesMatch =
                if polkitSystemNixosConfiguration.config.services.dbus.packages
                  == plainPolkitNixosConfiguration.config.services.dbus.packages
                then "true" else "false";
              pamServicesMatch =
                if (builtins.attrNames polkitSystemNixosConfiguration.config.security.pam.services)
                  == (builtins.attrNames plainPolkitNixosConfiguration.config.security.pam.services)
                then "true" else "false";
              nativeBuildInputs = [ pkgs.bash pkgs.coreutils ];
            } ''
            ${pkgs.bash}/bin/bash ${./test/security-polkit-system.sh} \
              "$disabledPolkitEnabled" "$systemEnabledPolkitEnable" "$systemEnabledPolkit1PamEnable" \
              "$systemEnabledPkexecWrapper" "$disabledPkexecWrapper" "$adversarialToplevelForced" \
              "$plainPolkitToplevelForced" "$plainPolkitEnable" \
              "$systemdServicesMatch" "$dbusPackagesMatch" "$pamServicesMatch"
            touch "$out"
          '';
          security-pam-composition = pkgs.runCommand "omanixy-security-pam-composition"
            {
              ownedServiceFile = pamPasswordServiceFile;
              adversarialServiceFile = pamPasswordAdversarialServiceFile;
              nativeBuildInputs = [ pkgs.bash pkgs.coreutils pkgs.diffutils pkgs.gnugrep ];
            } ''
            ${pkgs.bash}/bin/bash ${./test/security-pam-composition.sh} \
              "$ownedServiceFile" "$adversarialServiceFile"
            touch "$out"
          '';
          security-pam-writer-guard = pkgs.runCommand "omanixy-security-pam-writer-guard"
            {
              nativeBuildInputs = [ pkgs.bash pkgs.coreutils pkgs.ripgrep ];
            } ''
            ${pkgs.bash}/bin/bash ${./test/security-pam-writer-guard.sh} ${./test/lib/no-imperative-pam-write.sh}
            touch "$out"
          '';
          security-pam-capability = pkgs.runCommand "omanixy-security-pam-capability"
            {
              ownedServiceFile = pamPasswordServiceFile;
              ownedEnable = if pamPasswordNixosConfiguration.config.security.pam.services."omarchy-lock-password".enable then "true" else "false";
              ownedToplevelForced = if toplevelForced pamPasswordNixosConfiguration then "true" else "false";
              adversarialToplevelForced = if toplevelForced pamPasswordAdversarialNixosConfiguration then "true" else "false";
              enableConflictServiceFile = pamPasswordEnableConflictServiceFile;
              enableConflictEnable = if pamPasswordEnableConflictNixosConfiguration.config.security.pam.services."omarchy-lock-password".enable then "true" else "false";
              enableConflictToplevelForced = if toplevelForced pamPasswordEnableConflictNixosConfiguration then "true" else "false";
              strongConflictServiceFile = pamPasswordStrongConflictServiceFile;
              strongConflictToplevelForced = if toplevelForced pamPasswordStrongConflictNixosConfiguration then "true" else "false";
              nativeBuildInputs = [ pkgs.bash pkgs.coreutils pkgs.diffutils pkgs.gnugrep ];
            } ''
            ${pkgs.bash}/bin/bash ${./test/security-pam-capability.sh} \
              "$ownedServiceFile" "$ownedEnable" "$ownedToplevelForced" \
              "$adversarialToplevelForced" \
              "$enableConflictServiceFile" "$enableConflictEnable" "$enableConflictToplevelForced" \
              "$strongConflictServiceFile" "$strongConflictToplevelForced"
            touch "$out"
          '';
          security-pam-fingerprint = pkgs.runCommand "omanixy-security-pam-fingerprint"
            {
              serviceFile = pamFingerprintServiceFile;
              enabledHasPasswordService = if builtins.hasAttr "pam.d/omarchy-lock-password" pamFingerprintNixosConfiguration.config.environment.etc then "true" else "false";
              enabledPolkitEnabled = if pamFingerprintNixosConfiguration.config.security.polkit.enable then "true" else "false";
              nativeBuildInputs = [ pkgs.bash pkgs.coreutils pkgs.gnugrep pkgs.ripgrep ];
            } ''
            ${pkgs.bash}/bin/bash ${./test/security-pam-fingerprint.sh} ${./.} "$serviceFile" \
              "$enabledHasPasswordService" "$enabledPolkitEnabled"
            touch "$out"
          '';
          security-pam-fingerprint-composition = pkgs.runCommand "omanixy-security-pam-fingerprint-composition"
            {
              ownedServiceFile = pamFingerprintServiceFile;
              adversarialServiceFile = pamFingerprintAdversarialServiceFile;
              nativeBuildInputs = [ pkgs.bash pkgs.coreutils pkgs.diffutils pkgs.gnugrep ];
            } ''
            ${pkgs.bash}/bin/bash ${./test/security-pam-fingerprint-composition.sh} \
              "$ownedServiceFile" "$adversarialServiceFile"
            touch "$out"
          '';
          security-pam-fingerprint-capability = pkgs.runCommand "omanixy-security-pam-fingerprint-capability"
            {
              ownedServiceFile = pamFingerprintServiceFile;
              ownedEnable = if pamFingerprintNixosConfiguration.config.security.pam.services."omarchy-lock-fingerprint".enable then "true" else "false";
              ownedToplevelForced = if toplevelForced pamFingerprintNixosConfiguration then "true" else "false";
              adversarialToplevelForced = if toplevelForced pamFingerprintAdversarialNixosConfiguration then "true" else "false";
              enableConflictServiceFile = pamFingerprintEnableConflictServiceFile;
              enableConflictEnable = if pamFingerprintEnableConflictNixosConfiguration.config.security.pam.services."omarchy-lock-fingerprint".enable then "true" else "false";
              enableConflictToplevelForced = if toplevelForced pamFingerprintEnableConflictNixosConfiguration then "true" else "false";
              strongConflictServiceFile = pamFingerprintStrongConflictServiceFile;
              strongConflictToplevelForced = if toplevelForced pamFingerprintStrongConflictNixosConfiguration then "true" else "false";
              nativeBuildInputs = [ pkgs.bash pkgs.coreutils pkgs.diffutils pkgs.gnugrep ];
            } ''
            ${pkgs.bash}/bin/bash ${./test/security-pam-fingerprint-capability.sh} \
              "$ownedServiceFile" "$ownedEnable" "$ownedToplevelForced" \
              "$adversarialToplevelForced" \
              "$enableConflictServiceFile" "$enableConflictEnable" "$enableConflictToplevelForced" \
              "$strongConflictServiceFile" "$strongConflictToplevelForced"
            touch "$out"
          '';
          security-pam-fingerprint-widening = pkgs.runCommand "omanixy-security-pam-fingerprint-widening"
            {
              fprintdEnableConflictToplevelForced = if toplevelForced pamFingerprintFprintdEnableConflictNixosConfiguration then "true" else "false";
              noWideningToplevelForced = if toplevelForced pamFingerprintNoWideningNixosConfiguration then "true" else "false";
              noWideningFprintdEnable = if pamFingerprintNoWideningNixosConfiguration.config.services.fprintd.enable then "true" else "false";
              noWideningLoginFprintAuth = if pamFingerprintNoWideningNixosConfiguration.config.security.pam.services.login.fprintAuth then "true" else "false";
              noWideningSudoFprintAuth = if pamFingerprintNoWideningNixosConfiguration.config.security.pam.services.sudo.fprintAuth then "true" else "false";
              noWideningSuFprintAuth = if pamFingerprintNoWideningNixosConfiguration.config.security.pam.services.su.fprintAuth then "true" else "false";
              noWideningSshdFprintAuth = if pamFingerprintNoWideningNixosConfiguration.config.security.pam.services.sshd.fprintAuth then "true" else "false";
              noWideningPolkitFprintAuth = if pamFingerprintNoWideningNixosConfiguration.config.security.pam.services."polkit-1".fprintAuth then "true" else "false";
              noWideningPackageRegistered =
                if
                  builtins.elem pamFingerprintNoWideningNixosConfiguration.config.services.fprintd.package pamFingerprintNoWideningNixosConfiguration.config.services.dbus.packages
                  && builtins.elem pamFingerprintNoWideningNixosConfiguration.config.services.fprintd.package pamFingerprintNoWideningNixosConfiguration.config.systemd.packages
                  && builtins.elem pamFingerprintNoWideningNixosConfiguration.config.services.fprintd.package pamFingerprintNoWideningNixosConfiguration.config.environment.systemPackages
                then "true" else "false";
              nativeBuildInputs = [ pkgs.bash pkgs.coreutils ];
            } ''
            ${pkgs.bash}/bin/bash ${./test/security-pam-fingerprint-widening.sh} \
              "$fprintdEnableConflictToplevelForced" "$noWideningToplevelForced" "$noWideningFprintdEnable" \
              "$noWideningLoginFprintAuth" "$noWideningSudoFprintAuth" "$noWideningSuFprintAuth" \
              "$noWideningSshdFprintAuth" "$noWideningPolkitFprintAuth" "$noWideningPackageRegistered"
            touch "$out"
          '';
          security-pam-fingerprint-custom-package = pkgs.runCommand "omanixy-security-pam-fingerprint-custom-package"
            {
              serviceFile = integratedFingerprintCustomPackageServiceFile;
              toplevelForcedOk = if toplevelForced integratedFingerprintCustomPackageNixosConfiguration then "true" else "false";
              dbusRegistered = if builtins.elem customFprintdPackage integratedFingerprintCustomPackageNixosConfiguration.config.services.dbus.packages then "true" else "false";
              systemdRegistered = if builtins.elem customFprintdPackage integratedFingerprintCustomPackageNixosConfiguration.config.systemd.packages then "true" else "false";
              environmentRegistered = if builtins.elem customFprintdPackage integratedFingerprintCustomPackageNixosConfiguration.config.environment.systemPackages then "true" else "false";
              declaredRuntimeInputs = pkgs.writeText "omanixy-lock-fingerprint-custom-package-declared-runtime-inputs.json" integratedFingerprintCustomPackageRuntime.passthru.declaredRuntimeInputs;
              customPackagePath = "${customFprintdPackage}";
              defaultPackagePath = "${pkgs.fprintd}";
              nativeBuildInputs = [ pkgs.bash pkgs.coreutils pkgs.gnugrep pkgs.jq ];
            } ''
            ${pkgs.bash}/bin/bash ${./test/security-pam-fingerprint-custom-package.sh} \
              "$serviceFile" "$toplevelForcedOk" \
              "$dbusRegistered" "$systemdRegistered" "$environmentRegistered" \
              "$declaredRuntimeInputs" "$customPackagePath" "$defaultPackagePath"
            touch "$out"
          '';
          security-pam-fingerprint-tod = pkgs.runCommand "omanixy-security-pam-fingerprint-tod"
            {
              serviceFile = pamFingerprintTodServiceFile;
              toplevelForcedOk = if toplevelForced pamFingerprintTodNixosConfiguration then "true" else "false";
              packagePath = "${pamFingerprintTodNixosConfiguration.config.services.fprintd.package}";
              expectedPackagePath = "${pkgs.fprintd-tod}";
              envValue = pamFingerprintTodNixosConfiguration.config.systemd.services.fprintd.environment.FP_TOD_DRIVERS_DIR or "";
              expectedEnvValue = "${todDriverPackage}${todDriverPackage.driverPath}";
              driverPath = "${todDriverPackage}";
              nativeBuildInputs = [ pkgs.bash pkgs.coreutils pkgs.gnugrep ];
            } ''
            ${pkgs.bash}/bin/bash ${./test/security-pam-fingerprint-tod.sh} \
              "$serviceFile" "$toplevelForcedOk" \
              "$packagePath" "$expectedPackagePath" \
              "$envValue" "$expectedEnvValue" "$driverPath"
            touch "$out"
          '';
          security-polkit-hm = pkgs.runCommand "omanixy-security-polkit-hm"
            {
              standaloneAgentDisabledOk = if standaloneLockDisabledEval.success then "true" else "false";
              standaloneAgentEnabledOk = if standalonePolkitAgentEnabledEval.success then "true" else "false";
              integratedOffOffOk = if toplevelForced integratedPolkitOffOffNixosConfiguration then "true" else "false";
              integratedOnOffOk = if toplevelForced integratedPolkitOnOffNixosConfiguration then "true" else "false";
              integratedOffOnOk = if toplevelForced integratedPolkitOffOnNixosConfiguration then "true" else "false";
              integratedOnOnOk = if toplevelForced integratedPolkitOnOnNixosConfiguration then "true" else "false";
              integratedOnOnHyprConflictOk = if toplevelForced integratedPolkitOnOnHyprConflictNixosConfiguration then "true" else "false";
              integratedOnOnGnomeConflictOk = if toplevelForced integratedPolkitOnOnGnomeConflictNixosConfiguration then "true" else "false";
              agentOffHyprOk = if toplevelForced integratedPolkitAgentOffHyprNixosConfiguration then "true" else "false";
              agentOffGnomeOk = if toplevelForced integratedPolkitAgentOffGnomeNixosConfiguration then "true" else "false";
              lockOnAgentOffOk = if toplevelForced integratedPamOnLockOnNixosConfiguration then "true" else "false";
              nativeBuildInputs = [ pkgs.bash pkgs.coreutils ];
            } ''
            ${pkgs.bash}/bin/bash ${./test/security-polkit-hm.sh} \
              "$standaloneAgentDisabledOk" "$standaloneAgentEnabledOk" \
              "$integratedOffOffOk" "$integratedOnOffOk" "$integratedOffOnOk" "$integratedOnOnOk" \
              "$integratedOnOnHyprConflictOk" "$integratedOnOnGnomeConflictOk" \
              "$agentOffHyprOk" "$agentOffGnomeOk" "$lockOnAgentOffOk"
            touch "$out"
          '';
          security-lock = pkgs.runCommand "omanixy-security-lock"
            {
              standaloneLockDisabledOk = if standaloneLockDisabledEval.success then "true" else "false";
              standaloneLockEnabledOk = if standaloneLockEnabledEval.success then "true" else "false";
              integratedOffOffOk = if toplevelForced integratedPamOffLockOffNixosConfiguration then "true" else "false";
              integratedOnOffOk = if toplevelForced integratedPamOnLockOffNixosConfiguration then "true" else "false";
              integratedOffOnOk = if toplevelForced integratedPamOffLockOnNixosConfiguration then "true" else "false";
              integratedOnOnOk = if toplevelForced integratedPamOnLockOnNixosConfiguration then "true" else "false";
              nativeBuildInputs = [ pkgs.bash pkgs.coreutils pkgs.gnugrep pkgs.jq pkgs.procps ];
            } ''
            ${pkgs.bash}/bin/bash ${./test/security-lock.sh} \
              ${lockRuntime.passthru.omarchyCompatibilityRoot} ${lockRuntime.passthru.compatibilityBin} ${lockRuntime} \
              ${compatibilityRoot} ${runtime.passthru.compatibilityBin} \
              "$standaloneLockDisabledOk" "$standaloneLockEnabledOk" \
              "$integratedOffOffOk" "$integratedOnOffOk" "$integratedOffOnOk" "$integratedOnOnOk" \
              ${./packages/omanixy-shell/adapters/common.bash} ${./packages/omanixy-shell/adapters/lock.bash}
            touch "$out"
          '';
          security-lock-shell-json = pkgs.runCommand "omanixy-security-lock-shell-json"
            {
              nativeBuildInputs = [ pkgs.bash pkgs.coreutils pkgs.diffutils pkgs.jq ];
            } ''
            ${pkgs.bash}/bin/bash ${./test/security-lock-shell-json.sh} \
              ${activationScript} ${lockEnabledActivationScript} ${storeConfig}
            touch "$out"
          '';
          security-polkit-shell-json = pkgs.runCommand "omanixy-security-polkit-shell-json"
            {
              nativeBuildInputs = [ pkgs.bash pkgs.coreutils pkgs.diffutils pkgs.jq ];
            } ''
            ${pkgs.bash}/bin/bash ${./test/security-polkit-shell-json.sh} \
              ${activationScript} ${polkitEnabledActivationScript} ${storeConfig}
            touch "$out"
          '';
          security-lock-closure = pkgs.runCommand "omanixy-security-lock-closure"
            {
              lockClosurePaths = "${lockRuntimeClosureInfo}/store-paths";
              nativeBuildInputs = [ pkgs.bash pkgs.coreutils pkgs.gnugrep pkgs.findutils pkgs.diffutils ];
            } ''
            ${pkgs.bash}/bin/bash ${./test/security-lock-closure.sh} \
              ${lockRuntime} "$lockClosurePaths" \
              ${lockRuntime.passthru.compatibilityBin} ${runtime.passthru.compatibilityBin}
            touch "$out"
          '';
          security-lock-executable-surface = pkgs.runCommand "omanixy-security-lock-executable-surface"
            {
              nativeBuildInputs = [ pkgs.bash pkgs.python3 ];
            } ''
            ${pkgs.bash}/bin/bash ${./test/security-lock-executable-surface.sh} \
              ${./scripts/scan-lock-executable-surface} \
              ${lockRuntime.passthru.omarchyCompatibilityRoot}/shell/plugins/lock/Service.qml \
              ${pkgs.python3}/bin/python3 ${./scripts}
            touch "$out"
          '';
          security-lock-fingerprint = pkgs.runCommand "omanixy-security-lock-fingerprint"
            {
              standaloneFingerprintLockDisabledOk = if standaloneFingerprintLockDisabledEval.success then "true" else "false";
              standaloneFingerprintLockEnabledOk = if standaloneFingerprintLockEnabledEval.success then "true" else "false";
              integratedOffOffOk = if toplevelForced integratedFingerprintPamOffFingerprintOffNixosConfiguration then "true" else "false";
              integratedOnOffOk = if toplevelForced integratedFingerprintPamOnFingerprintOffNixosConfiguration then "true" else "false";
              integratedOffOnOk = if toplevelForced integratedFingerprintPamOffFingerprintOnNixosConfiguration then "true" else "false";
              integratedOnOnOk = if toplevelForced integratedFingerprintPamOnFingerprintOnNixosConfiguration then "true" else "false";
              integratedOnOnHmDisabledOk = if toplevelForced integratedFingerprintPamOnFingerprintOnHmDisabledNixosConfiguration then "true" else "false";
              nativeBuildInputs = [ pkgs.bash pkgs.coreutils pkgs.gnugrep ];
            } ''
            ${pkgs.bash}/bin/bash ${./test/security-lock-fingerprint.sh} \
              ${lockFingerprintRuntime.passthru.omarchyCompatibilityRoot}/shell/plugins/lock/Service.qml \
              ${lockRuntime.passthru.omarchyCompatibilityRoot}/shell/plugins/lock/Service.qml \
              "$standaloneFingerprintLockDisabledOk" "$standaloneFingerprintLockEnabledOk" \
              "$integratedOffOffOk" "$integratedOnOffOk" "$integratedOffOnOk" "$integratedOnOnOk" "$integratedOnOnHmDisabledOk"
            touch "$out"
          '';
          security-lock-fingerprint-ready = pkgs.runCommand "omanixy-security-lock-fingerprint-ready"
            {
              nativeBuildInputs = [ pkgs.bash pkgs.coreutils ];
            } ''
            ${pkgs.bash}/bin/bash ${./test/security-lock-fingerprint-ready.sh} \
              ${./packages/omanixy-shell/adapters/common.bash} ${./packages/omanixy-shell/adapters/lock.bash}
            touch "$out"
          '';
          security-lock-fingerprint-executable-surface = pkgs.runCommand "omanixy-security-lock-fingerprint-executable-surface"
            {
              nativeBuildInputs = [ pkgs.bash pkgs.python3 ];
            } ''
            ${pkgs.bash}/bin/bash ${./test/security-lock-fingerprint-executable-surface.sh} \
              ${./scripts/scan-lock-executable-surface} \
              ${lockFingerprintRuntime.passthru.omarchyCompatibilityRoot}/shell/plugins/lock/Service.qml \
              ${pkgs.python3}/bin/python3 ${./scripts}
            touch "$out"
          '';
          security-lock-fingerprint-closure = pkgs.runCommand "omanixy-security-lock-fingerprint-closure"
            {
              lockClosurePaths = "${lockRuntimeClosureInfo}/store-paths";
              lockFingerprintClosurePaths = "${lockFingerprintRuntimeClosureInfo}/store-paths";
              declaredRuntimeInputs = pkgs.writeText "omanixy-lock-declared-runtime-inputs.json" lockRuntime.passthru.declaredRuntimeInputs;
              fingerprintDeclaredRuntimeInputs = pkgs.writeText "omanixy-lock-fingerprint-declared-runtime-inputs.json" lockFingerprintRuntime.passthru.declaredRuntimeInputs;
              nativeBuildInputs = [ pkgs.bash pkgs.coreutils pkgs.gnugrep pkgs.findutils pkgs.diffutils pkgs.jq ];
            } ''
            ${pkgs.bash}/bin/bash ${./test/security-lock-fingerprint-closure.sh} \
              "$lockClosurePaths" "$lockFingerprintClosurePaths" \
              "$declaredRuntimeInputs" "$fingerprintDeclaredRuntimeInputs" \
              ${lockRuntime.passthru.compatibilityBin} ${lockFingerprintRuntime.passthru.compatibilityBin} \
              ${pkgs.fprintd}
            touch "$out"
          '';
          security-lock-fingerprint-behavior = pkgs.runCommand "omanixy-security-lock-fingerprint-behavior"
            {
              nativeBuildInputs = [ pkgs.bash pkgs.nodejs ];
            } ''
            ${pkgs.bash}/bin/bash ${./test/security-lock-fingerprint-behavior.sh} \
              ${lockFingerprintRuntime.passthru.omarchyCompatibilityRoot}/shell/plugins/lock/FingerprintPolicy.js
            touch "$out"
          '';
          security-lock-managed-plugin = pkgs.runCommand "omanixy-security-lock-managed-plugin"
            {
              nativeBuildInputs = [ pkgs.bash pkgs.coreutils pkgs.findutils ];
            } ''
            ${pkgs.bash}/bin/bash ${./test/security-lock-managed-plugin.sh} \
              ${lockRuntime.passthru.omarchyCompatibilityRoot} ${lockRuntime}/bin/quickshell \
              ${compatibilityRoot} ${runtime}/bin/quickshell
            touch "$out"
          '';
          security-polkit-managed-plugin = pkgs.runCommand "omanixy-security-polkit-managed-plugin"
            {
              nativeBuildInputs = [ pkgs.bash pkgs.coreutils pkgs.findutils ];
            } ''
            ${pkgs.bash}/bin/bash ${./test/security-polkit-managed-plugin.sh} \
              ${polkitRuntime.passthru.omarchyCompatibilityRoot} ${polkitRuntime}/bin/quickshell \
              ${compatibilityRoot} ${runtime}/bin/quickshell
            touch "$out"
          '';
          security-lock-core-only = pkgs.runCommand "omanixy-security-lock-core-only"
            {
              coreClosurePaths = "${coreRuntimeClosureInfo}/store-paths";
              coreLockClosurePaths = "${coreLockRuntimeClosureInfo}/store-paths";
              coreDeclaredRuntimeInputs = pkgs.writeText "omanixy-core-declared-runtime-inputs.json" coreRuntime.passthru.declaredRuntimeInputs;
              coreLockDeclaredRuntimeInputs = pkgs.writeText "omanixy-core-lock-declared-runtime-inputs.json" coreLockRuntime.passthru.declaredRuntimeInputs;
              nativeBuildInputs = [ pkgs.bash pkgs.coreutils pkgs.gnugrep pkgs.findutils pkgs.diffutils pkgs.jq ];
            } ''
            ${pkgs.bash}/bin/bash ${./test/security-lock-core-only.sh} \
              ${coreLockRuntime.passthru.compatibilityBin} ${coreRuntime.passthru.compatibilityBin} \
              "$coreClosurePaths" "$coreLockClosurePaths" \
              "$coreDeclaredRuntimeInputs" "$coreLockDeclaredRuntimeInputs"
            touch "$out"
          '';
          security-polkit-core-only = pkgs.runCommand "omanixy-security-polkit-core-only"
            {
              coreClosurePaths = "${coreRuntimeClosureInfo}/store-paths";
              corePolkitClosurePaths = "${corePolkitRuntimeClosureInfo}/store-paths";
              coreDeclaredRuntimeInputs = pkgs.writeText "omanixy-core-declared-runtime-inputs.json" coreRuntime.passthru.declaredRuntimeInputs;
              corePolkitDeclaredRuntimeInputs = pkgs.writeText "omanixy-core-polkit-declared-runtime-inputs.json" corePolkitRuntime.passthru.declaredRuntimeInputs;
              coreExpectedChanged = pkgs.writeText "omanixy-core-expected-changed" (nixpkgs.lib.concatMapStringsSep "\n" toString [
                coreRuntime
                coreRuntime.passthru.omarchyCompatibilityRoot
                coreRuntime.passthru.compatibilityBin
                coreRuntime.passthru.ipc
                coreRuntime.passthru.compatAdapter
                coreRuntime.passthru.runtime
              ]);
              corePolkitExpectedChanged = pkgs.writeText "omanixy-core-polkit-expected-changed" (nixpkgs.lib.concatMapStringsSep "\n" toString [
                corePolkitRuntime
                corePolkitRuntime.passthru.omarchyCompatibilityRoot
                corePolkitRuntime.passthru.compatibilityBin
                corePolkitRuntime.passthru.ipc
                corePolkitRuntime.passthru.compatAdapter
                corePolkitRuntime.passthru.runtime
              ]);
              nativeBuildInputs = [ pkgs.bash pkgs.coreutils pkgs.gnugrep pkgs.findutils pkgs.diffutils pkgs.jq ];
            } ''
            ${pkgs.bash}/bin/bash ${./test/security-polkit-core-only.sh} \
              ${corePolkitRuntime.passthru.compatibilityBin} ${coreRuntime.passthru.compatibilityBin} \
              "$coreClosurePaths" "$corePolkitClosurePaths" \
              "$coreDeclaredRuntimeInputs" "$corePolkitDeclaredRuntimeInputs" \
              "$coreExpectedChanged" "$corePolkitExpectedChanged"
            touch "$out"
          '';
          security-polkit-closure = pkgs.runCommand "omanixy-security-polkit-closure"
            {
              polkitClosurePaths = "${polkitRuntimeClosureInfo}/store-paths";
              nativeBuildInputs = [ pkgs.bash pkgs.coreutils pkgs.gnugrep pkgs.findutils pkgs.diffutils ];
            } ''
            ${pkgs.bash}/bin/bash ${./test/security-polkit-closure.sh} \
              ${polkitRuntime} "$polkitClosurePaths" \
              ${polkitRuntime.passthru.compatibilityBin} ${runtime.passthru.compatibilityBin} \
              ${polkitRuntime.passthru.omarchyCompatibilityRoot}
            touch "$out"
          '';
          security-polkit-model = pkgs.runCommand "omanixy-security-polkit-model"
            {
              nativeBuildInputs = [ pkgs.bash pkgs.nodejs ];
            } ''
            ${pkgs.bash}/bin/bash ${./test/security-polkit-model.sh} \
              ${polkitRuntime.passthru.omarchyCompatibilityRoot}/shell/plugins/polkit/PolkitModel.js
            touch "$out"
          '';
          security-polkit-executable-surface = pkgs.runCommand "omanixy-security-polkit-executable-surface"
            {
              nativeBuildInputs = [ pkgs.bash pkgs.python3 ];
            } ''
            ${pkgs.bash}/bin/bash ${./test/security-polkit-executable-surface.sh} \
              ${./scripts/scan-polkit-executable-surface} \
              ${polkitRuntime.passthru.omarchyCompatibilityRoot}/shell/plugins/polkit/PolkitAgent.qml \
              ${pkgs.python3}/bin/python3 ${./scripts}
            touch "$out"
          '';
          security-polkit-quickshell-contract = pkgs.runCommand "omanixy-security-polkit-quickshell-contract"
            {
              nativeBuildInputs = [ pkgs.bash pkgs.coreutils pkgs.gnugrep pkgs.gawk ];
            } ''
            ${pkgs.bash}/bin/bash ${./test/security-polkit-quickshell-contract.sh} ${quickshell}
            touch "$out"
          '';
          security-polkit-no-fingerprint-widening = pkgs.runCommand "omanixy-security-polkit-no-fingerprint-widening"
            {
              systemOnlyFprintdEnable = if polkitSystemNixosConfiguration.config.services.fprintd.enable then "true" else "false";
              systemOnlyPolkit1FprintAuth = if polkitSystemNixosConfiguration.config.security.pam.services."polkit-1".fprintAuth then "true" else "false";
              combinedFprintdEnable = if pamFingerprintPolkitSystemNixosConfiguration.config.services.fprintd.enable then "true" else "false";
              fingerprintOnlyServiceFile = pamFingerprintServiceFile;
              combinedServiceFile = pamFingerprintPolkitSystemServiceFile;
              nativeBuildInputs = [ pkgs.bash pkgs.coreutils pkgs.diffutils pkgs.gnugrep ];
            } ''
            ${pkgs.bash}/bin/bash ${./test/security-polkit-no-fingerprint-widening.sh} \
              ${./.} "$systemOnlyFprintdEnable" "$systemOnlyPolkit1FprintAuth" \
              "$combinedFprintdEnable" "$fingerprintOnlyServiceFile" "$combinedServiceFile"
            touch "$out"
          '';
          security-polkit-qml-behavior = pkgs.runCommand "omanixy-security-polkit-qml-behavior"
            {
              nativeBuildInputs = [ pkgs.bash pkgs.python3 ];
            } ''
            PYTHON=${pkgs.python3}/bin/python3 ${pkgs.bash}/bin/bash ${./test/security-polkit-qml-behavior.sh} \
              ${polkitRuntime.passthru.omarchyCompatibilityRoot} ${polkitRuntime}/bin/quickshell
            touch "$out"
          '';
          security-idle-hm = pkgs.runCommand "omanixy-security-idle-hm"
            {
              allOffOk = if toplevelForced integratedIdleAllOffNixosConfiguration then "true" else "false";
              idleOnLockOffOk = if toplevelForced integratedIdleOnLockOffNixosConfiguration then "true" else "false";
              idleOnLockOnOk = if toplevelForced integratedIdleOnLockOnNixosConfiguration then "true" else "false";
              hypridleConflictOk = if toplevelForced integratedIdleOnHypridleConflictNixosConfiguration then "true" else "false";
              swayidleConflictOk = if toplevelForced integratedIdleOnSwayidleConflictNixosConfiguration then "true" else "false";
              bothConflictOk = if toplevelForced integratedIdleOnBothConflictNixosConfiguration then "true" else "false";
              idleOffBothDaemonsOnOk = if toplevelForced integratedIdleOffBothDaemonsOnNixosConfiguration then "true" else "false";
              idleOnFingerprintOnOk = if toplevelForced integratedIdleOnFingerprintOnNixosConfiguration then "true" else "false";
              idleOnPolkitOnOk = if toplevelForced integratedIdleOnPolkitOnNixosConfiguration then "true" else "false";
              idleOffLockOnOk = if toplevelForced integratedIdleOffLockOnNixosConfiguration then "true" else "false";
              nativeBuildInputs = [ pkgs.bash pkgs.coreutils ];
            } ''
            ${pkgs.bash}/bin/bash ${./test/security-idle-hm.sh} \
              "$allOffOk" "$idleOnLockOffOk" "$idleOnLockOnOk" \
              "$hypridleConflictOk" "$swayidleConflictOk" "$bothConflictOk" \
              "$idleOffBothDaemonsOnOk" "$idleOnFingerprintOnOk" "$idleOnPolkitOnOk" \
              "$idleOffLockOnOk"
            touch "$out"
          '';
          security-idle-shell-json = pkgs.runCommand "omanixy-security-idle-shell-json"
            {
              nativeBuildInputs = [ pkgs.bash pkgs.coreutils pkgs.diffutils pkgs.jq ];
            } ''
            ${pkgs.bash}/bin/bash ${./test/security-idle-shell-json.sh} \
              ${activationScript} ${idleEnabledActivationScript} ${storeConfig}
            touch "$out"
          '';
          security-idle-managed-plugin = pkgs.runCommand "omanixy-security-idle-managed-plugin"
            {
              nativeBuildInputs = [ pkgs.bash pkgs.coreutils pkgs.findutils ];
            } ''
            ${pkgs.bash}/bin/bash ${./test/security-idle-managed-plugin.sh} \
              ${idleRuntime.passthru.omarchyCompatibilityRoot} ${idleRuntime}/bin/quickshell \
              ${compatibilityRoot} ${runtime}/bin/quickshell
            touch "$out"
          '';
          security-idle-model = pkgs.runCommand "omanixy-security-idle-model"
            {
              nativeBuildInputs = [ pkgs.bash pkgs.nodejs ];
            } ''
            ${pkgs.bash}/bin/bash ${./test/security-idle-model.sh} \
              ${idleRuntime.passthru.omarchyCompatibilityRoot}/shell/plugins/services/idle/IdleModel.js
            touch "$out"
          '';
          security-idle-policy = pkgs.runCommand "omanixy-security-idle-policy"
            {
              nativeBuildInputs = [ pkgs.bash pkgs.nodejs ];
            } ''
            ${pkgs.bash}/bin/bash ${./test/security-idle-policy.sh} \
              ${idleRuntime.passthru.omarchyCompatibilityRoot}/shell/plugins/services/idle/IdlePolicy.js
            touch "$out"
          '';
          security-idle-state = pkgs.runCommand "omanixy-security-idle-state"
            {
              nativeBuildInputs = [ pkgs.bash pkgs.coreutils ];
            } ''
            ${pkgs.bash}/bin/bash ${./test/security-idle-state.sh} \
              ${./packages/omanixy-shell/adapters/idle.bash}
            touch "$out"
          '';
          security-idle-executable-surface = pkgs.runCommand "omanixy-security-idle-executable-surface"
            {
              nativeBuildInputs = [ pkgs.bash pkgs.python3 ];
            } ''
            ${pkgs.bash}/bin/bash ${./test/security-idle-executable-surface.sh} \
              ${./scripts/scan-idle-executable-surface} \
              ${idleRuntime.passthru.omarchyCompatibilityRoot}/shell/plugins/services/idle/Service.qml \
              ${pkgs.python3}/bin/python3 ${./scripts}
            touch "$out"
          '';
          security-idle-closure = pkgs.runCommand "omanixy-security-idle-closure"
            {
              lockClosurePaths = "${coreLockRuntimeClosureInfo}/store-paths";
              lockIdleClosurePaths = "${coreLockIdleRuntimeClosureInfo}/store-paths";
              lockDeclaredRuntimeInputs = pkgs.writeText "omanixy-lock-only-declared-runtime-inputs.json" coreLockRuntime.passthru.declaredRuntimeInputs;
              lockIdleDeclaredRuntimeInputs = pkgs.writeText "omanixy-lock-idle-declared-runtime-inputs.json" coreLockIdleRuntime.passthru.declaredRuntimeInputs;
              lockExpectedChanged = pkgs.writeText "omanixy-lock-only-expected-changed" (nixpkgs.lib.concatMapStringsSep "\n" toString [
                coreLockRuntime
                coreLockRuntime.passthru.omarchyCompatibilityRoot
                coreLockRuntime.passthru.compatibilityBin
                coreLockRuntime.passthru.ipc
                coreLockRuntime.passthru.compatAdapter
                coreLockRuntime.passthru.runtime
              ]);
              lockIdleExpectedChanged = pkgs.writeText "omanixy-lock-idle-expected-changed" (nixpkgs.lib.concatMapStringsSep "\n" toString [
                coreLockIdleRuntime
                coreLockIdleRuntime.passthru.omarchyCompatibilityRoot
                coreLockIdleRuntime.passthru.compatibilityBin
                coreLockIdleRuntime.passthru.ipc
                coreLockIdleRuntime.passthru.compatAdapter
                coreLockIdleRuntime.passthru.runtime
              ]);
              nativeBuildInputs = [ pkgs.bash pkgs.coreutils pkgs.gnugrep pkgs.findutils pkgs.diffutils pkgs.jq ];
            } ''
            ${pkgs.bash}/bin/bash ${./test/security-idle-closure.sh} \
              ${coreLockIdleRuntime.passthru.compatibilityBin} ${coreLockRuntime.passthru.compatibilityBin} \
              "$lockClosurePaths" "$lockIdleClosurePaths" \
              "$lockDeclaredRuntimeInputs" "$lockIdleDeclaredRuntimeInputs" \
              "$lockExpectedChanged" "$lockIdleExpectedChanged"
            touch "$out"
          '';
          security-idle-no-dpms-widening = pkgs.runCommand "omanixy-security-idle-no-dpms-widening"
            {
              nativeBuildInputs = [ pkgs.bash pkgs.diffutils ];
            } ''
            ${pkgs.bash}/bin/bash ${./test/security-idle-no-dpms-widening.sh} \
              ${coreLockRuntime.passthru.omarchyCompatibilityRoot}/shell/plugins/lock/Service.qml \
              ${coreLockIdleRuntime.passthru.omarchyCompatibilityRoot}/shell/plugins/lock/Service.qml
            touch "$out"
          '';
          security-idle-package-invariant = pkgs.runCommand "omanixy-security-idle-package-invariant"
            {
              idleWithoutLockOk = if packageIdleWithoutLockEval.success then "true" else "false";
              idleWithLockOk = if packageIdleWithLockEval.success then "true" else "false";
              nativeBuildInputs = [ pkgs.bash pkgs.coreutils ];
            } ''
            ${pkgs.bash}/bin/bash ${./test/security-idle-package-invariant.sh} \
              "$idleWithoutLockOk" "$idleWithLockOk"
            touch "$out"
          '';
          security-idle-quickshell-contract = pkgs.runCommand "omanixy-security-idle-quickshell-contract"
            {
              nativeBuildInputs = [ pkgs.bash pkgs.coreutils pkgs.gnugrep pkgs.gawk ];
            } ''
            ${pkgs.bash}/bin/bash ${./test/security-idle-quickshell-contract.sh} ${quickshell}
            touch "$out"
          '';
          security-idle-qml-behavior = pkgs.runCommand "omanixy-security-idle-qml-behavior"
            {
              nativeBuildInputs = [ pkgs.bash pkgs.python3 ];
            } ''
            PYTHON=${pkgs.python3}/bin/python3 ${pkgs.bash}/bin/bash ${./test/security-idle-qml-behavior.sh} \
              ${idleRuntime.passthru.omarchyCompatibilityRoot} ${idleRuntime}/bin/quickshell
            touch "$out"
          '';
          security-notifications-hm = pkgs.runCommand "omanixy-security-notifications-hm"
            {
              daemonOffOk = if standaloneLockDisabledEval.success then "true" else "false";
              daemonOnOk = if standaloneNotificationDaemonEnabledEval.success then "true" else "false";
              makoConflictOk = if standaloneNotificationDaemonMakoConflictEval.success then "true" else "false";
              dunstConflictOk = if standaloneNotificationDaemonDunstConflictEval.success then "true" else "false";
              swayncConflictOk = if standaloneNotificationDaemonSwayncConflictEval.success then "true" else "false";
              fnottConflictOk = if standaloneNotificationDaemonFnottConflictEval.success then "true" else "false";
              offAllConflictsOnOk = if standaloneNotificationDaemonOffAllConflictsOnEval.success then "true" else "false";
              withClientFeatureOk = if standaloneNotificationDaemonWithClientFeatureEval.success then "true" else "false";
              nativeBuildInputs = [ pkgs.bash pkgs.coreutils ];
            } ''
            ${pkgs.bash}/bin/bash ${./test/security-notifications-hm.sh} \
              "$daemonOffOk" "$daemonOnOk" \
              "$makoConflictOk" "$dunstConflictOk" "$swayncConflictOk" "$fnottConflictOk" \
              "$offAllConflictsOnOk" "$withClientFeatureOk"
            touch "$out"
          '';
          security-notifications-shell-json = pkgs.runCommand "omanixy-security-notifications-shell-json"
            {
              nativeBuildInputs = [ pkgs.bash pkgs.coreutils pkgs.diffutils pkgs.jq ];
            } ''
            ${pkgs.bash}/bin/bash ${./test/security-notifications-shell-json.sh} \
              ${activationScript} ${notificationDaemonEnabledActivationScript} ${storeConfig}
            touch "$out"
          '';
          security-notifications-managed-plugin = pkgs.runCommand "omanixy-security-notifications-managed-plugin"
            {
              nativeBuildInputs = [ pkgs.bash pkgs.coreutils pkgs.findutils ];
            } ''
            ${pkgs.bash}/bin/bash ${./test/security-notifications-managed-plugin.sh} \
              ${notificationDaemonRuntime.passthru.omarchyCompatibilityRoot} ${notificationDaemonRuntime}/bin/quickshell \
              ${compatibilityRoot} ${runtime}/bin/quickshell
            touch "$out"
          '';
          security-notifications-logic = pkgs.runCommand "omanixy-security-notifications-logic"
            {
              nativeBuildInputs = [ pkgs.bash pkgs.nodejs ];
            } ''
            ${pkgs.bash}/bin/bash ${./test/security-notifications-logic.sh} \
              ${notificationDaemonRuntime.passthru.omarchyCompatibilityRoot}/shell/plugins/notifications/NotificationLogic.js
            touch "$out"
          '';
          security-notifications-state = pkgs.runCommand "omanixy-security-notifications-state"
            {
              nativeBuildInputs = [ pkgs.bash pkgs.coreutils pkgs.util-linux ];
            } ''
            ${pkgs.bash}/bin/bash ${./test/security-notifications-state.sh} \
              ${./packages/omanixy-shell/adapters/notification-state.bash}
            touch "$out"
          '';
          security-notifications-executable-surface = pkgs.runCommand "omanixy-security-notifications-executable-surface"
            {
              nativeBuildInputs = [ pkgs.bash pkgs.python3 ];
            } ''
            ${pkgs.bash}/bin/bash ${./test/security-notifications-executable-surface.sh} \
              ${./scripts/scan-notification-executable-surface} \
              ${notificationDaemonRuntime.passthru.omarchyCompatibilityRoot}/shell/plugins/notifications/Service.qml \
              ${pkgs.python3}/bin/python3 ${./scripts}
            touch "$out"
          '';
          security-notifications-closure = pkgs.runCommand "omanixy-security-notifications-closure"
            {
              coreClosurePaths = "${coreRuntimeClosureInfo}/store-paths";
              coreNotificationDaemonClosurePaths = "${coreNotificationDaemonRuntimeClosureInfo}/store-paths";
              coreDeclaredRuntimeInputs = pkgs.writeText "omanixy-core-declared-runtime-inputs-for-notifications.json" coreRuntime.passthru.declaredRuntimeInputs;
              coreNotificationDaemonDeclaredRuntimeInputs = pkgs.writeText "omanixy-core-notification-daemon-declared-runtime-inputs.json" coreNotificationDaemonRuntime.passthru.declaredRuntimeInputs;
              coreExpectedChanged = pkgs.writeText "omanixy-core-expected-changed-for-notifications" (nixpkgs.lib.concatMapStringsSep "\n" toString [
                coreRuntime
                coreRuntime.passthru.omarchyCompatibilityRoot
                coreRuntime.passthru.compatibilityBin
                coreRuntime.passthru.ipc
                coreRuntime.passthru.compatAdapter
                coreRuntime.passthru.runtime
              ]);
              coreNotificationDaemonExpectedChanged = pkgs.writeText "omanixy-core-notification-daemon-expected-changed" (nixpkgs.lib.concatMapStringsSep "\n" toString [
                coreNotificationDaemonRuntime
                coreNotificationDaemonRuntime.passthru.omarchyCompatibilityRoot
                coreNotificationDaemonRuntime.passthru.compatibilityBin
                coreNotificationDaemonRuntime.passthru.ipc
                coreNotificationDaemonRuntime.passthru.compatAdapter
                coreNotificationDaemonRuntime.passthru.runtime
              ]);
              nativeBuildInputs = [ pkgs.bash pkgs.coreutils pkgs.gnugrep pkgs.findutils pkgs.diffutils pkgs.jq ];
            } ''
            ${pkgs.bash}/bin/bash ${./test/security-notifications-closure.sh} \
              ${coreRuntime.passthru.compatibilityBin} ${coreNotificationDaemonRuntime.passthru.compatibilityBin} \
              "$coreClosurePaths" "$coreNotificationDaemonClosurePaths" \
              "$coreDeclaredRuntimeInputs" "$coreNotificationDaemonDeclaredRuntimeInputs" \
              "$coreExpectedChanged" "$coreNotificationDaemonExpectedChanged"
            touch "$out"
          '';
          security-notifications-client-independence = pkgs.runCommand "omanixy-security-notifications-client-independence"
            {
              nativeBuildInputs = [ pkgs.bash pkgs.coreutils ];
            } ''
            ${pkgs.bash}/bin/bash ${./test/security-notifications-client-independence.sh} \
              ${coreRuntime.passthru.omarchyCompatibilityRoot} \
              ${coreNotificationDaemonRuntime.passthru.compatibilityBin} \
              ${notificationRuntime.passthru.omarchyCompatibilityRoot} ${notificationRuntime.passthru.compatibilityBin} \
              ${notificationClientAndDaemonRuntime.passthru.omarchyCompatibilityRoot} ${notificationClientAndDaemonRuntime.passthru.compatibilityBin}
            touch "$out"
          '';
          security-notifications-lower-layer-independence = pkgs.runCommand "omanixy-security-notifications-lower-layer-independence"
            {
              nativeBuildInputs = [ pkgs.bash pkgs.coreutils pkgs.diffutils ];
            } ''
            ${pkgs.bash}/bin/bash ${./test/security-notifications-lower-layer-independence.sh} \
              ${allSecurityWithNotificationDaemonRuntime.passthru.omarchyCompatibilityRoot}/shell/plugins/lock/Service.qml \
              ${allSecurityWithNotificationDaemonRuntime.passthru.omarchyCompatibilityRoot}/shell/plugins/lock/FingerprintPolicy.js \
              ${allSecurityWithNotificationDaemonRuntime.passthru.omarchyCompatibilityRoot}/shell/plugins/polkit/PolkitAgent.qml \
              ${allSecurityWithNotificationDaemonRuntime.passthru.omarchyCompatibilityRoot}/shell/plugins/services/idle/IdleModel.js \
              ${allSecurityWithoutNotificationDaemonRuntime.passthru.omarchyCompatibilityRoot}/shell/plugins/lock/Service.qml \
              ${allSecurityWithoutNotificationDaemonRuntime.passthru.omarchyCompatibilityRoot}/shell/plugins/lock/FingerprintPolicy.js \
              ${allSecurityWithoutNotificationDaemonRuntime.passthru.omarchyCompatibilityRoot}/shell/plugins/polkit/PolkitAgent.qml \
              ${allSecurityWithoutNotificationDaemonRuntime.passthru.omarchyCompatibilityRoot}/shell/plugins/services/idle/IdleModel.js
            touch "$out"
          '';
          security-notifications-quickshell-contract = pkgs.runCommand "omanixy-security-notifications-quickshell-contract"
            {
              nativeBuildInputs = [ pkgs.bash pkgs.coreutils pkgs.gnugrep pkgs.gawk ];
            } ''
            ${pkgs.bash}/bin/bash ${./test/security-notifications-quickshell-contract.sh} ${quickshell}
            touch "$out"
          '';
          security-notifications-qml-behavior = pkgs.runCommand "omanixy-security-notifications-qml-behavior"
            {
              nativeBuildInputs = [ pkgs.bash pkgs.python3 ];
            } ''
            PYTHON=${pkgs.python3}/bin/python3 ${pkgs.bash}/bin/bash ${./test/security-notifications-qml-behavior.sh} \
              ${notificationDaemonRuntime.passthru.omarchyCompatibilityRoot} ${notificationDaemonRuntime}/bin/quickshell \
              ${./packages/omanixy-shell/adapters/notification-state.bash}
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
          security-recovery-contract = pkgs.runCommand "omanixy-security-recovery-contract"
            {
              nativeBuildInputs = [ pkgs.bash (pkgs.python3.withPackages (ps: [ ps.pyyaml ])) ];
            } ''
            PYTHON=${pkgs.python3.withPackages (ps: [ ps.pyyaml ])}/bin/python ${pkgs.bash}/bin/bash ${./test/security-recovery-contract.sh} ${./.}
            touch "$out"
          '';
          security-recovery-measurement = pkgs.runCommand "omanixy-security-recovery-measurement"
            {
              nativeBuildInputs = [ pkgs.bash pkgs.gnugrep pkgs.python3 ];
            } ''
            ${pkgs.bash}/bin/bash ${./test/security-recovery-measurement.sh} \
              ${./.} \
              ${./justfile}
            touch "$out"
          '';
          security-recovery-check-helpers-selftest = pkgs.runCommand "omanixy-security-recovery-check-helpers-selftest"
            {
              nativeBuildInputs = [ pkgs.python3 ];
            } ''
            python3 ${./test/lib/recovery-check-helpers-selftest.py} ${./test/lib/recovery-check-helpers.py}
            touch "$out"
          '';
          source-comment-policy-selftest = pkgs.runCommand "omanixy-source-comment-policy-selftest"
            {
              nativeBuildInputs = [ pkgs.python3 ];
            } ''
            python3 ${./test/lib/source-comment-policy-selftest.py} ${./scripts/check-source-comments}
            touch "$out"
          '';
          release-contract = pkgs.runCommand "omanixy-release-contract"
            {
              nativeBuildInputs = [ releasePython ];
            } ''
            ${releasePython}/bin/python ${./test/release-contract.py} ${self}
            touch "$out"
          '';
          release-context-selftest = pkgs.runCommand "omanixy-release-context-selftest"
            {
              nativeBuildInputs = [ releasePython ];
            } ''
            ${releasePython}/bin/python ${./test/lib/release-context-selftest.py} ${./scripts/release-context}
            touch "$out"
          '';
          actionlint = pkgs.runCommand "omanixy-actionlint"
            {
              nativeBuildInputs = [ pkgs.actionlint ];
            } ''
            actionlint ${./.github/workflows/ci.yaml} ${./.github/workflows/release-please.yaml}
            touch "$out"
          '';
          source-comment-policy = pkgs.runCommand "omanixy-source-comment-policy"
            {
              nativeBuildInputs = [ pkgs.python3 ];
            } ''
            python3 ${self}/scripts/check-source-comments ${self}
            touch "$out"
          '';
          security-recovery-contract-helpers-selftest = pkgs.runCommand "omanixy-security-recovery-contract-helpers-selftest"
            {
              nativeBuildInputs = [ pkgs.python3 ];
            } ''
            python3 ${./test/lib/recovery-contract-helpers-selftest.py} ${./test/lib/recovery-contract-helpers.py}
            touch "$out"
          '';
          security-issue-4-acceptance = pkgs.runCommand "omanixy-security-issue-4-acceptance"
            {
              nativeBuildInputs = [ pkgs.bash (pkgs.python3.withPackages (ps: [ ps.pyyaml ])) ];
            } ''
            PYTHON=${pkgs.python3.withPackages (ps: [ ps.pyyaml ])}/bin/python ${pkgs.bash}/bin/bash ${./test/security-issue-4-acceptance.sh} ${./.}
            touch "$out"
          '';
          security-recovery-pam-vm = import ./test/security-recovery-pam-vm.nix { inherit pkgs self home-manager; };
          security-recovery-polkit-vm = import ./test/security-recovery-polkit-vm.nix { inherit pkgs self home-manager; };
          security-recovery-notifications-vm = import ./test/security-recovery-notifications-vm.nix { inherit pkgs self home-manager; };
          security-recovery-cross-feature-vm = import ./test/security-recovery-cross-feature-vm.nix { inherit pkgs self home-manager; };
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
            PYTHON=${pkgs.python3}/bin/python3 ${pkgs.bash}/bin/bash ${./test/qml-patch-behavior.sh} ${compatibilityRoot} ${runtime.passthru.omarchySource} ${./scripts/patch-transparent-foreground-process} ${runtime}/bin/quickshell ${./scripts/patch-menu-power-provider} ${./scripts/patch-menu-font-provider} ${./scripts/patch-menu-terminal-provider} ${./scripts/patch-background}
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
