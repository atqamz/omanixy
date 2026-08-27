{ config
, lib
, omanixyRuntimeFor
, pkgs
, osConfig ? null
, ...
}:

let
  cfg = config.programs.omanixy;
  fingerprintPackage =
    if cfg.security.lock.enable && cfg.security.lock.fingerprint.enable && osConfig != null
    then osConfig.services.fprintd.package
    else null;
  securitySelection =
    (lib.optionalAttrs cfg.security.lock.enable {
      lock = true;
      fingerprint = cfg.security.lock.fingerprint.enable;
      fingerprintPackage = fingerprintPackage;
    })
    // (lib.optionalAttrs cfg.security.polkit.agent.enable {
      polkitAgent = true;
    })
    // (lib.optionalAttrs cfg.security.idle.enable {
      idle = true;
    })
    // (lib.optionalAttrs cfg.security.notifications.daemon.enable {
      notificationDaemon = true;
    });
  configuredDisabledPlugins = cfg.shell.config.disabledPlugins or [ ];
  configuredBackgroundDisabled = builtins.elem "omarchy.background" configuredDisabledPlugins;
  backgroundEnabled = cfg.background.enable && !configuredBackgroundDisabled;
  runtime = omanixyRuntimeFor cfg.features (
    (if securitySelection == { }
    then { }
    else securitySelection)
    // { background = backgroundEnabled; }
  );
  coreutils = "${pkgs.coreutils}/bin";
  baselineSource = builtins.fromJSON (builtins.readFile ../../upstream/shell-baseline.json);
  featureSelection = import ../../lib/feature-selection.nix { inherit lib; baseline = baselineSource; };
  historicalBaseline = builtins.fromJSON (builtins.readFile ../../upstream/shell-baseline-v1.json);
  baselineConfig = builtins.removeAttrs baselineSource [ "featurePlugins" "featureDependencies" "featureOrder" "migrations" "featureCapabilities" "capabilityDependencies" ];
  featurePlugins = baselineSource.featurePlugins;
  selectedFeatures = featureSelection.select cfg.features;
  effectiveDisabledPlugins = lib.unique (baselineConfig.disabledPlugins
    ++ configuredDisabledPlugins
    ++ lib.optional (!backgroundEnabled) "omarchy.background");
  omittedFeaturePlugins = lib.concatLists (map
    (feature: featurePlugins.${feature} or [ ])
    (lib.filter (feature: !builtins.elem feature selectedFeatures) (builtins.attrNames featurePlugins)));
  runtimeBlockedPlugins = lib.unique (baselineConfig.disabledPlugins
    ++ omittedFeaturePlugins
    ++ lib.optional (!backgroundEnabled) "omarchy.background");
  effectiveConfig = baselineConfig // cfg.shell.config // {
    disabledPlugins = effectiveDisabledPlugins;
  };
  configJson = builtins.toJSON effectiveConfig;
  configSeed = pkgs.writeText "omanixy-shell-config" configJson;
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
      '
        if . == $legacy then
          $current
        elif has("disabledPlugins") and (.disabledPlugins | type) != "array" then
          error("disabledPlugins must be a JSON array")
        else
          .
        end
      ' "$source" > "$destination"
    trap - EXIT
  '';
  runtimeTheme = runtime.passthru.theme;
  defaultBackground = runtime.passthru.defaultBackground;
in
{
  options.programs.omanixy = {
    enable = lib.mkEnableOption "the Omanixy Quattro shell";

    features = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "audio" "bluetooth" "clipboard" "launcher" "monitor" "network" "notification" "power" "screenshot" "weather" ];
      description = "Optional Omanixy presentation feature groups; each selected group resolves the runtime capabilities and exact helper contracts required by its reachable consumers.";
    };

    shell.config = lib.mkOption {
      type = lib.types.attrsOf lib.types.json;
      default = { };
      defaultText = lib.literalExpression "{ }";
      description = ''
        Partial upstream-compatible Quattro shell.json configuration.
        Omanixy merges user keys under the safe baseline and preserves the
        baseline disabled-plugin floor in the generated file.
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

    font.package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.nerd-fonts.jetbrains-mono;
      description = "Font package provisioned for the Omanixy monospace default.";
    };

    font.family = lib.mkOption {
      type = lib.types.str;
      default = "JetBrainsMono Nerd Font";
      description = "Default monospace family selected by Omanixy.";
    };

    background.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable Omanixy's pinned Quattro background renderer and default state.";
    };

    background.default = lib.mkOption {
      type = lib.types.path;
      default = defaultBackground;
      description = "Immutable image target materialized as the default writable background state.";
    };

    security.lock.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Enable the experimental, password-only native Quickshell session
        lock (shell/plugins/lock). This is not the stable default: Omanixy
        does not own screen locking unless this is explicitly turned on.

        Password authentication via PAM is always available through this
        option; `programs.omanixy.security.lock.fingerprint.enable` adds an
        optional, disabled-by-default fingerprint unlock path alongside it.
        Omanixy binds no keybinding to trigger the lock and provides no
        fallback lock mechanism, so the consumer must wire their own trigger
        (for example a Hyprland keybind invoking the shell's `lock` IPC
        target).

        Enabling this option on a standalone Home Manager installation
        (without a paired NixOS configuration) always fails evaluation,
        because there is no way to provision the PAM service the lock
        authenticates against. On an integrated NixOS + Home Manager
        installation, this option additionally requires
        `programs.omanixy.security.pam.password.enable` to be `true` in the
        NixOS configuration.
      '';
    };

    security.lock.fingerprint.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Enable fingerprint authentication as a secondary unlock path for the
        native Quickshell session lock, alongside (never instead of)
        password authentication. Password authentication remains mandatory
        and always functional regardless of this option.

        This option is only meaningful while
        `programs.omanixy.security.lock.enable` is also `true`; enabling it
        without the lock itself enabled fails evaluation. Like the lock
        itself, it requires an integrated NixOS + Home Manager installation:
        enabling it on a standalone Home Manager installation (no `osConfig`)
        always fails evaluation, because there is no way to provision the
        `omarchy-lock-fingerprint` PAM service or the fprintd daemon backing
        it. On an integrated installation, it additionally requires both
        `programs.omanixy.security.pam.password.enable` and
        `programs.omanixy.security.pam.fingerprint.enable` to be `true` in
        the paired NixOS configuration - the former because fingerprint is
        only ever a secondary path to the mandatory password fallback, the
        latter because it provisions the fingerprint PAM service and daemon
        this option authenticates against.

        This is a Nix-declared capability, not a runtime readiness claim: a
        machine with this enabled but no fingerprint reader (or no enrolled
        finger) still builds and boots successfully, and unlock silently
        falls back to password-only.
      '';
    };

    security.polkit.agent.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Select the native Quattro polkit authentication agent
        (shell/plugins/polkit) as this session's polkit authentication agent.

        This option is fully independent of
        `programs.omanixy.security.lock.enable` and its fingerprint
        sub-option: enabling one never implies or requires the other, and a
        polkit-only runtime with the lock left disabled (or vice versa) is a
        supported configuration.

        Enabling this option on a standalone Home Manager installation
        (without a paired NixOS configuration) always fails evaluation,
        because there is no way to provision the NixOS
        `security.polkit` system capability the agent registers against. On
        an integrated NixOS + Home Manager installation, this option
        additionally requires
        `programs.omanixy.security.polkit.system.enable` to be `true` in the
        NixOS configuration - the explicit system/session ownership
        handshake, mirroring the lock capability's own
        `security.pam.password` handshake.

        Enabling this option asserts that no other Home Manager-managed
        polkit agent this repository knows how to detect declaratively
        (`services.hyprpolkitagent.enable`, `services.polkit-gnome.enable`)
        is also enabled, since two session polkit agents intentionally
        competing for the same registration is never correct. Omanixy does
        not stop, disable, or otherwise mutate another agent on your behalf;
        it only refuses to evaluate a configuration that declares two at
        once. An agent this repository has no way to detect declaratively
        (an unknown external agent already registered at runtime) is left
        alone entirely: the pinned Quickshell `PolkitAgent` listener reports
        a bounded, diagnostic registration failure rather than taking over or
        retrying in a loop, and Omanixy never kills or disables an unknown
        agent to make this option's agent win.

        The Quattro agent presentation is authentication-method-neutral: it
        is driven only by the pinned Quickshell `AuthFlow.isResponseRequired`
        signal, never by parsing `/etc/pam.d/polkit-1` or laptop lid state,
        so it never assumes or requires fingerprint hardware.
      '';
    };

    security.idle.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Select the native Quattro idle owner
        (shell/plugins/services/idle) for this session: an experimental,
        disabled-by-default capability that requests the Omanixy native
        lock after a period of user inactivity.

        This is user-session idle detection and bounded lock-on-idle
        orchestration only. It respects Wayland idle inhibitors (an
        application that actively inhibits idle through the compositor
        protocol keeps the session from being considered idle at all;
        there is no option to turn that off). It does not suspend the
        machine, does not own display DPMS blanking or wake, and does not
        own any system sleep policy - those remain entirely the
        consumer's or NixOS's own responsibility, exactly as before this
        option existed.

        This option requires `programs.omanixy.security.lock.enable` to
        also be `true`: Layer 6 owns no lock provider of its own, only
        bounded orchestration of the already-audited, already-reviewed
        Layer-3 native lock IPC. There is no configurable alternative lock
        provider, dispatcher, or arbitrary shell command - a consumer using
        an external lock provider may continue using an external idle
        manager instead of this option. It is otherwise fully independent
        of `programs.omanixy.security.polkit.agent.enable` and
        `programs.omanixy.security.lock.fingerprint.enable`: enabling idle
        never implies or requires either.

        Enabling this option asserts that no other Home Manager-managed
        idle daemon this repository knows how to detect declaratively
        (`services.hypridle.enable`, `services.swayidle.enable`) is also
        enabled, since two idle managers intentionally competing to decide
        when the session is idle is never correct. Omanixy does not stop,
        mask, or otherwise mutate another idle manager's unit on your
        behalf, and does not attempt to detect an idle manager it has no
        declarative option for; it only refuses to evaluate a configuration
        that declares a known-conflicting one alongside this option.
      '';
    };

    security.notifications.daemon.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Select the native Quattro notification daemon
        (shell/plugins/notifications) to own this user session's
        `org.freedesktop.Notifications` D-Bus service name: an
        experimental, disabled-by-default capability providing adapted
        Quattro popup presentation, do-not-disturb, and bounded local
        history/popup persistence.

        This option is session D-Bus ownership only, not a system
        capability, and there is no paired NixOS option. It is fully
        independent of `programs.omanixy.security.lock.enable`,
        `programs.omanixy.security.lock.fingerprint.enable`,
        `programs.omanixy.security.polkit.agent.enable`, and
        `programs.omanixy.security.idle.enable`: enabling this option never
        implies or requires any of them, and none of them imply or require
        this option. It is also fully independent of the presentation
        `programs.omanixy.features = [ "notification" ]` client capability
        (`notification-send`/`omarchy-notification-send`): that capability
        continues to mean only that this session can send notifications to
        whatever daemon already owns the service name, and neither option
        enables or requires the other.

        Enabling this option asserts that no other Home Manager-managed
        notification daemon this repository knows how to detect
        declaratively (`services.mako.enable`, `services.dunst.enable`,
        `services.swaync.enable`, `services.fnott.enable`) is also enabled,
        since two notification daemons intentionally competing for the same
        D-Bus service name is never correct. Omanixy does not stop, mask,
        kill, or otherwise mutate another daemon on your behalf; it only
        refuses to evaluate a configuration that declares two at once. A
        daemon this repository has no way to detect declaratively (an
        unknown external daemon already registered at runtime) is left
        alone entirely: the pinned Quickshell `NotificationServer` reports a
        bounded, diagnostic registration failure rather than taking over or
        retrying in a loop, and Omanixy never kills or replaces an unknown
        daemon to make this option's daemon win. When that external owner
        later disappears, the pinned server retries registration
        event-driven, never on a polling timer.

        The adapted daemon intentionally does not execute the historical
        `omarchy-exec` notification hint, any other arbitrary command or
        argument carried in notification hints, or a compositor-focus
        fallback for notifications without a live default action: only the
        standard, sender-owned freedesktop `default` action may be invoked,
        and a click with no such action simply dismisses the toast. This is
        a hard security boundary, not a temporary limitation.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    fonts.fontconfig.enable = lib.mkDefault true;
    fonts.fontconfig.defaultFonts.monospace = lib.mkDefault [ cfg.font.family ];
    assertions = [
      {
        assertion = (effectiveConfig.version or null) == 1;
        message = "programs.omanixy.shell.config.version must be 1; partial overrides inherit the safe Quattro v1 baseline, but explicit values must remain compatible with version 1";
      }
      {
        assertion = builtins.isList configuredDisabledPlugins
          && builtins.all builtins.isString configuredDisabledPlugins;
        message = "programs.omanixy.shell.config.disabledPlugins must be a list of strings";
      }
      {
        assertion = !cfg.security.lock.enable || osConfig != null;
        message = ''
          programs.omanixy.security.lock.enable is true, but this Home
          Manager configuration is standalone (no NixOS osConfig is
          available). The native lock authenticates via a
          NixOS-provisioned PAM service
          (programs.omanixy.security.pam.password.enable), which a
          standalone Home Manager installation has no way to provision.
          Import this Home Manager configuration through the standard
          NixOS Home Manager integration module, inside a NixOS
          configuration that also enables
          programs.omanixy.security.pam.password, or leave
          programs.omanixy.security.lock.enable at its default (false).
        '';
      }
      {
        assertion = !cfg.security.lock.enable || osConfig == null
          || (osConfig.programs.omanixy.security.pam.password.enable or false) == true;
        message = ''
          programs.omanixy.security.lock.enable is true, but the paired
          NixOS configuration does not enable
          programs.omanixy.security.pam.password.enable. The native lock's
          PamContext authenticates against the password PAM service that
          only that NixOS option provisions; without it, every unlock
          attempt fails closed. Enable
          programs.omanixy.security.pam.password.enable in the NixOS
          configuration that imports this Home Manager configuration, or
          leave programs.omanixy.security.lock.enable at its default
          (false).
        '';
      }
      {
        assertion = !cfg.security.lock.fingerprint.enable || cfg.security.lock.enable;
        message = ''
          programs.omanixy.security.lock.fingerprint.enable is true, but
          programs.omanixy.security.lock.enable is not. Fingerprint is only
          ever a secondary unlock path for the native lock; enable
          programs.omanixy.security.lock first, or leave
          programs.omanixy.security.lock.fingerprint.enable at its default
          (false).
        '';
      }
      {
        assertion = !cfg.security.lock.fingerprint.enable || osConfig != null;
        message = ''
          programs.omanixy.security.lock.fingerprint.enable is true, but
          this Home Manager configuration is standalone (no NixOS osConfig
          is available). Fingerprint authenticates via a NixOS-provisioned
          PAM service and fprintd daemon
          (programs.omanixy.security.pam.fingerprint.enable), which a
          standalone Home Manager installation has no way to provision.
          Import this Home Manager configuration through the standard
          NixOS Home Manager integration module, inside a NixOS
          configuration that also enables
          programs.omanixy.security.pam.fingerprint, or leave
          programs.omanixy.security.lock.fingerprint.enable at its default
          (false).
        '';
      }
      {
        assertion = !cfg.security.lock.fingerprint.enable || osConfig == null
          || (osConfig.programs.omanixy.security.pam.password.enable or false) == true;
        message = ''
          programs.omanixy.security.lock.fingerprint.enable is true, but the
          paired NixOS configuration does not enable
          programs.omanixy.security.pam.password.enable. Fingerprint is only
          ever a secondary path to the mandatory password fallback, never a
          replacement for it; enable
          programs.omanixy.security.pam.password.enable in the NixOS
          configuration that imports this Home Manager configuration, or
          leave programs.omanixy.security.lock.fingerprint.enable at its
          default (false).
        '';
      }
      {
        assertion = !cfg.security.lock.fingerprint.enable || osConfig == null
          || (osConfig.programs.omanixy.security.pam.fingerprint.enable or false) == true;
        message = ''
          programs.omanixy.security.lock.fingerprint.enable is true, but the
          paired NixOS configuration does not enable
          programs.omanixy.security.pam.fingerprint.enable. Fingerprint
          authenticates against the omarchy-lock-fingerprint PAM service and
          fprintd daemon that only that NixOS option provisions; without it,
          every fingerprint unlock attempt would be unavailable. Enable
          programs.omanixy.security.pam.fingerprint.enable in the NixOS
          configuration that imports this Home Manager configuration, or
          leave programs.omanixy.security.lock.fingerprint.enable at its
          default (false).
        '';
      }
      {
        assertion = !cfg.security.polkit.agent.enable || osConfig != null;
        message = ''
          programs.omanixy.security.polkit.agent.enable is true, but this
          Home Manager configuration is standalone (no NixOS osConfig is
          available). The Quattro polkit agent registers against a
          NixOS-provisioned security.polkit system capability
          (programs.omanixy.security.polkit.system.enable), which a
          standalone Home Manager installation has no way to provision.
          Import this Home Manager configuration through the standard
          NixOS Home Manager integration module, inside a NixOS
          configuration that also enables
          programs.omanixy.security.polkit.system.enable, or leave
          programs.omanixy.security.polkit.agent.enable at its default
          (false).
        '';
      }
      {
        assertion = !cfg.security.polkit.agent.enable || osConfig == null
          || (osConfig.programs.omanixy.security.polkit.system.enable or false) == true;
        message = ''
          programs.omanixy.security.polkit.agent.enable is true, but the
          paired NixOS configuration does not enable
          programs.omanixy.security.polkit.system.enable. The Quattro polkit
          agent registers against the NixOS-provisioned security.polkit
          capability that only that NixOS option provisions; without it there
          is nothing for the agent to register with. Enable
          programs.omanixy.security.polkit.system.enable in the NixOS
          configuration that imports this Home Manager configuration, or
          leave programs.omanixy.security.polkit.agent.enable at its default
          (false).
        '';
      }
      {
        assertion = !cfg.security.polkit.agent.enable
          || !(config.services.hyprpolkitagent.enable or false);
        message = ''
          programs.omanixy.security.polkit.agent.enable is true while
          services.hyprpolkitagent.enable is also true. Both are session
          polkit authentication agents and must not intentionally compete.
          Disable one; Omanixy will not stop or kill the other agent for you.
        '';
      }
      {
        assertion = !cfg.security.polkit.agent.enable
          || !(config.services.polkit-gnome.enable or false);
        message = ''
          programs.omanixy.security.polkit.agent.enable is true while
          services.polkit-gnome.enable is also true. Both are session polkit
          authentication agents and must not intentionally compete. Disable
          one; Omanixy will not stop or kill the other agent for you.
        '';
      }
      {
        assertion = !cfg.security.idle.enable || cfg.security.lock.enable;
        message = ''
          programs.omanixy.security.idle.enable is true, but
          programs.omanixy.security.lock.enable is not. Layer 6 owns no
          lock provider of its own - only bounded orchestration of the
          native Omanixy lock's already-audited IPC - so idle-on-inactivity
          has nothing to request. Enable
          programs.omanixy.security.lock.enable, or leave
          programs.omanixy.security.idle.enable at its default (false) and
          use an external idle manager with your existing lock provider
          instead.
        '';
      }
      {
        assertion = !cfg.security.idle.enable
          || !(config.services.hypridle.enable or false);
        message = ''
          programs.omanixy.security.idle.enable is true while
          services.hypridle.enable is also true. Both are session idle
          managers and must not intentionally compete. Disable one; Omanixy
          will not stop or mask the other idle manager for you.
        '';
      }
      {
        assertion = !cfg.security.idle.enable
          || !(config.services.swayidle.enable or false);
        message = ''
          programs.omanixy.security.idle.enable is true while
          services.swayidle.enable is also true. Both are session idle
          managers and must not intentionally compete. Disable one; Omanixy
          will not stop or mask the other idle manager for you.
        '';
      }
      {
        assertion = !cfg.security.notifications.daemon.enable
          || !(config.services.mako.enable or false);
        message = ''
          programs.omanixy.security.notifications.daemon.enable is true
          while services.mako.enable is also true. Both are session
          notification daemons and must not intentionally compete for
          org.freedesktop.Notifications. Disable one; Omanixy will not
          stop or kill the other daemon for you.
        '';
      }
      {
        assertion = !cfg.security.notifications.daemon.enable
          || !(config.services.dunst.enable or false);
        message = ''
          programs.omanixy.security.notifications.daemon.enable is true
          while services.dunst.enable is also true. Both are session
          notification daemons and must not intentionally compete for
          org.freedesktop.Notifications. Disable one; Omanixy will not
          stop or kill the other daemon for you.
        '';
      }
      {
        assertion = !cfg.security.notifications.daemon.enable
          || !(config.services.swaync.enable or false);
        message = ''
          programs.omanixy.security.notifications.daemon.enable is true
          while services.swaync.enable is also true. Both are session
          notification daemons and must not intentionally compete for
          org.freedesktop.Notifications. Disable one; Omanixy will not
          stop or kill the other daemon for you.
        '';
      }
      {
        assertion = !cfg.security.notifications.daemon.enable
          || !(config.services.fnott.enable or false);
        message = ''
          programs.omanixy.security.notifications.daemon.enable is true
          while services.fnott.enable is also true. Both are session
          notification daemons and must not intentionally compete for
          org.freedesktop.Notifications. Disable one; Omanixy will not
          stop or kill the other daemon for you.
        '';
      }
    ];

    home.packages = [ runtime cfg.font.package ];

    home.activation.omanixyShellState = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      config_dir="$HOME/.config/omarchy"
      config_file="$config_dir/shell.json"
      capability_dir="$HOME/.local/state/omanixy"
      capability_file="$capability_dir/capabilities.json"
      theme_dir="$HOME/.local/state/omarchy/current/theme"
      background_dir="$HOME/.local/state/omarchy/current"
      background_file="$background_dir/background"

      run ${coreutils}/mkdir -p "$config_dir" "$config_dir/plugins"
      run ${coreutils}/mkdir -p "$capability_dir"
      ${lib.optionalString backgroundEnabled ''
      run ${coreutils}/mkdir -p "$background_dir"
      if [ -L "$background_file" ] && [ ! -e "$background_file" ]; then
        run ${coreutils}/rm -f -- "$background_file"
      fi
      if [ ! -e "$background_file" ]; then
        run ${coreutils}/ln -s -- '${cfg.background.default}' "$background_file"
      fi
      ''}

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
