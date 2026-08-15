{ config
, lib
, omanixyRuntime
, ...
}:

let
  cfg = config.programs.omanixy;
  runtime = omanixyRuntime;
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
    disabledPlugins = [
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
  };
  configJson = builtins.toJSON cfg.shell.config;
  runtimeTheme = runtime.passthru.theme;
in
{
  options.programs.omanixy = {
    enable = lib.mkEnableOption "the Omanixy Quattro shell";

    shell.config = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      default = baselineConfig;
      defaultText = lib.literalExpression "<safe Quattro baseline>";
      description = ''
        Whole-file upstream-compatible Quattro shell.json configuration.
        The file is seeded on first activation and remains user-owned after
        that; it is not deep-merged or overwritten by later activations.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ runtime ];

    home.activation.omanixyShellState = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      config_dir="$HOME/.config/omarchy"
      config_file="$config_dir/shell.json"
      theme_dir="$HOME/.local/state/omarchy/current/theme"

      mkdir -p "$config_dir" "$config_dir/plugins"

      if [ -L "$config_file" ]; then
        config_target=$(readlink -f "$config_file" || true)
        case "$config_target" in
          /nix/store/*)
            config_tmp="$config_file.omanixy.$$"
            cp -- "$config_target" "$config_tmp"
            chmod u+rw -- "$config_tmp"
            mv -f -- "$config_tmp" "$config_file"
            ;;
        esac
      fi

      if [ ! -e "$config_file" ]; then
        (
          umask 077
          printf '%s\n' ${lib.escapeShellArg configJson} > "$config_file"
        )
      fi

      if [ -L "$theme_dir" ]; then
        theme_target=$(readlink -f "$theme_dir" || true)
        case "$theme_target" in
          /nix/store/*)
            theme_tmp="$theme_dir.omanixy.$$"
            mkdir -p "$theme_tmp"
            cp -R -- "$theme_target/." "$theme_tmp/"
            chmod -R u+rwX -- "$theme_tmp"
            rm -f -- "$theme_dir"
            mv -- "$theme_tmp" "$theme_dir"
            ;;
        esac
      elif [ ! -e "$theme_dir" ]; then
        mkdir -p "$theme_dir"
        cp -R -- '${runtimeTheme}/.' "$theme_dir/"
        chmod -R u+rwX -- "$theme_dir"
      fi
    '';

    systemd.user.services.omanixy-shell = {
      Unit = {
        Description = lib.mkDefault "Omanixy Quattro shell";
        Documentation = lib.mkDefault [ "https://github.com/atqamz/omanixy" ];
        PartOf = lib.mkDefault [ "graphical-session.target" ];
        After = lib.mkDefault [ "graphical-session-pre.target" ];
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
