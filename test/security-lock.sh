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
common_bash=${12:?adapters/common.bash source required}
lock_bash=${13:?adapters/lock.bash source required}

registry_file="$lock_compat_root/shell/services/PluginRegistry.qml"
disabled_registry_file="$disabled_compat_root/shell/services/PluginRegistry.qml"
service_file="$lock_compat_root/shell/plugins/lock/Service.qml"

test -e "$lock_compat_root/shell/plugins/lock/Service.qml"
test -e "$lock_compat_root/shell/plugins/lock/LockView.qml"
test -e "$lock_compat_root/shell/plugins/lock/manifest.json"
test ! -e "$disabled_compat_root/shell/plugins/lock"

test -L "$lock_compat_bin/bin/omarchy-hyprland-session-locked"
test ! -e "$disabled_compat_bin/bin/omarchy-hyprland-session-locked"
test -L "$lock_runtime/bin/omarchy-hyprland-session-locked"

grep -q 'omanixyManagedSecurityPlugins' "$registry_file"
grep -q '"omarchy.lock"' "$registry_file"
grep -q 'omanixyManagedSecurityPlugins: \[\]' "$disabled_registry_file"
grep -q 'managed by Omanixy/Nix configuration' "$registry_file"

for token in \
  fingerprintCheckProc fingerprintPam fingerprintRetryTimer fingerprintAuthenticating \
  startFingerprint handleFingerprintFinished fprintd-list fprintd omarchy-lock-fingerprint \
  ; do
  if grep -Fq "$token" "$service_file"; then
    printf 'patched Service.qml still references %s\n' "$token" >&2
    exit 1
  fi
done
grep -q 'root.fingerprintConfigured = false' "$service_file"
if grep -q 'fingerprintConfigured = true' "$service_file"; then
  printf '%s\n' 'patched Service.qml can still assign fingerprintConfigured = true' >&2
  exit 1
fi
test "$(grep -c 'PamContext {' "$service_file")" = 1

grep -q 'WlSessionLock' "$service_file"
grep -q 'PamContext' "$service_file"
grep -q 'omarchy-lock-password' "$service_file"

grep -q 'command: \["omarchy-hyprland-session-locked"\]' "$service_file"
if grep -q 'bash", "-c", "omarchy-hyprland-session-locked' "$service_file"; then
  printf '%s\n' 'stranded-lock check still shells out via bash -c' >&2
  exit 1
fi

grep -Fq 'command: ["timeout", "--kill-after=1s", "3s", "hyprctl", "dispatch", "hl.dsp.dpms({ action = \"enable\" })"]' "$service_file"
grep -Fq 'command: ["timeout", "--kill-after=1s", "3s", "hyprctl", "dispatch", "hl.dsp.dpms({ action = \"disable\" })"]' "$service_file"
if grep -q 'omarchy-system-wake\|omarchy-brightness-keyboard\|omarchy-hyprland-monitor-clamshell' "$service_file"; then
  printf '%s\n' 'patched Service.qml still references the keyboard-backlight/wake/clamshell helpers' >&2
  exit 1
fi
if grep -q 'bash", "-c", "omarchy-system-wake\|bash", "-c", "omarchy-brightness' "$service_file"; then
  printf '%s\n' 'wake/blank DPMS dispatch still shells out via bash -c' >&2
  exit 1
fi

dpms_fake_bin=$(mktemp -d)
trap 'rm -rf "$dpms_fake_bin"' EXIT
printf '#!%s\n' "$(command -v bash)" >"$dpms_fake_bin/hyprctl"
printf '%s\n' 'sleep 30' >>"$dpms_fake_bin/hyprctl"
chmod +x "$dpms_fake_bin/hyprctl"

dpms_start=$SECONDS
dpms_status=0
timeout --kill-after=1s 3s "$dpms_fake_bin/hyprctl" dispatch 'hl.dsp.dpms({ action = "enable" })' || dpms_status=$?
dpms_elapsed=$((SECONDS - dpms_start))

test "$dpms_status" -ne 0
case $dpms_status in
  124 | 137 | 143) : ;;
  *)
    printf 'unexpected exit status from bounded DPMS dispatch: %s\n' "$dpms_status" >&2
    exit 1
    ;;
esac
test "$dpms_elapsed" -le 10

if pgrep -f "$dpms_fake_bin/hyprctl" >/dev/null 2>&1; then
  printf '%s\n' 'hanging fake hyprctl backend survived the DPMS timeout bound' >&2
  exit 1
fi

fake_bin=$(mktemp -d)
trap 'rm -rf "$fake_bin" "$dpms_fake_bin"' EXIT
printf '#!%s\n' "$(command -v bash)" >"$fake_bin/hyprctl"
cat >>"$fake_bin/hyprctl" <<'EOF'
case "$STRANDED_LOCK_FIXTURE" in
  locked) printf '%s\n' '[{"solitaryBlockedBy":["LOCK"]}]' ;;
  unlocked) printf '%s\n' '[{"solitaryBlockedBy":[]}]' ;;
  indeterminate) printf '%s\n' '[{"solitaryBlockedBy":["WORKSPACE"]}]' ;;
  malformed) printf '%s\n' 'not json' ;;
  empty) printf '' ;;
  json-null) printf '%s\n' 'null' ;;
  json-object) printf '%s\n' '{"solitaryBlockedBy":["LOCK"]}' ;;
  hang) sleep 30 ;;
  fail) exit 1 ;;
esac
EOF
chmod +x "$fake_bin/hyprctl"

fixture_status() {
  local fixture=$1 status=0
  shift
  STRANDED_LOCK_FIXTURE="$fixture" OMANIXY_PROBE_BACKEND_PATH="$fake_bin" \
    "$lock_runtime/bin/omarchy-hyprland-session-locked" "$@" && status=0 || status=$?
  printf '%s\n' "$status"
}

test "$(fixture_status locked)" = 0
test "$(fixture_status unlocked)" = 1
test "$(fixture_status indeterminate)" = 2
test "$(fixture_status malformed)" = 2
test "$(fixture_status empty)" = 2
test "$(fixture_status json-null)" = 2
test "$(fixture_status json-object)" = 2
test "$(fixture_status fail)" = 2
test "$(fixture_status hang)" = 2
test "$(fixture_status locked extra-argument)" = 2

coreutils_bin=$(dirname "$(command -v timeout)")

domain_status() {
  local path=$1 status=0
  (
    PATH="$path"
    HOME=$(mktemp -d)
    # shellcheck disable=SC1090
    source "$common_bash"
    # shellcheck disable=SC1090
    source "$lock_bash"
    hyprland_session_locked
  ) && status=0 || status=$?
  printf '%s\n' "$status"
}

test "$(domain_status "$coreutils_bin")" = 2
test "$(domain_status "$fake_bin:$coreutils_bin")" = 2

test "$standalone_disabled_ok" = true
test "$standalone_enabled_ok" = false
test "$integrated_off_off_ok" = true
test "$integrated_on_off_ok" = true
test "$integrated_off_on_ok" = false
test "$integrated_on_on_ok" = true

printf '%s\n' 'security lock checks passed'
