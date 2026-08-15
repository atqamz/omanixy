#!/usr/bin/env bash
set -euo pipefail

runtime=${1:?runtime package path required}
compatibility_root=${2:?compatibility root path required}
menu="$compatibility_root/default/omarchy/omarchy-menu.jsonc"

test -f "$menu"
test ! -e "$compatibility_root/bin"

for forbidden in omarchy-update pacman yay paru omarchy-theme omarchy-pkg omarchy-lock omarchy-polkit; do
  ! grep -Fq "$forbidden" "$menu"
done

runtime_path=$(sed -n 's/^export PATH="\(.*\)"$/\1/p' "$runtime/bin/omanixy-shell-runtime")
test -n "$runtime_path"

while IFS= read -r command; do
  while IFS= read -r helper; do
    helper_path=$(PATH="$runtime_path" command -v "$helper")
    test -x "$helper_path"
  done < <(grep -oE 'omarchy-[a-z0-9][a-z0-9-]*' <<<"$command" | sort -u)
done < <(jq -r '.. | objects | .action?, .when?, .checked?, .provider? | strings' "$menu")

for executable in systemctl loginctl; do
  PATH="$runtime_path" command -v "$executable" >/dev/null
done

printf '%s\n' 'safe menu contract passed'
