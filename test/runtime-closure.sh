#!/usr/bin/env bash
set -euo pipefail

runtime=${1:?runtime package path required}
closure_paths=${2:?closure store paths required}
quickshell_path=${3:?selected Quickshell store path required}
omarchy_path=${4:?selected Omarchy source store path required}
compatibility_root=${5:?compatibility root store path required}
compatibility_bin=${6:?compatibility bin store path required}
omarchy_revision=f0020448ca87329199de7cb12f2015ebc4a3e5e7
omarchy_short_revision=${omarchy_revision:0:12}
quickshell_revision=28771c7c74b42e20afca0b1b63980cb46515537c
quickshell_short_revision=${quickshell_revision:0:7}

unit_path() {
  readlink -f "$1"
}

test -x "$runtime/bin/omanixy-shell"
test -x "$runtime/bin/omanixy-shell-runtime"
test -x "$runtime/bin/quickshell"
test -x "$runtime/bin/inotifywait"
test -x "$runtime/bin/hyprctl"
runtime_source=$(sed -n 's/^export OMARCHY_PATH=//p' "$runtime/bin/omanixy-shell-runtime")
test -n "$runtime_source"
test "$runtime_source" = "$compatibility_root"
test -f "$runtime_source/shell/shell.qml"
test -f "$runtime_source/config/omarchy/shell.json"
test -f "$runtime_source/default/omarchy/omarchy-menu.jsonc"
test -L "$runtime_source/shell"
test -L "$runtime_source/config/omarchy/shell.json"
test ! -e "$runtime_source/config/hypr"
test ! -e "$runtime_source/bin"
test "$runtime_source" != "$runtime"
test -f "$runtime/share/omarchy-theme/colors.toml"
test -f "$runtime/share/omarchy-theme/shell.toml"

grep -Fxq "$runtime" "$closure_paths"
grep -Fxq "$quickshell_path" "$closure_paths"
grep -Fxq "$omarchy_path" "$closure_paths"
grep -Fxq "$compatibility_root" "$closure_paths"
grep -Fxq "$compatibility_bin" "$closure_paths"
! grep -E '/(pacman|yay|universe)([-/]|$)|/home/atqa([-/]|$)' "$closure_paths"
! grep -E '/pulseaudio([-/]|$)' "$closure_paths"

[[ $(basename "$omarchy_path") == *"$omarchy_short_revision"* ]]
[[ $(basename "$quickshell_path") == *"$quickshell_short_revision"* ]]
test -x "$runtime/bin/omarchy-network-qr"
test -x "$runtime/bin/omarchy-network-password"
test "$(unit_path "$runtime/bin/omarchy-network-qr")" = "$(unit_path "$compatibility_bin/bin/omarchy-network-qr")"
test "$(unit_path "$runtime/bin/omarchy-network-password")" = "$(unit_path "$compatibility_bin/bin/omarchy-network-password")"

printf '%s\n' 'runtime closure invariants passed'
