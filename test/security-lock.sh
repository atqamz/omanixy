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

# Finding 3: fingerprint reachability is not just probed-away, it is removed -
# no fingerprint PamContext, no retry timer, no startFingerprint()/
# handleFingerprintFinished(), no fprintd probe, and no filesystem probe for
# the omarchy-lock-fingerprint PAM service. fingerprintConfigured is retained
# only as a permanently-false property (LockView's icon binding and the IPC
# status field read it), and no code path may ever assign it true.
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
# Exactly one PamContext (password) remains.
test "$(grep -c 'PamContext {' "$service_file")" = 1

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

# Finding 1: wake/blank are bounded Hyprland DPMS dispatches - statically
# assert the exact patched argv (direct argv, no bash -c), not just a grep
# for the word "timeout".
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

# Finding 1: hermetic execution fixture - drive the exact patched argv shape
# against a fake hyprctl that sleeps well past the 3s bound and prove it is
# actually terminated, not just that the word "timeout" appears in the source.
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
# The bound is 3s + a 1s kill-after grace period; give generous slack for a
# loaded build sandbox while still proving the 30s sleep never ran to completion.
test "$dpms_elapsed" -le 10

if pgrep -f "$dpms_fake_bin/hyprctl" >/dev/null 2>&1; then
  printf '%s\n' 'hanging fake hyprctl backend survived the DPMS timeout bound' >&2
  exit 1
fi

# Section 20/Finding 2: hermetic fake-backend exit-code contract for the
# stranded-lock helper - 0 (still locked), 1 (unlocked/readable), 2
# (indeterminate or any backend failure). This is deliberately exercised
# here, not through test/compat-adapters.sh, because
# omarchy-hyprland-session-locked is not registered in
# upstream/compatibility-contracts.json and compat-adapters.sh's
# record_case output is cross-checked against that ledger by
# test/compatibility-test-matrix.sh.
fake_bin=$(mktemp -d)
trap 'rm -rf "$fake_bin" "$dpms_fake_bin"' EXIT
# The Nix build sandbox has no /usr/bin/env, so the fixture's shebang must
# name an absolute bash path rather than relying on env(1) to find one.
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
  # The packaged executable is a writeShellApplication with inheritPath =
  # false, so it replaces rather than extends PATH; a bare PATH override here
  # would never reach it. OMANIXY_PROBE_BACKEND_PATH is compat-adapter.bash's
  # own hook for prepending a fake backend ahead of the wrapper's PATH.
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
# Extra CLI argument: the packaged entrypoint's externally visible contract
# rejects it with exit 2, same as any other malformed invocation.
test "$(fixture_status locked extra-argument)" = 2

# Finding 2: hyprctl/jq missing from PATH entirely cannot be reproduced
# against the packaged entrypoint - writeShellApplication's inheritPath =
# false bakes core-runtime's hyprland+jq into its PATH regardless of
# OMANIXY_PROBE_BACKEND_PATH, which only prepends. Exercise the domain
# function directly instead, with a PATH that genuinely does not resolve
# the backend, to prove need()'s exit-127 default never leaks through this
# call site.
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

test "$(domain_status "$coreutils_bin")" = 2 # hyprctl absent
test "$(domain_status "$fake_bin:$coreutils_bin")" = 2 # jq absent

# Section 26: the 7-scenario NixOS + Home Manager integration matrix.
test "$standalone_disabled_ok" = true
test "$standalone_enabled_ok" = false
test "$integrated_off_off_ok" = true
test "$integrated_on_off_ok" = true
test "$integrated_off_on_ok" = false
test "$integrated_on_on_ok" = true

printf '%s\n' 'security lock checks passed'
