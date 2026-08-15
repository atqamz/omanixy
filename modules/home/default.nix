{ config
, lib
, omanixyRuntime
, pkgs
, ...
}:

let
  cfg = config.programs.omanixy;
  runtime = omanixyRuntime;
  coreutils = "${pkgs.coreutils}/bin";
  safetyDisabledPlugins = [
    "omarchy.background"
    "omarchy.battery"
    "omarchy.clipboard"
    "omarchy.idle"
    "omarchy.lock"
    "omarchy.media"
    "omarchy.nightlight"
    "omarchy.notifications"
    "omarchy.polkit"
  ];
  baselineConfig = {
    version = 1;
    bar = {
      position = "top";
      transparent = false;
      centerAnchor = "omarchy.clock";
      layout = {
        left = [
          { id = "omarchy.menu"; }
          { id = "omarchy.workspaces"; }
        ];
        center = [
          {
            id = "omarchy.clock";
            format = "dddd HH:mm";
          }
        ];
        right = [ ];
      };
    };
    disabledPlugins = safetyDisabledPlugins;
  };
  configuredDisabledPlugins = cfg.shell.config.disabledPlugins or [ ];
  effectiveConfig = cfg.shell.config // {
    disabledPlugins = lib.unique (safetyDisabledPlugins ++ configuredDisabledPlugins);
  };
  configJson = builtins.toJSON effectiveConfig;
  configSeed = pkgs.writeText "omanixy-shell-config" configJson;
  safetyDisabledPluginsJson = builtins.toJSON safetyDisabledPlugins;
  migrateStoreConfig = pkgs.writeShellScript "omanixy-migrate-store-shell-config" ''
    set -euo pipefail
    source=$1
    destination=$2
    cleanup() {
      ${coreutils}/rm -f -- "$destination"
    }
    trap cleanup EXIT
    ${pkgs.jq}/bin/jq \
      --argjson safetyDisabledPlugins '${safetyDisabledPluginsJson}' \
      '
        if .disabledPlugins == null then
          .disabledPlugins = $safetyDisabledPlugins
        elif (.disabledPlugins | type) == "array" then
          .disabledPlugins = (
            reduce $safetyDisabledPlugins[] as $plugin (
              .disabledPlugins;
              if index($plugin) == null then . + [$plugin] else . end
            )
          )
        else
          error("disabledPlugins must be a JSON array")
        end
      ' "$source" > "$destination"
    trap - EXIT
  '';
  runtimeTheme = runtime.passthru.theme;
in
{
  options.programs.omanixy = {
    enable = lib.mkEnableOption "the Omanixy Quattro shell";

    shell.config = lib.mkOption {
      type = lib.types.attrsOf lib.types.json;
      default = baselineConfig;
      defaultText = lib.literalExpression "<safe Quattro baseline>";
      description = ''
        Whole-file upstream-compatible Quattro shell.json configuration.
        Omanixy always adds its safety floor to disabledPlugins, so this option
        cannot enable unfinished lock, polkit, idle, notification, or related
        surfaces owned by issue #4.
        The file is seeded on first activation and remains user-owned after
        that; it is not deep-merged or overwritten by later activations.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = (cfg.shell.config.version or null) == 1;
        message = "programs.omanixy.shell.config.version must be 1";
      }
      {
        assertion = builtins.isList configuredDisabledPlugins
          && builtins.all builtins.isString configuredDisabledPlugins;
        message = "programs.omanixy.shell.config.disabledPlugins must be a list of strings";
      }
    ];

    home.packages = [ runtime ];

    home.activation.omanixyShellState = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      config_dir="$HOME/.config/omarchy"
      config_file="$config_dir/shell.json"
      theme_dir="$HOME/.local/state/omarchy/current/theme"

      run ${coreutils}/mkdir -p "$config_dir" "$config_dir/plugins"

      if [ -L "$config_file" ]; then
        config_target=$(${coreutils}/readlink -f "$config_file" || true)
        case "$config_target" in
          /nix/store/*)
            if [ -f "$config_target" ]; then
              config_tmp="$config_file.omanixy.$$"
              (
                config_tmp_cleanup() {
                  run ${coreutils}/rm -f -- "$config_tmp"
                }
                trap config_tmp_cleanup EXIT
                run ${migrateStoreConfig} "$config_target" "$config_tmp" || exit $?
                run ${coreutils}/chmod u+rw -- "$config_tmp" || exit $?
                run ${coreutils}/mv -f -- "$config_tmp" "$config_file" || exit $?
              ) || exit $?
            else
              run ${coreutils}/rm -f -- "$config_file"
            fi
            ;;
          *)
            if [ ! -e "$config_file" ]; then
              run ${coreutils}/rm -f -- "$config_file"
            fi
            ;;
        esac
      fi

      if [ ! -e "$config_file" ]; then
        run ${coreutils}/install -Dm600 -- '${configSeed}' "$config_file"
      fi

      if [ -L "$theme_dir" ]; then
        theme_target=$(${coreutils}/readlink -f "$theme_dir" || true)
        case "$theme_target" in
          /nix/store/*)
            if [ -d "$theme_target" ]; then
              theme_tmp="$theme_dir.omanixy.$$"
              run ${coreutils}/mkdir -p "$theme_tmp"
              run ${coreutils}/cp -R -- "$theme_target/." "$theme_tmp/"
              run ${coreutils}/chmod -R u+rwX -- "$theme_tmp"
              run ${coreutils}/rm -f -- "$theme_dir"
              run ${coreutils}/mv -- "$theme_tmp" "$theme_dir"
            else
              run ${coreutils}/rm -f -- "$theme_dir"
            fi
            ;;
          *)
            if [ ! -e "$theme_dir" ]; then
              run ${coreutils}/rm -f -- "$theme_dir"
            fi
            ;;
        esac
      fi

      if [ ! -e "$theme_dir" ]; then
        run ${coreutils}/mkdir -p "$theme_dir"
        run ${coreutils}/cp -R -- '${runtimeTheme}/.' "$theme_dir/"
        run ${coreutils}/chmod -R u+rwX -- "$theme_dir"
      fi
    '';

    systemd.user.services.omanixy-shell = {
      Unit = {
        Description = lib.mkDefault "Omanixy Quattro shell";
        Documentation = lib.mkDefault [ "https://github.com/atqamz/omanixy" ];
        PartOf = lib.mkDefault [ "graphical-session.target" ];
        After = lib.mkDefault [ "graphical-session.target" ];
        StartLimitIntervalSec = lib.mkDefault "60s";
        StartLimitBurst = lib.mkDefault 5;
      };
      Service = {
        ExecStart = lib.mkDefault "${runtime}/bin/omanixy-shell-runtime";
        Restart = lib.mkDefault "on-failure";
        RestartSec = lib.mkDefault "2s";
        TimeoutStopSec = lib.mkDefault "10s";
        Environment = lib.mkDefault [
          "OMARCHY_PATH=${runtime.passthru.omarchySource}"
          "QS_DISABLE_FILE_WATCHER=1"
          "QS_NO_RELOAD_POPUP=1"
        ];
      };
      Install = {
        WantedBy = lib.mkDefault [ "graphical-session.target" ];
      };
    };
  };
}
