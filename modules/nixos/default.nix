{ config, lib, ... }:

let
  cfg = config.programs.omanixy.security.pam.password;
in
{
  options.programs.omanixy.security.pam.password = {
    enable = lib.mkOption {
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
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    security.pam.services."omarchy-lock-password".text = ''
      auth required ${config.security.pam.package}/lib/security/pam_unix.so
    '';
  };
}
