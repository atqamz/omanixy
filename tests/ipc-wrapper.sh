#!/usr/bin/env bash
set -euo pipefail

repo=${1:?repository path required}
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

mkdir -p "$tmp/bin" "$tmp/omarchy/shell"
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

run_wrapper() {
  IPC_LOG="$tmp/ipc.log" \
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

run_wrapper shell summon omarchy.menu
tail -n 1 "$tmp/ipc.log" | grep -Fqx '{}'

assert_failure 'omanixy-shell is not running' env IPC_MODE=unavailable IPC_LOG="$tmp/ipc.log" PATH="$tmp/bin:$PATH" WAYLAND_DISPLAY=wayland-1 XDG_RUNTIME_DIR="$tmp/runtime" "$tmp/omanixy-shell" shell ping
assert_failure 'omanixy-shell is not ready' env IPC_MODE=not-ready IPC_LOG="$tmp/ipc.log" PATH="$tmp/bin:$PATH" WAYLAND_DISPLAY=wayland-1 XDG_RUNTIME_DIR="$tmp/runtime" "$tmp/omanixy-shell" shell ping
assert_failure 'omanixy-shell is not responding' env IPC_MODE=timeout IPC_LOG="$tmp/ipc.log" PATH="$tmp/bin:$PATH" WAYLAND_DISPLAY=wayland-1 XDG_RUNTIME_DIR="$tmp/runtime" "$tmp/omanixy-shell" shell ping
assert_failure 'Target not found.' env IPC_MODE=target-error IPC_LOG="$tmp/ipc.log" PATH="$tmp/bin:$PATH" WAYLAND_DISPLAY=wayland-1 XDG_RUNTIME_DIR="$tmp/runtime" "$tmp/omanixy-shell" shell ping

assert_failure 'Usage: omanixy-shell <target> <method> [args...]' "$tmp/omanixy-shell" shell

printf 'ipc wrapper checks passed\n'
