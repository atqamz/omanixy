#!/usr/bin/env bash
set -euo pipefail

activation=${1:?default activation script required}
disabled_activation=${2:?disabled activation script required}
font_default=${3:?default fontconfig fragment required}
font_override=${4:?override fontconfig fragment required}
font_package=${5:?default font package required}
override_font_package=${6:?override font package required}
default_background=${7:?default background required}
compatibility_root=${8:?compatibility root required}
disabled_compatibility_root=${9:?disabled compatibility root required}
font_provisioned=${10:?font provisioning result required}
fc_match=${11:?fc-match executable required}

test_root=$(mktemp -d)
trap 'chmod -R u+w "$test_root" 2>/dev/null || true; rm -rf "$test_root"' EXIT

run_activation() {
  local home=$1
  local script=$2
  mkdir -p "$home"
  HOME="$home" USER=omanixy-test XDG_RUNTIME_DIR="$home/runtime" \
    bash -c 'run() { "$@"; }; source "$1"' bash "$script"
}

run_activation "$test_root/default" "$activation"
background_file="$test_root/default/.local/state/omarchy/current/background"
test -L "$background_file"
test -f "$background_file"
test "$(readlink -f "$background_file")" = "$default_background"
test -f "$default_background"
test "$font_provisioned" = true
test -d "$font_package/share/fonts"
test -e "$compatibility_root/shell/plugins/background/Background.qml"
if grep -Eq 'omarchy-theme-(bg-switcher|bg-set|switcher|set)|MouseArea|openSelector|openThemeSwitcher' \
  "$compatibility_root/shell/plugins/background/Background.qml"; then
  exit 1
fi
for owner in swww hyprpaper caelestia; do
  test ! -e "$test_root/default/.config/systemd/user/$owner.service"
  test ! -e "$test_root/default/.config/systemd/user/$owner.timer"
done

user_background="$test_root/default/user-background.jpg"
cp "$default_background" "$user_background"
ln -sfn "$user_background" "$background_file"
run_activation "$test_root/default" "$activation"
test "$(readlink -f "$background_file")" = "$user_background"

ln -sfn /nix/store/omanixy-missing-background "$background_file"
run_activation "$test_root/default" "$activation"
test "$(readlink -f "$background_file")" = "$default_background"

run_activation "$test_root/disabled" "$disabled_activation"
test ! -e "$test_root/disabled/.local/state/omarchy/current/background"
jq -e '.disabledPlugins | index("omarchy.background") != null' \
  "$test_root/disabled/.config/omarchy/shell.json" >/dev/null
test -f "$disabled_compatibility_root/shell/plugins/background/Background.qml"
grep -Fq 'omarchy.background' "$disabled_compatibility_root/shell/services/PluginRegistry.qml"

export HOME="$test_root/default"
export XDG_CACHE_HOME="$test_root/fontconfig-cache"
font_conf="$test_root/fontconfig.conf"
printf '%s\n' '<fontconfig>' > "$font_conf"
printf '<dir>%s/share/fonts</dir>\n' "$font_package" >> "$font_conf"
printf '<include>%s</include>\n' "$font_default" >> "$font_conf"
printf '%s\n' '</fontconfig>' >> "$font_conf"
default_family=$(FONTCONFIG_FILE="$font_conf" "$fc_match" monospace -f '%{family}\n' | head -n 1)
test "$default_family" = 'JetBrainsMono Nerd Font,JetBrainsMono NF'

override_conf="$test_root/fontconfig-override.conf"
printf '%s\n' '<fontconfig>' > "$override_conf"
printf '<dir>%s/share/fonts</dir>\n' "$override_font_package" >> "$override_conf"
printf '<include>%s</include>\n' "$font_override" >> "$override_conf"
printf '%s\n' '</fontconfig>' >> "$override_conf"
override_family=$(FONTCONFIG_FILE="$override_conf" "$fc_match" monospace -f '%{family}\n' | head -n 1)
test "$override_family" = 'DejaVu Sans Mono'

printf '%s\n' 'presentation ownership checks passed'
