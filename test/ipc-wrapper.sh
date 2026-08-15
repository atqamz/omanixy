#!/usr/bin/env bash
set -euo pipefail

repo=${1:?repository path required}
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

mkdir -p "$tmp/bin" "$tmp/omarchy/shell" "$tmp/runtime"
mkdir -p "$tmp/runtime/nested"
cp "$repo/packages/omanixy-shell/ipc-wrapper.bash" "$tmp/omanixy-shell"
sed -i "s|@OMARCHY_PATH@|$tmp/omarchy|g" "$tmp/omanixy-shell"
chmod +x "$tmp/omanixy-shell"

cat > "$tmp/bin/timeout" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
shift 3
exec "$@"
EOF
chmod +x "$tmp/bin/timeout"

cat > "$tmp/bin/quickshell" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$@" > "$IPC_LOG"
printf '%s\n' "${WAYLAND_DISPLAY:-unset}" > "${IPC_ENV_LOG:-/dev/null}"
printf '%s\n' "${XDG_RUNTIME_DIR:-unset}" >> "${IPC_ENV_LOG:-/dev/null}"
touch "${QS_CALL_LOG:-/dev/null}"
case ${IPC_MODE:-success} in
  success) printf '%s\n' '{"ok":true}' ;;
  unavailable) exit 1 ;;
  not-ready) printf '%s\n' 'Not ready to accept queries yet' ;;
  timeout) exit 124 ;;
  target-error) printf '%s\n' 'Target not found.' ;;
esac
EOF
chmod +x "$tmp/bin/quickshell"
sed -i "1c#!$(command -v bash)" "$tmp/omanixy-shell" "$tmp/bin/timeout" "$tmp/bin/quickshell"

python_cmd=${PYTHON:?PYTHON test interpreter required}
make_socket() {
  "$python_cmd" - "$1" <<'PY'
import socket
import sys

sock = socket.socket(socket.AF_UNIX)
sock.bind(sys.argv[1])
sock.close()
PY
}

make_socket "$tmp/runtime/wayland-1"
make_socket "$tmp/runtime/wayland-2"
make_socket "$tmp/runtime/nested/wayland-3"
make_socket "$tmp/absolute-wayland"

run_wrapper() {
  IPC_LOG="$tmp/ipc.log" \
    IPC_ENV_LOG="$tmp/ipc-env.log" \
    QS_CALL_LOG="$tmp/qs-called" \
    PATH="$tmp/bin:$PATH" \
    WAYLAND_DISPLAY=wayland-1 \
    XDG_RUNTIME_DIR="$tmp/runtime" \
    "$tmp/omanixy-shell" "$@"
}

assert_failure() {
  local expected=$1
  shift
  local stderr="$tmp/stderr"
  local status=0
  if "$@" >"$tmp/stdout" 2>"$stderr"; then
    status=0
  else
    status=$?
  fi
  test "$status" -eq 1
  grep -Fqx "$expected" "$stderr"
}

output=$(run_wrapper shell ping '{"value":"a b"}')
test "$output" = '{"ok":true}'
grep -Fqx 'ipc' "$tmp/ipc.log"
grep -Fqx 'shell' "$tmp/ipc.log"
grep -Fqx 'ping' "$tmp/ipc.log"
grep -Fqx '{"value":"a b"}' "$tmp/ipc.log"
grep -Fqx 'wayland-1' "$tmp/ipc-env.log"
grep -Fqx "$tmp/runtime" "$tmp/ipc-env.log"

output=$(IPC_LOG="$tmp/ipc.log" IPC_ENV_LOG="$tmp/ipc-env.log" QS_CALL_LOG="$tmp/qs-called" \
  PATH="$tmp/bin:$PATH" WAYLAND_DISPLAY=nested/wayland-3 XDG_RUNTIME_DIR="$tmp/runtime" \
  "$tmp/omanixy-shell" shell ping)
test "$output" = '{"ok":true}'
grep -Fqx 'nested/wayland-3' "$tmp/ipc-env.log"

output=$(IPC_LOG="$tmp/ipc.log" IPC_ENV_LOG="$tmp/ipc-env.log" QS_CALL_LOG="$tmp/qs-called" \
  PATH="$tmp/bin:$PATH" WAYLAND_DISPLAY="$tmp/absolute-wayland" XDG_RUNTIME_DIR="$tmp/runtime" \
  "$tmp/omanixy-shell" shell ping)
test "$output" = '{"ok":true}'
grep -Fqx "$tmp/absolute-wayland" "$tmp/ipc-env.log"
grep -Fqx "$tmp/runtime" "$tmp/ipc-env.log"

rm -f "$tmp/qs-called"
assert_failure 'omanixy-shell requires XDG_RUNTIME_DIR from the graphical session' env -u XDG_RUNTIME_DIR IPC_LOG="$tmp/ipc.log" IPC_ENV_LOG="$tmp/ipc-env.log" QS_CALL_LOG="$tmp/qs-called" PATH="$tmp/bin:$PATH" WAYLAND_DISPLAY="$tmp/absolute-wayland" "$tmp/omanixy-shell" shell ping
test ! -e "$tmp/qs-called"
assert_failure 'omanixy-shell requires an absolute XDG_RUNTIME_DIR from the graphical session' env IPC_LOG="$tmp/ipc.log" IPC_ENV_LOG="$tmp/ipc-env.log" QS_CALL_LOG="$tmp/qs-called" PATH="$tmp/bin:$PATH" WAYLAND_DISPLAY="$tmp/absolute-wayland" XDG_RUNTIME_DIR=relative-runtime "$tmp/omanixy-shell" shell ping
assert_failure "omanixy-shell XDG_RUNTIME_DIR is not a directory: $tmp/missing-runtime" env IPC_LOG="$tmp/ipc.log" IPC_ENV_LOG="$tmp/ipc-env.log" QS_CALL_LOG="$tmp/qs-called" PATH="$tmp/bin:$PATH" WAYLAND_DISPLAY="$tmp/absolute-wayland" XDG_RUNTIME_DIR="$tmp/missing-runtime" "$tmp/omanixy-shell" shell ping

run_wrapper shell summon omarchy.menu
tail -n 1 "$tmp/ipc.log" | grep -Fqx '{}'

assert_failure 'omanixy-shell is not running' env IPC_MODE=unavailable IPC_LOG="$tmp/ipc.log" PATH="$tmp/bin:$PATH" WAYLAND_DISPLAY=wayland-1 XDG_RUNTIME_DIR="$tmp/runtime" "$tmp/omanixy-shell" shell ping
assert_failure 'omanixy-shell is not ready' env IPC_MODE=not-ready IPC_LOG="$tmp/ipc.log" PATH="$tmp/bin:$PATH" WAYLAND_DISPLAY=wayland-1 XDG_RUNTIME_DIR="$tmp/runtime" "$tmp/omanixy-shell" shell ping
assert_failure 'omanixy-shell is not responding' env IPC_MODE=timeout IPC_LOG="$tmp/ipc.log" PATH="$tmp/bin:$PATH" WAYLAND_DISPLAY=wayland-1 XDG_RUNTIME_DIR="$tmp/runtime" "$tmp/omanixy-shell" shell ping
assert_failure 'Target not found.' env IPC_MODE=target-error IPC_LOG="$tmp/ipc.log" PATH="$tmp/bin:$PATH" WAYLAND_DISPLAY=wayland-1 XDG_RUNTIME_DIR="$tmp/runtime" "$tmp/omanixy-shell" shell ping

rm -f "$tmp/qs-called"
assert_failure 'omanixy-shell requires WAYLAND_DISPLAY from the graphical session' env -u WAYLAND_DISPLAY IPC_LOG="$tmp/ipc.log" IPC_ENV_LOG="$tmp/ipc-env.log" QS_CALL_LOG="$tmp/qs-called" PATH="$tmp/bin:$PATH" XDG_RUNTIME_DIR="$tmp/runtime" "$tmp/omanixy-shell" shell ping
test ! -e "$tmp/qs-called"

assert_failure 'omanixy-shell requires XDG_RUNTIME_DIR from the graphical session' env -u XDG_RUNTIME_DIR IPC_LOG="$tmp/ipc.log" IPC_ENV_LOG="$tmp/ipc-env.log" QS_CALL_LOG="$tmp/qs-called" PATH="$tmp/bin:$PATH" WAYLAND_DISPLAY=wayland-1 "$tmp/omanixy-shell" shell ping
assert_failure 'omanixy-shell requires an absolute XDG_RUNTIME_DIR from the graphical session' env IPC_LOG="$tmp/ipc.log" IPC_ENV_LOG="$tmp/ipc-env.log" QS_CALL_LOG="$tmp/qs-called" PATH="$tmp/bin:$PATH" WAYLAND_DISPLAY=wayland-1 XDG_RUNTIME_DIR=relative-runtime "$tmp/omanixy-shell" shell ping
assert_failure "omanixy-shell XDG_RUNTIME_DIR is not a directory: $tmp/missing-runtime" env IPC_LOG="$tmp/ipc.log" IPC_ENV_LOG="$tmp/ipc-env.log" QS_CALL_LOG="$tmp/qs-called" PATH="$tmp/bin:$PATH" WAYLAND_DISPLAY=wayland-1 XDG_RUNTIME_DIR="$tmp/missing-runtime" "$tmp/omanixy-shell" shell ping

rm -f "$tmp/qs-called"
assert_failure "omanixy-shell Wayland socket is unavailable: $tmp/runtime/stale-wayland" env IPC_LOG="$tmp/ipc.log" IPC_ENV_LOG="$tmp/ipc-env.log" QS_CALL_LOG="$tmp/qs-called" PATH="$tmp/bin:$PATH" WAYLAND_DISPLAY=stale-wayland XDG_RUNTIME_DIR="$tmp/runtime" "$tmp/omanixy-shell" shell ping
test ! -e "$tmp/qs-called"

assert_failure 'Usage: omanixy-shell <target> <method> [args...]' "$tmp/omanixy-shell" shell

printf 'ipc wrapper checks passed\n'
