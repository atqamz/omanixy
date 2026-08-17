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
  featurePluginIds = lib.unique (lib.concatLists (builtins.attrValues featurePlugins));
  selectedFeatures = featureSelection.select cfg.features;
  configuredDisabledPlugins = cfg.shell.config.disabledPlugins or [ ];
  omittedFeaturePlugins = lib.concatLists (map
    (feature: featurePlugins.${feature} or [ ])
    (lib.filter (feature: !builtins.elem feature selectedFeatures) (builtins.attrNames featurePlugins)));
  runtimeBlockedPlugins = lib.unique (baselineConfig.disabledPlugins ++ omittedFeaturePlugins);
  effectiveConfig = cfg.shell.config // {
    disabledPlugins = lib.unique (baselineConfig.disabledPlugins ++ configuredDisabledPlugins);
  };
  configJson = builtins.toJSON effectiveConfig;
  configSeed = pkgs.writeText "omanixy-shell-config" configJson;
  baselineDisabledPluginsJson = builtins.toJSON baselineConfig.disabledPlugins;
  featurePluginIdsJson = builtins.toJSON featurePluginIds;
  legacyBaselineJson = builtins.toJSON historicalBaseline;
  capabilityState = pkgs.writeText "omanixy-capability-state" (builtins.toJSON {
    schema = 1;
    owner = "omanixy";
    selectedFeatures = selectedFeatures;
    baselineDisabledPlugins = baselineConfig.disabledPlugins;
    runtimeBlockedPlugins = runtimeBlockedPlugins;
  });
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
      --argjson baselineDisabledPlugins '${baselineDisabledPluginsJson}' \
      --argjson featurePluginIds '${featurePluginIdsJson}' \
      '
        if . == $legacy then
          $current
        elif .disabledPlugins == null then
          .disabledPlugins = $baselineDisabledPlugins
        elif (.disabledPlugins | type) == "array" then
          .disabledPlugins = (
            .disabledPlugins
            | map(select(($featurePluginIds | index(.)) == null))
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
        Omanixy preserves the baseline disabled-plugin floor and explicit
        user preferences in the generated file.
        The immutable compatibility-root registry separately enforces the
        selected feature capability floor, so changing features cannot revive
        omitted runtime support or make unfinished issue #4 security surfaces
        reachable.
        The file is seeded on first activation and remains user-owned after
        that; only an exact known Omanixy-generated baseline is migrated to the
        current baseline, while customized or malformed files remain untouched.
        Omanixy-owned capability metadata is stored separately under
        .local/state/omanixy and is not shell configuration.
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
      capability_dir="$HOME/.local/state/omanixy"
      capability_file="$capability_dir/capabilities.json"
      theme_dir="$HOME/.local/state/omarchy/current/theme"

      run ${coreutils}/mkdir -p "$config_dir" "$config_dir/plugins"
      run ${coreutils}/mkdir -p "$capability_dir"

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

      if [ ! -L "$capability_file" ] && { [ ! -e "$capability_file" ] || ${pkgs.jq}/bin/jq -e '.owner == "omanixy" and .schema == 1' "$capability_file" >/dev/null 2>&1; }; then
        run ${coreutils}/install -Dm600 -- '${capabilityState}' "$capability_file"
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
