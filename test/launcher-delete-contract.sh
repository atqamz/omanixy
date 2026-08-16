#!/usr/bin/env bash
set -euo pipefail

root=${1:?compatibility root path required}
runtime=${2:?runtime package path required}
repo=${3:?repository path required}

test -n "$runtime"
runtime_path=$(sed -n 's/^export PATH="\(.*\)"$/\1/p' "$runtime/bin/omanixy-shell-runtime")
test -n "$runtime_path"
test_root=$(mktemp -d)
trap 'rm -rf "$test_root"' EXIT
home="$test_root/home"
runtime_dir="$test_root/runtime"
mkdir -p "$home/.local/share/applications" "$test_root/bin"
mkdir -p "$runtime_dir"
ln -s "$root/shell" "$test_root/qs"
printf '%s\n' '[Desktop Entry]' > "$home/.local/share/applications/org.example.User.desktop"
cat > "$test_root/bin/update-desktop-database" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$test_root/bin/update-desktop-database"
sed -i "1c#!$(command -v bash)" "$test_root/bin/update-desktop-database"
PATH="$test_root/bin:$root/bin:$runtime_path" \
  HOME="$home" XDG_DATA_HOME="$home/.local/share" \
  XDG_RUNTIME_DIR="$runtime_dir" \
  QT_QPA_PLATFORM=offscreen \
  QML2_IMPORT_PATH="$test_root" \
  "$root/bin/omarchy-remove-launcher-entry" org.example.User 'User app'
test ! -e "$home/.local/share/applications/org.example.User.desktop"
if PATH="$test_root/bin:$root/bin:$runtime_path" HOME="$home" XDG_DATA_HOME="$home/.local/share" \
  "$root/bin/omarchy-remove-launcher-entry" org.example.System 'System app'; then
  printf '%s\n' 'non-user launcher unexpectedly removed' >&2
  exit 1
fi

node - "$repo/packages/omanixy-shell/MenuDeleteSupport.js" <<'NODE'
const assert = require("node:assert/strict")
const support = require(process.argv[2])
const userLibrary = { canRemove: id => id === "org.example.User" }
assert.equal(support.canRequestDelete({kind: "app", appId: "org.example.User"}, userLibrary), true)
assert.equal(support.canRequestDelete({kind: "app", appId: "org.example.System"}, userLibrary), false)
assert.equal(support.canRequestDelete({kind: "action", appId: "org.example.User"}, userLibrary), false)
assert.equal(support.canRequestDelete({kind: "app", appId: "../escape"}, userLibrary), false)
assert.equal(support.canRequestDelete(null, userLibrary), false)
NODE

printf '%s\n' 'launcher delete contract passed'
