{ config
, lib
, omanixyRuntimeFor
, pkgs
, ...
}:

let
  cfg = config.programs.omanixy;
  runtime = omanixyRuntimeFor cfg.features;
  coreutils = "${pkgs.coreutils}/bin";
  baselineSource = builtins.fromJSON (builtins.readFile ../../upstream/shell-baseline.json);
  featureSelection = import ../../lib/feature-selection.nix { inherit lib; baseline = baselineSource; };
  historicalBaseline = builtins.fromJSON (builtins.readFile ../../upstream/shell-baseline-v1.json);
  baselineConfig = builtins.removeAttrs baselineSource [ "featurePlugins" "featureDependencies" "featureOrder" "migrations" ];
  featurePlugins = baselineSource.featurePlugins;
  selectedFeatures = featureSelection.select cfg.features;
  disabledFeaturePlugins = lib.concatLists (map
    (feature: featurePlugins.${feature} or [ ])
    (lib.filter (feature: !builtins.elem feature selectedFeatures) (builtins.attrNames featurePlugins)));
  disabledPluginsFloor = lib.unique (baselineConfig.disabledPlugins ++ disabledFeaturePlugins);
  configuredDisabledPlugins = cfg.shell.config.disabledPlugins or [ ];
  effectiveConfig = cfg.shell.config // {
    disabledPlugins = lib.unique (disabledPluginsFloor ++ configuredDisabledPlugins);
  };
  configJson = builtins.toJSON effectiveConfig;
  configSeed = pkgs.writeText "omanixy-shell-config" configJson;
  disabledPluginsFloorJson = builtins.toJSON disabledPluginsFloor;
  legacyBaselineJson = builtins.toJSON historicalBaseline;
  migrateGeneratedConfig = pkgs.writeShellScript "omanixy-migrate-generated-shell-config" ''
    set -euo pipefail
    file=$1
    temporary=$2
    ${pkgs.jq}/bin/jq \
      --argjson legacy '${legacyBaselineJson}' \
      --argjson current '${builtins.toJSON baselineConfig}' \
      'if . == $legacy then $current else empty end' "$file" > "$temporary"
  '';
  migrateStoreConfig = pkgs.writeShellScript "omanixy-migrate-store-shell-config" ''
    set -euo pipefail
    source=$1
    destination=$2
    cleanup() {
      ${coreutils}/rm -f -- "$destination"
    }
    trap cleanup EXIT
    ${pkgs.jq}/bin/jq \
      --argjson legacy '${legacyBaselineJson}' \
      --argjson current '${builtins.toJSON baselineConfig}' \
      --argjson disabledPluginsFloor '${disabledPluginsFloorJson}' \
      '
        if . == $legacy then
          $current
        elif .disabledPlugins == null then
          .disabledPlugins = $disabledPluginsFloor
        elif (.disabledPlugins | type) == "array" then
          .disabledPlugins = (
            reduce $disabledPluginsFloor[] as $plugin (
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

    features = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "audio" "bluetooth" "clipboard" "launcher" "monitor" "network" "notification" "power" "screenshot" "weather" ];
      description = "Optional Omanixy compatibility feature groups whose runtime dependencies and helpers are included; Bluetooth also enables the audio group required by its default-device action.";
    };

    shell.config = lib.mkOption {
      type = lib.types.attrsOf lib.types.json;
      default = baselineConfig;
      defaultText = lib.literalExpression "<safe Quattro baseline>";
      description = ''
        Whole-file upstream-compatible Quattro shell.json configuration.
        Omanixy includes its disabled-plugin floor in generated config and the
        compatibility-root registry enforces it at runtime, so this option
        cannot enable unfinished issue #4 security surfaces or unsupported
        first-party Quattro plugins.
        The file is seeded on first activation and remains user-owned after
        that; only an exact known Omanixy-generated baseline is migrated to the
        current baseline, while customized or malformed files remain untouched.
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
                run ${coreutils}/chmod 600 -- "$config_tmp" || exit $?
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

      if [ -f "$config_file" ] && [ ! -L "$config_file" ]; then
        config_tmp="$config_file.omanixy.$$"
        if run ${migrateGeneratedConfig} "$config_file" "$config_tmp" && [ -s "$config_tmp" ]; then
          run ${coreutils}/chmod 600 -- "$config_tmp"
          run ${coreutils}/mv -f -- "$config_tmp" "$config_file"
        else
          run ${coreutils}/rm -f -- "$config_tmp"
        fi
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
          "OMARCHY_PATH=${runtime.passthru.omarchyCompatibilityRoot}"
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
