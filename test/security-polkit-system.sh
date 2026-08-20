#!/usr/bin/env bash
# NixOS system-capability matrix for programs.omanixy.security.polkit.system.
# Mirrors test/security-pam-capability.sh's owned/adversarial fixture
# structure, but the capability here declares security.polkit.enable with an
# ordinary (non-forced) assignment rather than owning a whole PAM service
# text, so the adversary that matters is a stronger override (lib.mkForce
# false) rather than a same-priority text conflict.
set -euo pipefail

disabled_polkit_enabled=${1:?}
system_enabled_polkit_enable=${2:?}
system_enabled_polkit1_pam_enable=${3:?}
system_enabled_pkexec_wrapper=${4:?}
disabled_pkexec_wrapper=${5:?}
adversarial_toplevel_forced=${6:?}
plain_polkit_toplevel_forced=${7:?}
plain_polkit_enable=${8:?}
systemd_services_match=${9:?}
dbus_packages_match=${10:?}
pam_services_match=${11:?}

# A. Default (system.enable = false, the default): Omanixy has no opinion,
# native security.polkit.enable remains false.
test "$disabled_polkit_enabled" = false
test "$disabled_pkexec_wrapper" = false

# B. system.enable = true: resolved security.polkit.enable is true, the
# native polkit-1 PAM service NixOS's own security.polkit module creates is
# enabled, and Omanixy adds no pkexec wrapper requirement of its own.
test "$system_enabled_polkit_enable" = true
test "$system_enabled_polkit1_pam_enable" = true
test "$system_enabled_pkexec_wrapper" = false

# C. Stronger external override (security.polkit.enable = lib.mkForce
# false) alongside system.enable = true must fail config.system.build.
# toplevel closed via Omanixy's own resolved-state assertion, rather than
# silently leaving the option's stated capability unfulfilled.
test "$adversarial_toplevel_forced" = false

# D. No second polkitd, no new PAM service, no imperative duplication:
# Omanixy's system.enable = true resolves an identical systemd/D-Bus/PAM
# surface to a host that sets NixOS's own security.polkit.enable = true
# directly, with no Omanixy involvement at all.
test "$plain_polkit_toplevel_forced" = true
test "$plain_polkit_enable" = true
test "$systemd_services_match" = true
test "$dbus_packages_match" = true
test "$pam_services_match" = true

printf '%s\n' 'polkit system capability checks passed'
