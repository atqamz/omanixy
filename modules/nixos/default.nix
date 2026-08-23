{ config, lib, ... }:

let
  cfgPassword = config.programs.omanixy.security.pam.password;
  passwordPamText = ''
    auth required ${config.security.pam.package}/lib/security/pam_unix.so
  '';

  cfgFingerprint = config.programs.omanixy.security.pam.fingerprint;
  fingerprintPamText = ''
    auth required ${config.services.fprintd.package}/lib/security/pam_fprintd.so
  '';

  cfgPolkitSystem = config.programs.omanixy.security.polkit.system;
in
{
  options.programs.omanixy.security.polkit.system = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Declare the NixOS `security.polkit.enable` system capability that a
        polkit authentication agent (Quattro's own, via
        `programs.omanixy.security.polkit.agent.enable` in the Home Manager
        module, or any other consumer- or externally-managed agent) needs in
        order to have something to register with.

        This option owns exactly one thing: turning on NixOS's own native
        `security.polkit` module. It declares `security.polkit.enable = true`
        using an ordinary (non-forced) assignment, deliberately leaving
        NixOS's own polkit module to do everything it already does -
        `polkitd`, its D-Bus and systemd integration, the `polkit-agent-helper`
        binary, and the `polkit-1` PAM service - exactly as it would for any
        other consumer of `security.polkit.enable`. Omanixy does not
        second-guess, duplicate, or imperatively mutate any of that: no second
        `polkitd`, no custom `polkit-1` PAM text or `lib.mkForce` override of
        it, no new PAM service, and no
        `security.polkit.enablePkexecWrapper` (a separate NixOS knob this
        option never sets or requires).

        Because the assignment is ordinary rather than forced, a host or
        another module can still legitimately set `security.polkit.enable`
        itself; this option resolving to `true` and NixOS's own
        `security.polkit.enable` module option resolving to `true` are
        expected to agree, and an assertion fails the build closed if a
        stronger override (for example `lib.mkForce false` placed by some
        other module) disagrees with it, rather than silently leaving this
        option's stated capability unfulfilled.

        Enabling this option selects no session-side polkit authentication
        agent by itself: it is purely the system-capability half of the
        Layer-5 ownership split. Home Manager's
        `programs.omanixy.security.polkit.agent.enable` is the independent,
        session-side half that actually selects the Quattro polkit agent
        plugin, and requires this option to be enabled on the paired NixOS
        configuration before it will do so.
      '';
    };
  };

  options.programs.omanixy.security.pam = {
    password.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Declare the dedicated, auth-only `omarchy-lock-password` PAM service
        consumed by the pinned Quickshell `PamContext` screen-lock ABI
        (`shell/plugins/lock/Service.qml`).

        `PamContext` only calls `pam_authenticate` against this service; it
        never runs the account, session, or password PAM phases, so this
        option declares an auth-only stack with no unrelated login policy.
        Empty-password authentication is rejected: the stack contains no
        `nullok` and no unconditional-success module.

        This option does not enable the native Quattro lock, fingerprint
        authentication, polkit, idle, or notification ownership, and does
        not perform any imperative `/etc` mutation; the PAM service file is
        generated declaratively by `security.pam.services` like any other
        NixOS PAM service.

        The `security.pam.services.<name>` service submodule has an
        independently configurable `enable` (default `true`, filtered out of
        `/etc/pam.d` generation when false) as well as a `text` typed
        `nullOr lines`, which merges same-priority definitions by newline
        concatenation. While this option is enabled, Omanixy owns both the
        `enable` state and the entire text of the `omarchy-lock-password`
        service via `lib.mkForce`, so this capability being reported `true`
        always implies the service is actually present with exactly this
        text: an unrelated normal-priority definition cannot disable the
        service or silently extend its authentication stack, and an
        assertion fails the build closed if some other module contests
        ownership at an equal-or-stronger priority. A consumer who wants a
        different policy for this service must disable this option rather
        than add to it.
      '';
    };

    fingerprint.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Declare the dedicated, auth-only `omarchy-lock-fingerprint` PAM
        service consumed by the pinned Quickshell `PamContext` screen-lock
        ABI, as a secondary unlock path alongside (never instead of)
        `programs.omanixy.security.pam.password`.

        Enabling this option atomically owns the `omarchy-lock-fingerprint`
        PAM service (both `enable` and its entire `text` forced via
        `lib.mkForce`, with an assertion verifying the resolved state
        actually matches this single auth-only `pam_fprintd.so` line rather
        than assuming it from the override alone, mirroring the password
        capability's ownership contract exactly) and the daemon activation
        that service's module needs `pam_fprintd.so` to come from: the
        resolved `services.fprintd.package` is registered with
        `services.dbus.packages`, `systemd.packages`, and
        `environment.systemPackages`.

        This deliberately never sets `services.fprintd.enable` itself.
        `nixos/modules/security/pam.nix` reads that option as the default
        for every *other* PAM service's own `fprintAuth`, so turning it on
        would silently widen fingerprint authentication into
        login/sudo/su/polkit-1/greetd/sshd and any other PAM service that
        does not override `fprintAuth` itself - a generic, system-wide
        binding this option must never introduce. Registering the daemon's
        package directly, the way `services.fprintd`'s own module does when
        enabled, gives `omarchy-lock-fingerprint` a working `pam_fprintd.so`
        without touching the option any other service's default keys off
        of. This option never declares a generic `fprintAuth`-style
        login/sudo/su/polkit/greetd/sshd binding, and never touches
        `pam_unix.so`, `pam_permit.so`, `nullok`, or the account/session/
        password PAM phases.

        When `services.fprintd.tod.enable` is also set, this mirrors the one
        environment variable `nixos/modules/services/security/fprintd.nix`
        would otherwise only set inside its own `services.fprintd.enable`
        gate (`FP_TOD_DRIVERS_DIR`, pointing at the selected TOD driver) onto
        the `fprintd.service` unit, the same way that upstream module does
        it: layering an environment override onto the unit registered via
        `systemd.packages` above, without independently re-deriving or
        widening `services.fprintd.package`'s own already-TOD-aware default.

        This is a Nix-declared capability, not a runtime readiness claim: a
        machine with this enabled but no fingerprint reader (or no enrolled
        finger) still builds and boots successfully, and password
        authentication remains mandatory and always functional regardless
        of this option or of fingerprint hardware state.
      '';
    };
  };

  config = lib.mkMerge [
    (lib.mkIf cfgPolkitSystem.enable {
      security.polkit.enable = true;

      assertions = [
        {
          assertion = config.security.polkit.enable == true;
          message = ''
            programs.omanixy.security.polkit.system.enable is true, but the
            resolved security.polkit.enable is not true. This capability
            declares security.polkit.enable with an ordinary assignment
            rather than lib.mkForce, deliberately letting genuine consumer
            policy win; another module or host configuration is overriding
            security.polkit.enable at an equal-or-stronger priority (for
            example lib.mkForce false). If that override is intentional,
            disable programs.omanixy.security.polkit.system.enable instead
            of contesting security.polkit.enable underneath it.
          '';
        }
      ];
    })

    (lib.mkIf cfgPassword.enable {
      security.pam.services."omarchy-lock-password" = {
        enable = lib.mkForce true;
        text = lib.mkForce passwordPamText;
      };

      assertions = [
        {
          assertion =
            config.security.pam.services."omarchy-lock-password".enable == true
            && config.security.pam.services."omarchy-lock-password".text == passwordPamText;
          message = ''
            programs.omanixy.security.pam.password.enable is true, but the
            resolved security.pam.services."omarchy-lock-password" service does
            not match the Omanixy-owned contract (enable = true; text = the
            single auth-only pam_unix.so line). Another module is defining this
            service's enable or text at an equal-or-stronger override priority
            (for example, a second lib.mkForce): nixpkgs' `lines` type can
            combine same-priority text definitions by concatenation instead of
            raising a conflict, so ownership must be verified explicitly rather
            than assumed from mkForce alone. Disable
            programs.omanixy.security.pam.password if this service needs a
            different policy; this option does not provide an extraConfig
            escape hatch.
          '';
        }
      ];
    })

    (lib.mkIf cfgFingerprint.enable {
      services.dbus.packages = [ config.services.fprintd.package ];
      systemd.packages = [ config.services.fprintd.package ];
      environment.systemPackages = [ config.services.fprintd.package ];

      # services.fprintd.package's own default already resolves to the TOD
      # variant when services.fprintd.tod.enable is set, independent of
      # services.fprintd.enable, so the registrations above already carry a
      # TOD-capable daemon with no change needed. The one thing the upstream
      # module only wires inside its own services.fprintd.enable-gated
      # config block is this environment variable telling that daemon where
      # to find the driver; since this capability never sets
      # services.fprintd.enable, that block never runs, so it is mirrored
      # here instead - narrowly, and only this one variable.
      systemd.services.fprintd.environment = lib.mkIf config.services.fprintd.tod.enable {
        FP_TOD_DRIVERS_DIR = "${config.services.fprintd.tod.driver}${config.services.fprintd.tod.driver.driverPath}";
      };

      security.pam.services."omarchy-lock-fingerprint" = {
        enable = lib.mkForce true;
        text = lib.mkForce fingerprintPamText;
      };

      assertions = [
        {
          assertion = config.services.fprintd.enable == false;
          message = ''
            programs.omanixy.security.pam.fingerprint.enable is true, but the
            resolved services.fprintd.enable is true. This capability never
            sets that option itself: nixos/modules/security/pam.nix reads it
            as the default for every other PAM service's own fprintAuth, so
            turning it on would silently widen fingerprint authentication
            into login/sudo/su/polkit-1/greetd/sshd and any other PAM
            service that does not override fprintAuth itself. Some other
            module or host configuration is setting services.fprintd.enable
            directly; remove that and let this capability own the daemon's
            activation instead, or disable
            programs.omanixy.security.pam.fingerprint if the host genuinely
            needs generic fprintd-backed authentication elsewhere.
          '';
        }
        {
          assertion =
            builtins.elem config.services.fprintd.package config.services.dbus.packages
            && builtins.elem config.services.fprintd.package config.systemd.packages
            && builtins.elem config.services.fprintd.package config.environment.systemPackages;
          message = ''
            programs.omanixy.security.pam.fingerprint.enable is true, but the
            resolved services.fprintd.package is missing from
            services.dbus.packages, systemd.packages, or
            environment.systemPackages. Another module is overriding one of
            these lists with mkForce (list-typed options otherwise merge by
            concatenation, so ownership must be verified explicitly rather
            than assumed). Disable
            programs.omanixy.security.pam.fingerprint if this host needs a
            different fprintd activation path.
          '';
        }
        {
          assertion =
            config.security.pam.services."omarchy-lock-fingerprint".enable == true
            && config.security.pam.services."omarchy-lock-fingerprint".text == fingerprintPamText;
          message = ''
            programs.omanixy.security.pam.fingerprint.enable is true, but the
            resolved security.pam.services."omarchy-lock-fingerprint" service
            does not match the Omanixy-owned contract (enable = true; text =
            the single auth-only pam_fprintd.so line, sourced from the final
            resolved services.fprintd.package). Another module is defining
            this service's enable or text at an equal-or-stronger override
            priority (for example, a second lib.mkForce): nixpkgs' `lines`
            type can combine same-priority text definitions by concatenation
            instead of raising a conflict, so ownership must be verified
            explicitly rather than assumed from mkForce alone. Disable
            programs.omanixy.security.pam.fingerprint if this service needs a
            different policy; this option does not provide an extraConfig
            escape hatch.
          '';
        }
        {
          assertion = !config.services.fprintd.tod.enable
            || (config.systemd.services.fprintd.environment.FP_TOD_DRIVERS_DIR or null)
            == "${config.services.fprintd.tod.driver}${config.services.fprintd.tod.driver.driverPath}";
          message = ''
            programs.omanixy.security.pam.fingerprint.enable and
            services.fprintd.tod.enable are both true, but the resolved
            systemd.services.fprintd.environment.FP_TOD_DRIVERS_DIR does not
            match the selected TOD driver's path. Another module is
            overriding that unit's environment at an equal-or-stronger
            priority; this capability needs to own it so the TOD-aware
            daemon it activates can actually find its driver. Disable
            programs.omanixy.security.pam.fingerprint if this host needs a
            different fprintd/TOD activation path.
          '';
        }
      ];
    })
  ];
}
