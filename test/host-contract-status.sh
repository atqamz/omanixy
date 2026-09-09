#!/usr/bin/env bash
set -euo pipefail

repo=$(cd "${1:?repository path required}" && pwd)
common="$repo/packages/omanixy-shell/adapters/common.bash"
test_root=$(mktemp -d)
trap 'rm -rf "$test_root"' EXIT
mkdir -p "$test_root/empty-bin" "$test_root/home"

bash_path=$(command -v bash)
env_path=$(command -v env)

status=0
if "$env_path" \
  PATH="$test_root/empty-bin" \
  HOME="$test_root/home" \
  XDG_STATE_HOME="$test_root/home/.local/state" \
  XDG_DATA_HOME="$test_root/home/.local/share" \
  XDG_CONFIG_HOME="$test_root/home/.config" \
  COMPAT_ADAPTER_NAME=omarchy-test \
  "$bash_path" -c 'source "$1"; need missing-backend' _ "$common" \
  2>"$test_root/missing-backend.error"; then
  printf '%s\n' 'missing backend unexpectedly succeeded' >&2
  exit 1
else
  status=$?
fi

test "$status" -eq 69
grep -Fqx 'omarchy-test: required backend is unavailable: missing-backend' "$test_root/missing-backend.error"

status=0
if HOME="$test_root/home" \
  XDG_STATE_HOME="$test_root/home/.local/state" \
  XDG_DATA_HOME="$test_root/home/.local/share" \
  XDG_CONFIG_HOME="$test_root/home/.config" \
  COMPAT_ADAPTER_NAME=omarchy-test \
  "$bash_path" -c 'source "$1"; if timed 0.01 test-timeout bash -c "sleep 1"; then exit 99; else exit $?; fi' _ "$common" \
  2>"$test_root/timeout.error"; then
  printf '%s\n' 'timed backend unexpectedly succeeded' >&2
  exit 1
else
  status=$?
fi

test "$status" -eq 124
grep -Fqx 'omarchy-test: test-timeout timed out' "$test_root/timeout.error"

printf '%s\n' 'host contract status tests passed'
