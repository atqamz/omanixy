#!/usr/bin/env bash
set -euo pipefail

quiet=0
if [[ ${1:-} == "-q" ]]; then
  quiet=1
  shift
fi

fail() {
  if (( quiet )); then
    exit 0
  fi
  printf '%s\n' "$1" >&2
  exit 1
}

if (( $# == 0 )) || [[ ${1:-} == "-h" || ${1:-} == "--help" ]]; then
  cat <<'USAGE'
Usage: omanixy-shell [-q] <target> <method> [args...]

The shell must already be running. This command never starts it.
USAGE
  exit 0
fi

(( $# >= 2 )) || fail 'Usage: omanixy-shell <target> <method> [args...]'

if [[ $1 == shell && ($2 == summon || $2 == toggle) && $# == 3 ]]; then
  set -- "$@" '{}'
fi

export OMARCHY_PATH='@OMARCHY_PATH@'

[[ -n ${XDG_RUNTIME_DIR:-} ]] || fail 'omanixy-shell requires XDG_RUNTIME_DIR from the graphical session'
[[ -n ${WAYLAND_DISPLAY:-} ]] || fail 'omanixy-shell requires WAYLAND_DISPLAY from the graphical session'
[[ $WAYLAND_DISPLAY != */* ]] || fail 'omanixy-shell received an invalid WAYLAND_DISPLAY'

wayland_socket="$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY"
[[ -S $wayland_socket ]] || fail "omanixy-shell Wayland socket is unavailable: $wayland_socket"

timeout_value=${OMARCHY_SHELL_IPC_TIMEOUT:-2s}
set +e
output=$(timeout --foreground --kill-after=1s "$timeout_value" quickshell ipc -n -p "$OMARCHY_PATH/shell" call -- "$@" 2>/dev/null)
ipc_status=$?
set -e

case $ipc_status in
  124|137) fail 'omanixy-shell is not responding' ;;
  0) ;;
  *) fail 'omanixy-shell is not running' ;;
esac

case $output in
  'Target not found.'|'Function not found.'|'Too few arguments provided'*|'Too many arguments provided'*)
    fail "$output"
    ;;
  'Not ready to accept queries yet'*)
    fail 'omanixy-shell is not ready'
    ;;
esac

if (( !quiet )) && [[ -n $output ]]; then
  printf '%s\n' "$output"
fi
