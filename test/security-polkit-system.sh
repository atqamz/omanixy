#!/usr/bin/env bash
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

test "$disabled_polkit_enabled" = false
test "$disabled_pkexec_wrapper" = false

test "$system_enabled_polkit_enable" = true
test "$system_enabled_polkit1_pam_enable" = true
test "$system_enabled_pkexec_wrapper" = false

test "$adversarial_toplevel_forced" = false

test "$plain_polkit_toplevel_forced" = true
test "$plain_polkit_enable" = true
test "$systemd_services_match" = true
test "$dbus_packages_match" = true
test "$pam_services_match" = true

printf '%s\n' 'polkit system capability checks passed'
