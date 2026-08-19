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
in
{
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

        This is a Nix-declared capability, not a runtime readiness claim: a
        machine with this enabled but no fingerprint reader (or no enrolled
        finger) still builds and boots successfully, and password
        authentication remains mandatory and always functional regardless
        of this option or of fingerprint hardware state.
      '';
    };
  };

  config = lib.mkMerge [
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
      ];
    })
  ];
}
