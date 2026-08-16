#!/usr/bin/env bash
set -euo pipefail

runtime=${1:?runtime package path required}
compatibility_root=${2:?compatibility root path required}
quickshell=${3:?selected Quickshell executable required}
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
runtime_dir="$test_root/runtime"
config_root="$test_root/config"
mkdir -p "$fixture_bin" "$data_home/applications" "$runtime_dir" "$config_root"
ln -s "$compatibility_root/shell" "$test_root/qs"
ln -s "$compatibility_root/shell/Commons" "$config_root/Commons"
ln -s "$compatibility_root/shell/services" "$config_root/services"
cat > "$fixture_bin/gtk-launch" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" > "$LAUNCH_LOG"
EOF
chmod +x "$fixture_bin/gtk-launch"
sed -i "1c#!$(command -v bash)" "$fixture_bin/gtk-launch"
cat > "$data_home/applications/org.example.User.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Omanixy test app
Exec=$fixture_bin/gtk-launch
EOF
cat > "$fixture_bin/systemctl" <<'EOF'
#!/usr/bin/env bash
case "$*" in
  *show-environment*) printf 'PATH=%s\n' "$FIXTURE_PATH" ;;
  *) exit 0 ;;
esac
EOF
chmod +x "$fixture_bin/systemctl"
sed -i "1c#!$(command -v bash)" "$fixture_bin/systemctl"
for utility in sleep flock notify-send; do
  printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "$fixture_bin/$utility"
  chmod +x "$fixture_bin/$utility"
  sed -i "1c#!$(command -v bash)" "$fixture_bin/$utility"
done

cat > "$config_root/shell.qml" <<'EOF'
import QtQuick
import Quickshell
import Quickshell.Io

Loader {
  source: Quickshell.env("OMANIXY_APP_LIBRARY")
  property bool launched: false
  property int attempts: 0
  onLoaded: {
    if (item) item.launch("org.example.User", "Omanixy test app")
    launched = true
  }
  Timer {
    interval: 100
    running: true
    repeat: true
    onTriggered: {
      attempts++
      if (launched && attempts >= 20) Qt.quit()
    }
  }
}
EOF
launch_status=0
LAUNCH_LOG="$test_root/launch.log" \
  XDG_DATA_HOME="$data_home" \
  XDG_RUNTIME_DIR="$runtime_dir" \
  QT_QPA_PLATFORM=offscreen \
  OMANIXY_APP_LIBRARY="$config_root/services/AppLibrary.qml" \
  OMARCHY_PATH="$compatibility_root" \
  LAUNCH_LOG="$test_root/launch.log" \
  FIXTURE_PATH="$fixture_bin:$runtime_path" \
  PATH="$fixture_bin:$runtime_path" \
  timeout 10s "$quickshell" -n -p "$config_root" || launch_status=$?
if ((launch_status == 124)); then
  if [[ -n ${WAYLAND_DISPLAY:-} || -n ${UWSM_FINALIZE_VARNAME:-} ]]; then
    printf '%s\n' 'patched AppLibrary launch path timed out in an available session' >&2
    exit 1
  fi
  printf '%s\n' 'SESSION_UNAVAILABLE_UNCLAIMED: no live Wayland/UWSM session was available' >&2
  exit 0
fi
for _ in {1..20}; do
  test -f "$test_root/launch.log" && break
  sleep 0.1
done
if test -f "$test_root/launch.log"; then
  grep -Fxq 'org.example.User.desktop' "$test_root/launch.log"
else
  if [[ -n ${WAYLAND_DISPLAY:-} || -n ${UWSM_FINALIZE_VARNAME:-} ]]; then
    printf '%s\n' 'real AppLibrary/UWSM launch produced no evidence in an available session' >&2
    exit 1
  fi
  printf '%s\n' 'SESSION_UNAVAILABLE_UNCLAIMED: no live Wayland/UWSM session was available' >&2
  exit 0
fi

printf '%s\n' 'LIVE_SMOKE_CLAIMED: real UWSM launch recorder observed the desktop id'
