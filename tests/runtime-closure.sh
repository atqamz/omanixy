#!/usr/bin/env bash
set -euo pipefail

runtime=${1:?runtime package path required}
closure_paths=${2:?closure store paths required}
quickshell_path=${3:?selected Quickshell store path required}
omarchy_path=${4:?selected Omarchy source store path required}
omarchy_revision=f0020448ca87329199de7cb12f2015ebc4a3e5e7
omarchy_short_revision=${omarchy_revision:0:12}
quickshell_revision=28771c7c74b42e20afca0b1b63980cb46515537c
quickshell_short_revision=${quickshell_revision:0:7}

test -x "$runtime/bin/omanixy-shell"
test -x "$runtime/bin/omanixy-shell-runtime"
test -x "$runtime/bin/quickshell"
test -x "$runtime/bin/inotifywait"
test -x "$runtime/bin/hyprctl"
runtime_source=$(sed -n 's/^export OMARCHY_PATH=//p' "$runtime/bin/omanixy-shell-runtime")
test -n "$runtime_source"
test "$runtime_source" = "$omarchy_path"
test -f "$runtime_source/shell/shell.qml"
test -f "$runtime_source/config/omarchy/shell.json"
test "$runtime_source" != "$runtime"
test -f "$runtime/share/omarchy-theme/colors.toml"
test -f "$runtime/share/omarchy-theme/shell.toml"

grep -Fxq "$runtime" "$closure_paths"
grep -Fxq "$quickshell_path" "$closure_paths"
grep -Fxq "$omarchy_path" "$closure_paths"
! grep -E '/(pacman|yay|universe)([-/]|$)|/home/atqa([-/]|$)' "$closure_paths"

runtime_text=$(cat "$runtime/bin/omanixy-shell" "$runtime/bin/omanixy-shell-runtime")
! grep -E '/home/atqa|atqamz/universe|pacman|yay' <<<"$runtime_text"
! grep -Fq ':$PATH' <<<"$runtime_text"
grep -Fq "$omarchy_short_revision" <<<"$runtime_text"
grep -Fq "$quickshell_short_revision" <<<"$runtime_text"

printf '%s\n' 'runtime closure invariants passed'
