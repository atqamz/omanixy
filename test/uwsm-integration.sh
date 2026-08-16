#!/usr/bin/env bash
set -euo pipefail

runtime=${1:?runtime package path required}
compatibility_root=${2:?compatibility root path required}
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

app_library="$compatibility_root/shell/services/AppLibrary.qml"
grep -Fq 'Util.execDetached("uwsm-app -- gtk-launch ' "$app_library"
test "$(grep -Fc 'uwsm-app --' "$app_library")" -eq 1

printf '%s\n' 'UWSM package and AppLibrary integration passed'
