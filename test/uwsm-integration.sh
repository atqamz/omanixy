#!/usr/bin/env bash
set -euo pipefail

runtime=${1:?runtime package path required}
compatibility_root=${2:?compatibility root path required}
node=${NODE:-node}
runtime_path=$(sed -n 's/^export PATH="\(.*\)"$/\1/p' "$runtime/bin/omanixy-shell-runtime")
test -n "$runtime_path"

uwsm_app=$(PATH="$runtime_path" command -v uwsm-app)
test -n "$uwsm_app"
case "$uwsm_app" in
  /nix/store/*-uwsm-*/bin/uwsm-app) ;;
  *) printf 'selected UWSM executable is not the packaged binary: %s\n' "$uwsm_app" >&2; exit 1 ;;
esac
uwsm_help_status=0
uwsm_help=$(PATH="$runtime_path" uwsm-app --help 2>&1) || uwsm_help_status=$?
if ((uwsm_help_status == 0)); then
  grep -Fq 'usage: uwsm app' <<<"$uwsm_help"
else
  grep -Fq 'DBUS_SESSION_BUS_ADDRESS' <<<"$uwsm_help"
fi

test_root=$(mktemp -d)
trap 'rm -rf "$test_root"' EXIT
fixture_bin="$test_root/bin"
data_home="$test_root/data"
mkdir -p "$fixture_bin" "$data_home/applications"
cat > "$fixture_bin/record-launch" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" > "$LAUNCH_LOG"
EOF
chmod +x "$fixture_bin/record-launch"
sed -i "1c#!$(command -v bash)" "$fixture_bin/record-launch"
cat > "$data_home/applications/org.example.User.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Omanixy test app
Exec=$fixture_bin/record-launch
EOF
cat > "$fixture_bin/systemctl" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$fixture_bin/systemctl"
sed -i "1c#!$(command -v bash)" "$fixture_bin/systemctl"
cat > "$fixture_bin/sleep" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$fixture_bin/sleep"
sed -i "1c#!$(command -v bash)" "$fixture_bin/sleep"
for utility in flock notify-send; do
  printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "$fixture_bin/$utility"
  chmod +x "$fixture_bin/$utility"
  sed -i "1c#!$(command -v bash)" "$fixture_bin/$utility"
done
support="$compatibility_root/shell/services/AppLibrarySupport.js"
launch_command=$("$node" - "$support" <<'NODE'
const support = require(process.argv[2])
process.stdout.write(support.launchCommand("org.example.User"))
NODE
)
test "$launch_command" = "uwsm-app -- gtk-launch 'org.example.User.desktop'"
launch_status=0
LAUNCH_LOG="$test_root/launch.log" \
  XDG_DATA_HOME="$data_home" \
  PATH="$fixture_bin:$runtime_path" \
  DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/1000/bus" \
  timeout 2s uwsm-app -- gtk-launch 'org.example.User.desktop' || launch_status=$?
case "$launch_status" in
  0) test -f "$test_root/launch.log" ;;
  124) test ! -e "$test_root/launch.log" ;;
  *) printf 'packaged UWSM launch path failed with status %s\n' "$launch_status" >&2; exit 1 ;;
esac

printf '%s\n' 'UWSM package and AppLibrary integration passed'
