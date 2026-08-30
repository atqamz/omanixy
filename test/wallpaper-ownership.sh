#!/usr/bin/env bash
set -euo pipefail

activation=${1:?Home Manager activation script required}
runtime=${2:?Omanixy runtime package required}
default_background=${3:?default background required}
pinned_source=${4:?pinned source path required}
compatibility_root=${5:?compatibility root path required}

test_root=$(mktemp -d)
trap 'chmod -R u+w "$test_root" 2>/dev/null || true; rm -rf "$test_root"' EXIT

run_activation() {
  local home=$1
  local activation_script=${2:-$activation}
  mkdir -p "$home"
  HOME="$home" USER=omanixy-test XDG_RUNTIME_DIR="$home/runtime" \
    bash -c 'run() { "$@"; }; source "$1"' bash "$activation_script"
}

runtime_source=$(sed -n 's/^export OMARCHY_PATH=//p' "$runtime/bin/omanixy-shell-runtime")
test "$runtime_source" = "$compatibility_root"
test -f "$runtime_source/shell/plugins/background/Background.qml"
test -f "$runtime_source/default/omarchy/omarchy-menu.jsonc"
test -f "$default_background"

background_source="$pinned_source/shell/plugins/background/Background.qml"
background_runtime="$runtime_source/shell/plugins/background/Background.qml"
for helper in \
  omarchy-theme-bg-switcher \
  omarchy-theme-bg-set \
  omarchy-theme-switcher \
  omarchy-theme-set; do
  grep -Fq -- "$helper" "$background_source"
  if grep -Fq -- "$helper" "$background_runtime"; then
    printf '%s\n' "unsupported background helper is reachable: $helper" >&2
    exit 1
  fi
  if grep -Fq -- "$helper" "$runtime_source/default/omarchy/omarchy-menu.jsonc"; then
    printf '%s\n' "unsupported background helper is exposed in the safe menu: $helper" >&2
    exit 1
  fi
done
if grep -Eq 'MouseArea|openSelector|openThemeSwitcher' "$background_runtime"; then
  printf '%s\n' 'unsupported background interaction surface is reachable' >&2
  exit 1
fi

preseeded_home="$test_root/preseeded"
mkdir -p "$preseeded_home/.local/state/omarchy/current"
background_file="$preseeded_home/.local/state/omarchy/current/background"
user_background="$preseeded_home/user-chosen.jpg"
cp "$default_background" "$user_background"
ln -s "$user_background" "$background_file"
run_activation "$preseeded_home"
test -L "$background_file"
test -f "$background_file"
test "$(readlink -f "$background_file")" = "$user_background"

broken_activation="$test_root/broken-activation"
cp "$activation" "$broken_activation"
chmod u+w "$broken_activation"
sed -i \
  -e 's/if \[ ! -e "\$background_file" \]; then/if true; then/' \
  -e '0,/ln -s --/s//ln -sfn --/' \
  "$broken_activation"
broken_home="$test_root/broken"
mkdir -p "$broken_home/.local/state/omarchy/current"
broken_background="$broken_home/.local/state/omarchy/current/background"
broken_user_background="$broken_home/user-chosen.jpg"
cp "$default_background" "$broken_user_background"
ln -s "$broken_user_background" "$broken_background"
if run_activation "$broken_home" "$broken_activation" &&
  test "$(readlink -f "$broken_background")" = "$broken_user_background"; then
  printf '%s\n' 'wallpaper ownership check accepted a broken activation guard' >&2
  exit 1
fi

fresh_home="$test_root/fresh"
run_activation "$fresh_home"
fresh_background="$fresh_home/.local/state/omarchy/current/background"
for owner in caelestia hyprpaper mpvpaper swww swaybg; do
  for unit in service timer; do
    test ! -e "$fresh_home/.config/systemd/user/$owner.$unit"
  done
done
test -L "$fresh_background"
test -f "$fresh_background"
test "$(readlink -f "$fresh_background")" = "$default_background"

printf '%s\n' 'wallpaper ownership checks passed'
