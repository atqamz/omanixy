#!/usr/bin/env bash
set -euo pipefail

fprintd_enable_conflict_toplevel_forced=${1:?fprintd-enable-conflict config.system.build.toplevel eval result required}
no_widening_toplevel_forced=${2:?no-widening config.system.build.toplevel eval result required}
no_widening_fprintd_enable=${3:?no-widening resolved services.fprintd.enable value required}
no_widening_login_fprint_auth=${4:?no-widening login fprintAuth value required}
no_widening_sudo_fprint_auth=${5:?no-widening sudo fprintAuth value required}
no_widening_su_fprint_auth=${6:?no-widening su fprintAuth value required}
no_widening_sshd_fprint_auth=${7:?no-widening sshd fprintAuth value required}
no_widening_polkit_fprint_auth=${8:?no-widening polkit-1 fprintAuth value required}
no_widening_package_registered=${9:?no-widening fprintd package registration value required}

# The hazard: nixos/modules/security/pam.nix reads services.fprintd.enable
# as the default for every other PAM service's own fprintAuth. A host or
# module setting that option directly while the Omanixy fingerprint
# capability is also on must be rejected by the capability's own first
# assertion, closed - not silently accepted alongside a widened sshd/polkit.
test "$fprintd_enable_conflict_toplevel_forced" = false

# The no-widening proof: with services.fprintd.enable deliberately left
# untouched (the capability's actual mechanism), sshd and polkit-1 - both
# genuinely present in this fixture via services.openssh.enable and
# security.polkit.enable - along with the always-present login/sudo/su PAM
# services, all resolve fprintAuth = false, and the daemon's package is
# still registered directly by the Omanixy capability.
test "$no_widening_toplevel_forced" = true
test "$no_widening_fprintd_enable" = false
test "$no_widening_login_fprint_auth" = false
test "$no_widening_sudo_fprint_auth" = false
test "$no_widening_su_fprint_auth" = false
test "$no_widening_sshd_fprint_auth" = false
test "$no_widening_polkit_fprint_auth" = false
test "$no_widening_package_registered" = true

printf '%s\n' 'security pam fingerprint widening checks passed'
