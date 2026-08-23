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
      integratedHome = integratedNixos.config.home-manager.users.${username};
      integratedService = integratedHome.systemd.user.services.omanixy-shell;
      invalidLockDiagnostics = map
        (assertion: assertion.message)
        (builtins.filter (assertion: !assertion.assertion) invalidStandaloneLock.config.assertions);
      invalidLockDiagnosticOk = lib.any
        (message:
          lib.hasInfix "standalone" message
          && lib.hasInfix "programs.omanixy.security.pam.password" message)
        invalidLockDiagnostics;
      serviceContractOk =
        lib.hasSuffix "/bin/omanixy-shell-runtime" standaloneService.Service.ExecStart
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
        && lib.hasSuffix "/bin/omanixy-shell-runtime" integratedService.Service.ExecStart;
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
            activationStorePaths = "${standaloneActivationClosure}/store-paths";
            serviceContract = if serviceContractOk then "true" else "false";
            safeOwnership = if safeOwnershipOk then "true" else "false";
            overrideContract = if overrideContractOk then "true" else "false";
            hostCapabilities = if hostCapabilitiesOk then "true" else "false";
            integratedContract = if integratedContractOk then "true" else "false";
            invalidLockDiagnostic = if invalidLockDiagnosticOk then "true" else "false";
            nativeBuildInputs = [ pkgs.coreutils pkgs.gnugrep ];
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
          if grep -Fq 'universe' "$activationStorePaths"; then
            exit 1
          fi
          if grep -R -n -E '/home/atqa|sfx14|pavg15|~/dotfiles|atqamz/universe|Hand|private paths' ${./.}; then
            exit 1
          fi
          grep -Fq '## What Omanixy is' ${omanixy.outPath}/README.md
          grep -Fq '## Prerequisites and session assumptions' ${omanixy.outPath}/README.md
          grep -Fq '## Install with flakes' ${omanixy.outPath}/README.md
          grep -Fq '## Feature and support matrix' ${omanixy.outPath}/README.md
          grep -Fq '## Troubleshooting' ${omanixy.outPath}/README.md
          grep -Fq '## Upgrades and releases' ${omanixy.outPath}/README.md
          touch "$out"
        '';
      };
    };
}
