#!/usr/bin/env bash
set -euo pipefail

name=${COMPAT_ADAPTER_NAME:-${0##*/}}
state_home=${XDG_STATE_HOME:-$HOME/.local/state}
data_home=${XDG_DATA_HOME:-$HOME/.local/share}
config_home=${XDG_CONFIG_HOME:-$HOME/.config}
# shellcheck disable=SC2034
omarchy_state="$state_home/omarchy"

fail() {
  printf '%s\n' "$1" >&2
  exit "${2:-1}"
}

need() {
  command -v "$1" >/dev/null 2>&1 || fail "$name: required backend is unavailable: $1" 127
}

[[ $state_home == /* ]] || fail "$name: XDG_STATE_HOME must be an absolute path"
[[ $data_home == /* ]] || fail "$name: XDG_DATA_HOME must be an absolute path"
[[ $config_home == /* ]] || fail "$name: XDG_CONFIG_HOME must be an absolute path"

timed() {
  local seconds=$1 label=$2 status
  shift 2
  if timeout --kill-after=1s "${seconds}s" "$@"; then
    return 0
  else
    status=$?
  fi
  if [[ $status == 124 || $status == 137 || $status == 143 ]]; then
    printf '%s: %s timed out\n' "$name" "$label" >&2
  fi
  return "$status"
}
