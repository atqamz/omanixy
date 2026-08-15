#!/usr/bin/env bash
set -euo pipefail

runtime=${1:?runtime package path required}
compatibility_root=${2:?compatibility root path required}
menu="$compatibility_root/default/omarchy/omarchy-menu.jsonc"
test_root=$(mktemp -d)
trap 'rm -rf "$test_root"' EXIT
normalized_menu="$test_root/menu.json"

test -f "$menu"
for helper in \
  omarchy-remove-launcher-entry \
  omarchy-menu-emoji-insert \
  omarchy-clipboard-open \
  omarchy-clipboard-paste-file \
  omarchy-clipboard-paste-text; do
  test -x "$compatibility_root/bin/$helper"
done
test ! -e "$compatibility_root/bin/omarchy-update"
app_library="$compatibility_root/shell/services/AppLibrary.qml"
grep -Fq 'Util.execDetached("uwsm-app -- gtk-launch ' "$app_library"
test "$(grep -Fc 'uwsm-app --' "$app_library")" -eq 1

python3 - "$menu" "$normalized_menu" <<'PY'
import json
import re
import sys

source = open(sys.argv[1], encoding="utf-8").read()
output = []
index = 0
in_string = False
escaped = False
in_line_comment = False
in_block_comment = False
while index < len(source):
    char = source[index]
    next_char = source[index + 1] if index + 1 < len(source) else ""
    if in_line_comment:
        if char == "\n":
            in_line_comment = False
            output.append(char)
        index += 1
        continue
    if in_block_comment:
        if char == "*" and next_char == "/":
            in_block_comment = False
            index += 2
        else:
            index += 1
        continue
    if in_string:
        output.append(char)
        if escaped:
            escaped = False
        elif char == "\\":
            escaped = True
        elif char == '"':
            in_string = False
        index += 1
        continue
    if char == '"':
        in_string = True
        output.append(char)
    elif char == "/" and next_char == "/":
        in_line_comment = True
        index += 1
    elif char == "/" and next_char == "*":
        in_block_comment = True
        index += 1
    else:
        output.append(char)
    index += 1

json_text = re.sub(r",(\s*[}\]])", r"\1", "".join(output))
with open(sys.argv[2], "w", encoding="utf-8") as destination:
    json.dump(json.loads(json_text), destination)
PY

jq -e '
  (keys | sort) == [
    "apps", "system", "system.logout", "system.reboot", "system.shutdown",
    "system.suspend", "trigger", "trigger.emoji", "trigger.screenshot"
  ]
  and .apps == {label: "Apps", provider: "apps"}
  and .trigger == {label: "Trigger"}
  and .system == {label: "System"}
  and .["trigger.emoji"] == {label: "Emoji", action: "omarchy-shell shell summon omarchy.emojis"}
  and .["trigger.screenshot"] == {label: "Screenshot", action: "omarchy-capture-screenshot"}
  and .["system.suspend"] == {label: "Suspend", action: "systemctl suspend"}
  and .["system.logout"] == {label: "Logout", action: "loginctl terminate-user \"$USER\""}
  and .["system.reboot"] == {label: "Reboot", action: "systemctl reboot"}
  and .["system.shutdown"] == {label: "Shutdown", action: "systemctl poweroff"}
  and ([.. | objects | select(has("when") or has("checked"))] | length) == 0
' "$normalized_menu" >/dev/null

for forbidden in omarchy-update pacman yay paru omarchy-theme omarchy-pkg omarchy-lock omarchy-polkit; do
  jq -e --arg forbidden "$forbidden" \
    '[.. | objects | .action? | strings | select(test("(^|[^[:alnum:]_-])" + $forbidden + "([^[:alnum:]_-]|$)"))] | length == 0' \
    "$normalized_menu" >/dev/null
done

runtime_path=$(sed -n 's/^export PATH="\(.*\)"$/\1/p' "$runtime/bin/omanixy-shell-runtime")
test -n "$runtime_path"

while IFS= read -r command; do
  while IFS= read -r helper; do
    helper_path=$(PATH="$runtime_path" command -v "$helper")
    test -x "$helper_path"
  done < <(grep -oE 'omarchy-[a-z0-9][a-z0-9-]*' <<<"$command" | sort -u)
done < <(jq -r '.. | objects | .action?, .when?, .checked?, .provider? | strings' "$normalized_menu")

for executable in systemctl loginctl; do
  PATH="$runtime_path" command -v "$executable" >/dev/null
done

printf '%s\n' 'safe menu contract passed'
