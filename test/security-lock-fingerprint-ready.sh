#!/usr/bin/env bash
set -euo pipefail

common_adapter=${1:?adapters/common.bash path required}
lock_adapter=${2:?adapters/lock.bash path required}

real_bash=$(command -v bash)
real_id=$(command -v id)
real_timeout=$(command -v timeout)

test_root=$(mktemp -d)
trap 'rm -rf "$test_root"' EXIT
bin="$test_root/bin"
mkdir -p "$bin" "$test_root/home"
ln -s "$real_id" "$bin/id"
ln -s "$real_timeout" "$bin/timeout"

export HOME="$test_root/home"

probe_script="$test_root/probe.sh"
cat > "$probe_script" <<EOF
#!/usr/bin/env bash
set -euo pipefail
source "$common_adapter"
source "$lock_adapter"
lock_fingerprint_ready "\$@"
EOF
chmod +x "$probe_script"
sed -i "1c#!$real_bash" "$probe_script"

write_fprintd_list() {
  cat > "$bin/fprintd-list" <<EOF
#!/usr/bin/env bash
$1
EOF
  chmod +x "$bin/fprintd-list"
  sed -i "1c#!$real_bash" "$bin/fprintd-list"
}

remove_fprintd_list() {
  rm -f "$bin/fprintd-list"
}

use_failing_id() {
  rm -f "$bin/id"
  cat > "$bin/id" <<EOF
#!/usr/bin/env bash
exit 1
EOF
  chmod +x "$bin/id"
  sed -i "1c#!$real_bash" "$bin/id"
}

use_real_id() {
  rm -f "$bin/id"
  ln -s "$real_id" "$bin/id"
}

assert_exit() {
  local description=$1 expected=$2 status
  shift 2
  set +e
  PATH="$bin" "$probe_script" "$@" >/dev/null 2>"$test_root/stderr"
  status=$?
  set -e
  if [[ $status != "$expected" ]]; then
    printf 'case failed: %s (expected exit %s, got %s)\n' "$description" "$expected" "$status" >&2
    cat "$test_root/stderr" >&2
    exit 1
  fi
  case $status in
    0 | 1 | 2) ;;
    *)
      printf 'case leaked a non-ABI exit code %s: %s\n' "$status" "$description" >&2
      exit 1
      ;;
  esac
}

assert_exit 'args supplied' 2 extra-arg

assert_exit 'missing fprintd-list backend' 2

use_failing_id
write_fprintd_list 'exit 0'
assert_exit 'id lookup failure' 2
use_real_id
remove_fprintd_list

write_fprintd_list 'sleep 10'
assert_exit 'fprintd-list timeout' 2
remove_fprintd_list

write_fprintd_list 'printf "unexpected backend failure\n"; exit 5'
assert_exit 'arbitrary backend exit code' 2
remove_fprintd_list

write_fprintd_list 'printf "Fingerprints for user testuser:\n - #0: enabled\n"; exit 0'
assert_exit 'single enrolled fingerprint' 0
remove_fprintd_list

write_fprintd_list 'printf "Fingerprint device 1 : has no fingers enrolled\nFingerprints for user testuser:\n - #0: enabled\n"; exit 0'
assert_exit 'multi-device mixed enrollment (positive wins)' 0
remove_fprintd_list

write_fprintd_list 'printf "Impossible to get the list of fingerprints: testuser has no fingers enrolled\n"; exit 0'
assert_exit 'no fingerprints enrolled' 1
remove_fprintd_list

write_fprintd_list 'printf "No devices available\n"; exit 1'
assert_exit 'no devices available' 1
remove_fprintd_list

write_fprintd_list 'printf "garbage that matches neither pattern\n"; exit 0'
assert_exit 'malformed success output' 2
remove_fprintd_list

write_fprintd_list 'printf "some other daemon error\n"; exit 1'
assert_exit 'unrecognized failure-path output' 2
remove_fprintd_list

printf '%s\n' 'security lock fingerprint readiness adapter ABI checks passed'
