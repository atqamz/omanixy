#!/usr/bin/env bash
set -euo pipefail

root=${1:?compatibility root path required}
runtime=${2:?runtime package path required}
node=${NODE:-node}

support="$root/shell/services/AppLibrarySupport.js"
test -f "$support"

"$node" - "$support" <<'NODE'
const assert = require("node:assert/strict")
const support = require(process.argv[2])

const userEntries = new Set(["org.example.User", "org.example.Space"])
assert.equal(support.isValidDesktopId("org.example.User"), true)
assert.equal(support.isValidDesktopId("../outside"), false)
assert.equal(support.isValidDesktopId(""), false)
assert.equal(support.canRemove("org.example.User", userEntries), true)
assert.equal(support.canRemove("org.example.System", userEntries), false)
assert.equal(support.canRemove("org.example.Missing", userEntries), false)
assert.equal(support.canRemove("org.example.Space.desktop", userEntries), true)
assert.equal(support.canRemove("org.example/Space", userEntries), false)
NODE

test -n "$runtime"
runtime_path=$(sed -n 's/^export PATH="\(.*\)"$/\1/p' "$runtime/bin/omanixy-shell-runtime")
test -n "$runtime_path"
test_root=$(mktemp -d)
trap 'rm -rf "$test_root"' EXIT
home="$test_root/home"
mkdir -p "$home/.local/share/applications" "$test_root/bin"
printf '%s\n' '[Desktop Entry]' > "$home/.local/share/applications/org.example.User.desktop"
cat > "$test_root/bin/update-desktop-database" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$test_root/bin/update-desktop-database"
sed -i "1c#!$(command -v bash)" "$test_root/bin/update-desktop-database"
PATH="$test_root/bin:$root/bin:$runtime_path" \
  HOME="$home" XDG_DATA_HOME="$home/.local/share" \
  "$root/bin/omarchy-remove-launcher-entry" org.example.User 'User app'
test ! -e "$home/.local/share/applications/org.example.User.desktop"
if PATH="$test_root/bin:$root/bin:$runtime_path" HOME="$home" XDG_DATA_HOME="$home/.local/share" \
  "$root/bin/omarchy-remove-launcher-entry" org.example.System 'System app'; then
  printf '%s\n' 'non-user launcher unexpectedly removed' >&2
  exit 1
fi

printf '%s\n' 'launcher delete contract passed'
