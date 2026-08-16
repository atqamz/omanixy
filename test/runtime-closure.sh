#!/usr/bin/env bash
set -euo pipefail

runtime=${1:?runtime package path required}
closure_paths=${2:?closure store paths required}
quickshell_path=${3:?selected Quickshell store path required}
omarchy_path=${4:?selected Omarchy source store path required}
compatibility_root=${5:?compatibility root store path required}
compatibility_bin=${6:?compatibility bin store path required}
manifest=${7:?compatibility manifest path required}
omarchy_revision=$(jq -er '.pins.omarchy' "$manifest")
omarchy_short_revision=${omarchy_revision:0:12}
quickshell_revision=$(jq -er '.pins.quickshell' "$manifest")
quickshell_short_revision=${quickshell_revision:0:7}

unit_path() {
  readlink -f "$1"
}

test -x "$runtime/bin/omanixy-shell"
test -x "$runtime/bin/omanixy-shell-runtime"
test -x "$runtime/bin/quickshell"
test -x "$runtime/bin/inotifywait"
test -x "$runtime/bin/hyprctl"
runtime_path=$(sed -n 's/^export PATH="\(.*\)"$/\1/p' "$runtime/bin/omanixy-shell-runtime")
test -n "$runtime_path"
PATH="$runtime_path" command -v pkill >/dev/null
PATH="$runtime_path" command -v update-desktop-database >/dev/null
PATH="$runtime_path" command -v wpctl >/dev/null
PATH="$runtime_path" command -v wl-paste >/dev/null
PATH="$runtime_path" command -v omanixy-compat-adapter >/dev/null
uwsm_app=$(PATH="$runtime_path" command -v uwsm-app)
uwsm=$(PATH="$runtime_path" command -v uwsm)
[[ $uwsm_app == *uwsm-*/bin/uwsm-app ]]
[[ $uwsm == *uwsm-*/bin/uwsm ]]
runtime_source=$(sed -n 's/^export OMARCHY_PATH=//p' "$runtime/bin/omanixy-shell-runtime")
test -n "$runtime_source"
test "$runtime_source" = "$compatibility_root"
test -f "$runtime_source/shell/shell.qml"
test -f "$runtime_source/config/omarchy/shell.json"
test -f "$runtime_source/default/omarchy/omarchy-menu.jsonc"
test -d "$runtime_source/shell"
test ! -L "$runtime_source/shell"
test ! -L "$runtime_source/config/omarchy/shell.json"
test ! -e "$runtime_source/shell/plugins/agents"
test ! -e "$runtime_source/shell/plugins/background"
test ! -e "$runtime_source/shell/plugins/lock"
test ! -e "$runtime_source/shell/plugins/notifications"
test ! -e "$runtime_source/shell/plugins/panels/dropbox"
test ! -e "$runtime_source/shell/plugins/panels/tailscale"
test ! -e "$runtime_source/shell/plugins/panels/speedtest"
test ! -e "$runtime_source/shell/Ui/SpeedTestOverlay.qml"
test ! -e "$runtime_source/shell/plugins/bar/widgets/SystemUpdate.qml"
jq -e '
  .version == 1
  and .omanixyBaselineVersion == 2
  and .bar.layout.left[0].id == "omarchy.menu"
  and .bar.layout.center[0].id == "omarchy.clock"
  and .bar.layout.right[-1].id == "omarchy.power"
  and (.disabledPlugins | index("omarchy.system-update") != null)
' "$runtime_source/config/omarchy/shell.json" >/dev/null
test ! -e "$runtime_source/config/hypr"
diff -u \
  <(find "$runtime_source/bin" -mindepth 1 -maxdepth 1 -type f -printf '%f\n' | sort) \
  <(find "$compatibility_bin/bin" -mindepth 1 -maxdepth 1 -type l -printf '%f\n' | sort)
test -x "$runtime_source/bin/omarchy-menu-emoji-insert"
test -x "$runtime_source/bin/omarchy-clipboard-open"
test ! -e "$runtime_source/bin/omarchy-update"
test "$runtime_source" != "$runtime"
test -f "$runtime/share/omarchy-theme/colors.toml"
test -f "$runtime/share/omarchy-theme/shell.toml"

grep -Fxq "$runtime" "$closure_paths"
grep -Fxq "$quickshell_path" "$closure_paths"
if grep -Fxq "$omarchy_path" "$closure_paths"; then
  exit 1
fi
grep -Fxq "$compatibility_root" "$closure_paths"
grep -Fxq "$compatibility_bin" "$closure_paths"
if grep -E '/(pacman|yay|universe)([-/]|$)|/home/atqa([-/]|$)' "$closure_paths"; then
  exit 1
fi
grep -E '/[^/]*-(lib)?pulseaudio([-/]|$)' "$closure_paths"

[[ $(basename "$omarchy_path") == *"$omarchy_short_revision"* ]]
[[ $(basename "$quickshell_path") == *"$quickshell_short_revision"* ]]
test -x "$runtime/bin/omarchy-network-qr"
test -x "$runtime/bin/omarchy-network-password"
test "$(unit_path "$runtime/bin/omarchy-network-qr")" = "$(unit_path "$compatibility_bin/bin/omarchy-network-qr")"
test "$(unit_path "$runtime/bin/omarchy-network-password")" = "$(unit_path "$compatibility_bin/bin/omarchy-network-password")"
test -f "$runtime_source/shell/services/AppLibrarySupport.js"

printf '%s\n' 'runtime closure invariants passed'
