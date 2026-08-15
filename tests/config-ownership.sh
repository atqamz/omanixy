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
trap 'rm -rf "$home" "$custom_home" "$store_home"' EXIT

run_activation() {
  HOME="$home" \
    USER=omanixy-test \
    XDG_RUNTIME_DIR="$home/runtime" \
    "$activation"
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

HOME="$custom_home" USER=omanixy-test XDG_RUNTIME_DIR="$custom_home/runtime" "$custom_activation"
grep -Fq '"custom":true' "$custom_home/.config/omarchy/shell.json"

test ! -w "$store_config"
ln -s "$store_config" "$store_home/.config/omarchy/shell.json"
HOME="$store_home" USER=omanixy-test XDG_RUNTIME_DIR="$store_home/runtime" "$activation"
store_file="$store_home/.config/omarchy/shell.json"
test ! -L "$store_file"
test -w "$store_file"
jq empty "$store_file"
printf '%s\n' '{"storeLinkMaterialized":true}' > "$store_file"
HOME="$store_home" USER=omanixy-test XDG_RUNTIME_DIR="$store_home/runtime" "$activation"
grep -Fqx '{"storeLinkMaterialized":true}' "$store_file"

printf 'configuration ownership checks passed\n'
