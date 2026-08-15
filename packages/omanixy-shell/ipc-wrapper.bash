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
runtime_dir=${XDG_RUNTIME_DIR:-/run/user/$UID}

if [[ -z ${WAYLAND_DISPLAY:-} ]]; then
  # shellcheck disable=SC2012,SC2045,SC2046
  for socket in $(ls -t "$runtime_dir"/wayland-[0-9]* 2>/dev/null); do
    [[ -S $socket ]] || continue
    WAYLAND_DISPLAY=${socket##*/}
    break
  done
  export WAYLAND_DISPLAY
fi

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
