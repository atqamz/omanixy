#!/usr/bin/env bash
set -euo pipefail

disabled_activation=${1:?lock-disabled activation script required}
lock_activation=${2:?lock-enabled activation script required}
store_config=${3:?store-backed historical shell.json required}

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

run_activation_at() {
  local home=$1 activation=$2
  HOME="$home" USER=omanixy-test XDG_RUNTIME_DIR="$home/runtime" \
    bash -c 'run() { "$@"; }; source "$1"' bash "$activation"
}

# Section 27/28: 5-case shell.json regression matrix (A-E). Each case runs
# the identical starting shell.json through both the lock-disabled and the
# lock-enabled activation script and asserts the resulting shell.json is
# byte-identical - proving programs.omanixy.security.lock.enable never
# changes shell.json handling, which stays owned by the presentation
# feature model alone (security = { lock = ...; } is structurally separate).
assert_case() {
  local label=$1 setup=$2
  local disabled_home="$work/$label-disabled" lock_home="$work/$label-lock"
  mkdir -p "$disabled_home" "$lock_home"
  "$setup" "$disabled_home"
  "$setup" "$lock_home"
  run_activation_at "$disabled_home" "$disabled_activation"
  run_activation_at "$lock_home" "$lock_activation"
  cmp "$disabled_home/.config/omarchy/shell.json" "$lock_home/.config/omarchy/shell.json"
}

# Case A: no pre-existing shell.json - the default, freshly-seeded baseline.
setup_a() { :; }
assert_case a setup_a

# Establish the canonical seed content from case A's own lock-disabled run,
# to build the remaining fixtures without duplicating the module's private
# baseline-computation logic.
seed_shell_json="$work/a-disabled/.config/omarchy/shell.json"
reenabled_shell_json="$work/reenabled-shell.json"
jq 'del(.disabledPlugins[] | select(. == "omarchy.lock"))' "$seed_shell_json" >"$reenabled_shell_json"

# Case B: pre-existing shell.json is the canonical seed verbatim (omarchy.lock
# already disabled by default).
setup_b() {
  mkdir -p "$1/.config/omarchy"
  cp "$seed_shell_json" "$1/.config/omarchy/shell.json"
}
assert_case b setup_b

# Case C: pre-existing shell.json has omarchy.lock explicitly removed from
# disabledPlugins - the user has re-enabled the plugin themselves.
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

printf '%s\n' 'security lock shell.json regression matrix passed'
