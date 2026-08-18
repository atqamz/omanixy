{ config, lib, ... }:

let
  cfg = config.programs.omanixy.security.pam.password;
  passwordPamText = ''
    auth required ${config.security.pam.package}/lib/security/pam_unix.so
  '';
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
  };

  config = lib.mkIf cfg.enable {
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
  };
}
