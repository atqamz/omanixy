#!/usr/bin/env bash
set -euo pipefail

activation=${1:?Home Manager activation script required}
custom_activation=${2:?custom Home Manager activation script required}
home=${3:?Home Manager test home required}
custom_home=${4:?custom Home Manager test home required}
store_home=${5:?store-link test home required}
store_config=${6:?store-backed source config required}
malformed_store_config=${7:?malformed store-backed source config required}
historical_baseline=${8:?historical issue #2 baseline required}
mkdir -p "$home"
mkdir -p "$custom_home"
mkdir -p "$store_home/.config/omarchy"
malformed_store_home="${home}-malformed-store-link"
trap 'rm -rf "$home" "$custom_home" "$store_home" "${home}-broken-store-link" "$malformed_store_home"' EXIT

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

migration_home="${home}-migration"
custom_migration_home="${home}-custom-migration"
mkdir -p "$migration_home/.config/omarchy" "$custom_migration_home/.config/omarchy"
trap 'rm -rf "$home" "$custom_home" "$store_home" "$migration_home" "$custom_migration_home" "${home}-broken-store-link" "$malformed_store_home"' EXIT
cp "$historical_baseline" "$migration_home/.config/omarchy/shell.json"
run_activation_at "$migration_home" "$activation"
jq -e '.version == 1 and .omanixyBaselineVersion == 2 and .bar.layout.right[-1].id == "omarchy.power"' \
  "$migration_home/.config/omarchy/shell.json" >/dev/null
cp "$migration_home/.config/omarchy/shell.json" "$migration_home/after-first"
run_activation_at "$migration_home" "$activation"
cmp "$migration_home/after-first" "$migration_home/.config/omarchy/shell.json"
jq '. + {customized: true}' "$historical_baseline" > "$custom_migration_home/.config/omarchy/shell.json"
cp "$custom_migration_home/.config/omarchy/shell.json" "$custom_migration_home/before"
run_activation_at "$custom_migration_home" "$activation"
cmp "$custom_migration_home/before" "$custom_migration_home/.config/omarchy/shell.json"

formatted_migration_home="${home}-formatted-migration"
mkdir -p "$formatted_migration_home/.config/omarchy"
jq -S . "$historical_baseline" | sed '1s/{/{\n/' > "$formatted_migration_home/.config/omarchy/shell.json"
run_activation_at "$formatted_migration_home" "$activation"
jq -e '.omanixyBaselineVersion == 2 and .bar.layout.center[1].id == "omarchy.weather"' \
  "$formatted_migration_home/.config/omarchy/shell.json" >/dev/null

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
  omarchy.active-window \
  omarchy.agents \
  omarchy.background \
  omarchy.battery \
  omarchy.dev-gallery \
  omarchy.disk-speedtest \
  omarchy.dropbox \
  omarchy.idle \
  omarchy.image-picker \
  omarchy.indicators \
  omarchy.keyboard-layout \
  omarchy.lock \
  omarchy.microphone \
  omarchy.nightlight \
  omarchy.notifications \
  omarchy.polkit \
  omarchy.reminders \
  omarchy.system-update \
  omarchy.tailscale; do
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
test "$(stat -c '%a' "$store_file")" = 600
for plugin in \
  omarchy.active-window \
  omarchy.agents \
  omarchy.background \
  omarchy.battery \
  omarchy.dev-gallery \
  omarchy.disk-speedtest \
  omarchy.dropbox \
  omarchy.idle \
  omarchy.image-picker \
  omarchy.indicators \
  omarchy.keyboard-layout \
  omarchy.lock \
  omarchy.microphone \
  omarchy.nightlight \
  omarchy.notifications \
  omarchy.polkit \
  omarchy.reminders \
  omarchy.system-update \
  omarchy.tailscale; do
  jq -e --arg plugin "$plugin" '.disabledPlugins | index($plugin) != null' "$store_file" >/dev/null
done
jq -e '
  .version == 1
  and .omanixyBaselineVersion == 2
  and .bar.layout.left[0].id == "omarchy.menu"
  and .bar.layout.center[1].id == "omarchy.weather"
' "$store_file" >/dev/null
printf '%s\n' '{"storeLinkMaterialized":true}' > "$store_file"
HOME="$store_home" USER=omanixy-test XDG_RUNTIME_DIR="$store_home/runtime" \
  bash -c 'run() { "$@"; }; source "$1"' bash "$activation"
grep -Fqx '{"storeLinkMaterialized":true}' "$store_file"

mkdir -p "$malformed_store_home/.config/omarchy"
ln -s "$malformed_store_config" "$malformed_store_home/.config/omarchy/shell.json"
malformed_status=0
HOME="$malformed_store_home" USER=omanixy-test XDG_RUNTIME_DIR="$malformed_store_home/runtime" \
  bash -c 'run() { "$@"; }; source "$1"' bash "$activation" || malformed_status=$?
test "$malformed_status" -ne 0
test -L "$malformed_store_home/.config/omarchy/shell.json"
test "$(readlink "$malformed_store_home/.config/omarchy/shell.json")" = "$malformed_store_config"
grep -Fqx '{"disabledPlugins":' "$malformed_store_config"
if compgen -G "$malformed_store_home/.config/omarchy/shell.json.omanixy.*" >/dev/null; then
  exit 1
fi

printf 'configuration ownership checks passed\n'
