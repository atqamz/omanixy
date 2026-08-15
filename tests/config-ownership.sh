#!/usr/bin/env bash
set -euo pipefail

activation=${1:?Home Manager activation script required}
custom_activation=${2:?custom Home Manager activation script required}
home=${3:?Home Manager test home required}
custom_home=${4:?custom Home Manager test home required}
store_home=${5:?store-link test home required}
store_config=${6:?store-backed source config required}
mkdir -p "$home"
mkdir -p "$custom_home"
mkdir -p "$store_home/.config/omarchy"
trap 'rm -rf "$home" "$custom_home" "$store_home" "${home}-broken-store-link"' EXIT

run_activation_at() {
  activation_home=$1
  activation_script=$2
  HOME="$activation_home" \
    USER=omanixy-test \
    XDG_RUNTIME_DIR="$activation_home/runtime" \
    bash -c 'run() { "$@"; }; source "$1"' bash "$activation_script"
}

run_activation() {
  run_activation_at "$home" "$activation"
}

run_dry_activation() {
  HOME="${home_dry_run}" \
    USER=omanixy-test \
    XDG_RUNTIME_DIR="${home_dry_run}/runtime" \
    DRY_RUN=1 \
    bash -c 'run() { if [[ -v DRY_RUN ]]; then printf "dry-run: %s\n" "$*"; else "$@"; fi; }; source "$1"' bash "$activation"
}

run_activation

config_file="$home/.config/omarchy/shell.json"
theme_dir="$home/.local/state/omarchy/current/theme"
test -f "$config_file"
test -w "$config_file"
test ! -L "$config_file"
grep -Fq 'disabledPlugins' "$config_file"
test -d "$home/.config/omarchy/plugins"
test -f "$theme_dir/colors.toml"
test -f "$theme_dir/shell.toml"
test ! -L "$theme_dir"

printf '%s\n' '{"userOwned":true}' > "$config_file"
run_activation
grep -Fqx '{"userOwned":true}' "$config_file"

printf '%s\n' 'user theme' > "$theme_dir/user-state"
run_activation
grep -Fqx 'user theme' "$theme_dir/user-state"

HOME="$custom_home" USER=omanixy-test XDG_RUNTIME_DIR="$custom_home/runtime" \
  bash -c 'run() { "$@"; }; source "$1"' bash "$custom_activation"
grep -Fq '"custom":true' "$custom_home/.config/omarchy/shell.json"
for plugin in \
  omarchy.background \
  omarchy.battery \
  omarchy.clipboard \
  omarchy.idle \
  omarchy.lock \
  omarchy.media \
  omarchy.nightlight \
  omarchy.notifications \
  omarchy.polkit; do
  jq -e --arg plugin "$plugin" '.disabledPlugins | index($plugin) != null' "$custom_home/.config/omarchy/shell.json" >/dev/null
done

home_dry_run="${home}-dry-run"
mkdir -p "$home_dry_run"
trap 'rm -rf "$home" "$custom_home" "$store_home" "$home_dry_run" "${home}-broken-store-link"' EXIT
run_dry_activation
test ! -e "$home_dry_run/.config/omarchy/shell.json"
test ! -e "$home_dry_run/.local/state/omarchy/current/theme"

mkdir -p "$home_dry_run/.config/omarchy" "$home_dry_run/.local/state/omarchy/current/theme"
printf '%s\n' '{"dryRun":"preserve"}' > "$home_dry_run/.config/omarchy/shell.json"
printf '%s\n' 'dry-run theme' > "$home_dry_run/.local/state/omarchy/current/theme/user-state"
HOME="$home_dry_run" USER=omanixy-test XDG_RUNTIME_DIR="$home_dry_run/runtime" DRY_RUN=1 \
  bash -c 'run() { if [[ -v DRY_RUN ]]; then printf "dry-run: %s\n" "$*"; else "$@"; fi; }; source "$1"' bash "$activation"
grep -Fqx '{"dryRun":"preserve"}' "$home_dry_run/.config/omarchy/shell.json"
grep -Fqx 'dry-run theme' "$home_dry_run/.local/state/omarchy/current/theme/user-state"

broken_home="${home}-broken-store-link"
mkdir -p "$broken_home/.config/omarchy" "$broken_home/.local/state/omarchy/current"
ln -s /nix/store/omanixy-missing-shell.json "$broken_home/.config/omarchy/shell.json"
ln -s /nix/store/omanixy-missing-theme "$broken_home/.local/state/omarchy/current/theme"
run_activation_at "$broken_home" "$activation"
test -f "$broken_home/.config/omarchy/shell.json"
test ! -L "$broken_home/.config/omarchy/shell.json"
test -d "$broken_home/.local/state/omarchy/current/theme"
test ! -L "$broken_home/.local/state/omarchy/current/theme"

test ! -w "$store_config"
ln -s "$store_config" "$store_home/.config/omarchy/shell.json"
HOME="$store_home" USER=omanixy-test XDG_RUNTIME_DIR="$store_home/runtime" \
  bash -c 'run() { "$@"; }; source "$1"' bash "$activation"
store_file="$store_home/.config/omarchy/shell.json"
test ! -L "$store_file"
test -w "$store_file"
jq empty "$store_file"
printf '%s\n' '{"storeLinkMaterialized":true}' > "$store_file"
HOME="$store_home" USER=omanixy-test XDG_RUNTIME_DIR="$store_home/runtime" \
  bash -c 'run() { "$@"; }; source "$1"' bash "$activation"
grep -Fqx '{"storeLinkMaterialized":true}' "$store_file"

printf 'configuration ownership checks passed\n'
