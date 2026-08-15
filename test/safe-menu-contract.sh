#!/usr/bin/env bash
set -euo pipefail

runtime=${1:?runtime package path required}
compatibility_root=${2:?compatibility root path required}
menu="$compatibility_root/default/omarchy/omarchy-menu.jsonc"
test_root=$(mktemp -d)
trap 'rm -rf "$test_root"' EXIT
normalized_menu="$test_root/menu.json"

test -f "$menu"
test ! -e "$compatibility_root/bin"

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
