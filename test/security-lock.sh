#!/usr/bin/env bash
set -euo pipefail

lock_compat_root=${1:?lock-enabled compatibility root required}
lock_compat_bin=${2:?lock-enabled compatibility bin required}
lock_runtime=${3:?lock-enabled runtime package required}
disabled_compat_root=${4:?lock-disabled compatibility root required}
disabled_compat_bin=${5:?lock-disabled compatibility bin required}
standalone_disabled_ok=${6:?standalone lock-disabled evaluation result required}
standalone_enabled_ok=${7:?standalone lock-enabled evaluation result required}
integrated_off_off_ok=${8:?integrated pam-off/lock-off evaluation result required}
integrated_on_off_ok=${9:?integrated pam-on/lock-off evaluation result required}
integrated_off_on_ok=${10:?integrated pam-off/lock-on evaluation result required}
integrated_on_on_ok=${11:?integrated pam-on/lock-on evaluation result required}

registry_file="$lock_compat_root/shell/services/PluginRegistry.qml"
disabled_registry_file="$disabled_compat_root/shell/services/PluginRegistry.qml"
service_file="$lock_compat_root/shell/plugins/lock/Service.qml"

# Section 12: source packaging is conditional on the security capability,
# never on presentation features.
test -e "$lock_compat_root/shell/plugins/lock/Service.qml"
test -e "$lock_compat_root/shell/plugins/lock/LockView.qml"
test -e "$lock_compat_root/shell/plugins/lock/manifest.json"
test ! -e "$disabled_compat_root/shell/plugins/lock"

# Section 16/19: the stranded-lock helper is packaged and reachable through
# the shared compat dispatcher only when the security capability is on.
test -L "$lock_compat_bin/bin/omarchy-hyprland-session-locked"
test ! -e "$disabled_compat_bin/bin/omarchy-hyprland-session-locked"
test -L "$lock_runtime/bin/omarchy-hyprland-session-locked"

# Section 8/9: the managed-plugin override is always present (both builds)
# but only non-empty when the security capability is on.
grep -q 'omanixyManagedSecurityPlugins' "$registry_file"
grep -q '"omarchy.lock"' "$registry_file"
grep -q 'omanixyManagedSecurityPlugins: \[\]' "$disabled_registry_file"
grep -q 'managed by Omanixy/Nix configuration' "$registry_file"

# Section 13: fingerprint reachability is structurally impossible - the only
# code path that could ever flip fingerprintConfigured to true is removed,
# and the flag is forced false on every refresh.
if grep -q 'fingerprintCheckProc' "$service_file"; then
  printf '%s\n' 'patched Service.qml still declares fingerprintCheckProc' >&2
  exit 1
fi
grep -q 'root.fingerprintConfigured = false' "$service_file"
grep -q 'fingerprintPam' "$service_file"

# Section 15: WlSessionLock topology and the password PAM service name are
# preserved untouched by the fingerprint/DPMS patch.
grep -q 'WlSessionLock' "$service_file"
grep -q 'PamContext' "$service_file"
grep -q 'omarchy-lock-password' "$service_file"

# Section 16: the stranded-lock helper is invoked as direct argv, not a
# bash -c string.
grep -q 'command: \["omarchy-hyprland-session-locked"\]' "$service_file"
if grep -q 'bash", "-c", "omarchy-hyprland-session-locked' "$service_file"; then
  printf '%s\n' 'stranded-lock check still shells out via bash -c' >&2
  exit 1
fi

# Section 17: wake/blank are bounded Hyprland DPMS dispatches, not the
# keyboard-backlight/clamshell helpers.
grep -q 'hl.dsp.dpms({ action = \\"enable\\" })' "$service_file"
grep -q 'hl.dsp.dpms({ action = \\"disable\\" })' "$service_file"
if grep -q 'omarchy-system-wake\|omarchy-brightness-keyboard' "$service_file"; then
  printf '%s\n' 'patched Service.qml still references the keyboard-backlight/wake helpers' >&2
  exit 1
fi

# Section 20: hermetic fake-backend exit-code contract for the stranded-lock
# helper - 0 (still locked), 1 (unlocked/readable), 2 (indeterminate or a
# backend failure). This is deliberately exercised here, not through
# test/compat-adapters.sh, because omarchy-hyprland-session-locked is not
# registered in upstream/compatibility-contracts.json and compat-adapters.sh's
# record_case output is cross-checked against that ledger by
# test/compatibility-test-matrix.sh.
fake_bin=$(mktemp -d)
trap 'rm -rf "$fake_bin"' EXIT
# The Nix build sandbox has no /usr/bin/env, so the fixture's shebang must
# name an absolute bash path rather than relying on env(1) to find one.
printf '#!%s\n' "$(command -v bash)" >"$fake_bin/hyprctl"
cat >>"$fake_bin/hyprctl" <<'EOF'
case "$STRANDED_LOCK_FIXTURE" in
  locked) printf '%s\n' '[{"solitaryBlockedBy":["LOCK"]}]' ;;
  unlocked) printf '%s\n' '[{"solitaryBlockedBy":[]}]' ;;
  indeterminate) printf '%s\n' '[{"solitaryBlockedBy":["WORKSPACE"]}]' ;;
  malformed) printf '%s\n' 'not json' ;;
  fail) exit 1 ;;
esac
EOF
chmod +x "$fake_bin/hyprctl"

fixture_status() {
  local fixture=$1 status=0
  # The packaged executable is a writeShellApplication with inheritPath =
  # false, so it replaces rather than extends PATH; a bare PATH override here
  # would never reach it. OMANIXY_PROBE_BACKEND_PATH is compat-adapter.bash's
  # own hook for prepending a fake backend ahead of the wrapper's PATH.
  STRANDED_LOCK_FIXTURE="$fixture" OMANIXY_PROBE_BACKEND_PATH="$fake_bin" \
    "$lock_runtime/bin/omarchy-hyprland-session-locked" && status=0 || status=$?
  printf '%s\n' "$status"
}

test "$(fixture_status locked)" = 0
test "$(fixture_status unlocked)" = 1
test "$(fixture_status indeterminate)" = 2
test "$(fixture_status malformed)" = 2
test "$(fixture_status fail)" = 2

# Section 26: the 7-scenario NixOS + Home Manager integration matrix.
test "$standalone_disabled_ok" = true
test "$standalone_enabled_ok" = false
test "$integrated_off_off_ok" = true
test "$integrated_on_off_ok" = true
test "$integrated_off_on_ok" = false
test "$integrated_on_on_ok" = true

printf '%s\n' 'security lock checks passed'
