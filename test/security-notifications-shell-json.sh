#!/usr/bin/env bash
set -euo pipefail

disabled_activation=${1:?notifications-disabled activation script required}
daemon_activation=${2:?notifications-daemon-enabled activation script required}
store_config=${3:?store-backed historical shell.json required}

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

run_activation_at() {
  local home=$1 activation=$2
  HOME="$home" USER=omanixy-test XDG_RUNTIME_DIR="$home/runtime" \
    bash -c 'run() { "$@"; }; source "$1"' bash "$activation"
}

# Layer 7 (notifications) mirror of test/security-idle-shell-json.sh's 5-case
# matrix (A-E). Each case runs the identical starting shell.json through
# both the daemon-disabled and the daemon-enabled activation script and
# asserts the resulting shell.json is byte-identical - proving
# programs.omanixy.security.notifications.daemon.enable never mutates
# shell.json, which stays owned by the presentation feature model alone.
assert_case() {
  local label=$1 setup=$2
  local disabled_home="$work/$label-disabled" daemon_home="$work/$label-daemon"
  mkdir -p "$disabled_home" "$daemon_home"
  "$setup" "$disabled_home"
  "$setup" "$daemon_home"
  run_activation_at "$disabled_home" "$disabled_activation"
  run_activation_at "$daemon_home" "$daemon_activation"
  cmp "$disabled_home/.config/omarchy/shell.json" "$daemon_home/.config/omarchy/shell.json"
}

# Case A: no pre-existing shell.json - the default, freshly-seeded baseline.
setup_a() { :; }
assert_case a setup_a

seed_shell_json="$work/a-disabled/.config/omarchy/shell.json"
reenabled_shell_json="$work/reenabled-shell.json"
jq 'del(.disabledPlugins[] | select(. == "omarchy.notifications"))' "$seed_shell_json" >"$reenabled_shell_json"

# Case B: pre-existing shell.json is the canonical seed verbatim
# (omarchy.notifications already disabled by default).
setup_b() {
  mkdir -p "$1/.config/omarchy"
  cp "$seed_shell_json" "$1/.config/omarchy/shell.json"
}
assert_case b setup_b

# Case C: pre-existing shell.json has omarchy.notifications explicitly
# removed from disabledPlugins - the user has re-enabled the plugin
# themselves via shell.json, which must not be revivable that way and must
# still resolve identically either way.
setup_c() {
  mkdir -p "$1/.config/omarchy"
  cp "$reenabled_shell_json" "$1/.config/omarchy/shell.json"
}
assert_case c setup_c

# Case D: pre-existing shell.json is a store-backed symlink to a historical
# (v1) config, which must migrate to the same result either way.
setup_d() {
  mkdir -p "$1/.config/omarchy"
  ln -s "$store_config" "$1/.config/omarchy/shell.json"
}
assert_case d setup_d

# Case E: pre-existing shell.json is a broken symlink to a missing store
# path, which must regenerate to the same materialized default either way.
setup_e() {
  mkdir -p "$1/.config/omarchy"
  ln -s /nix/store/omanixy-missing-shell-json-regression "$1/.config/omarchy/shell.json"
}
assert_case e setup_e

printf '%s\n' 'security notifications shell.json regression matrix passed'
