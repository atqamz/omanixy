#!/usr/bin/env bash
set -euo pipefail

uwsm_app=${1:?selected uwsm-app path required}
test -x "$uwsm_app"
case "$uwsm_app" in
  /nix/store/*-uwsm-*/bin/uwsm-app) ;;
  *) exit 1 ;;
esac
help=$("$uwsm_app" --help 2>&1) || status=$?
status=${status:-0}
if ((status == 0)); then
  grep -Fq 'usage: uwsm app' <<<"$help"
else
  grep -Fq 'DBUS_SESSION_BUS_ADDRESS' <<<"$help"
fi
printf '%s\n' 'NATIVE_PROBE=uwsm-app'
