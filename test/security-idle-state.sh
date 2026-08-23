#!/usr/bin/env bash
set -euo pipefail

idle_adapter=${1:?adapters/idle.bash path required}

real_bash=$(command -v bash)

test_root=$(mktemp -d)
trap 'chmod -R u+w "$test_root"; rm -rf "$test_root"' EXIT
mkdir -p "$test_root/home"

probe_script="$test_root/probe.sh"
cat > "$probe_script" <<EOF
#!/usr/bin/env bash
set -euo pipefail
source "$idle_adapter"
idle_state "\$@"
EOF
chmod +x "$probe_script"
sed -i "1c#!$real_bash" "$probe_script"

marker="$test_root/home/.local/state/omarchy/indicators/stay-awake"

assert_exit() {
  local description=$1 expected=$2 home=$3 status
  shift 3
  set +e
  if [[ $home == __UNSET__ ]]; then
    env -u HOME "$probe_script" "$@" >/dev/null 2>"$test_root/stderr"
  else
    HOME=$home "$probe_script" "$@" >/dev/null 2>"$test_root/stderr"
  fi
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

home="$test_root/home"


assert_exit 'probe absent' 1 "$home" probe

mkdir -p "$(dirname "$marker")"
: > "$marker"
assert_exit 'probe present' 0 "$home" probe
rm -f "$marker"

assert_exit 'probe with unset HOME' 2 __UNSET__ probe

assert_exit 'probe with relative HOME' 2 'relative/path' probe

assert_exit 'probe with extra arg' 2 "$home" probe extra

indicators_dir="$test_root/home/.local/state/omarchy/indicators"
mkdir -p "$indicators_dir"
chmod 000 "$indicators_dir"
assert_exit 'probe with unsearchable parent' 2 "$home" probe
chmod 755 "$indicators_dir"
rm -rf "$test_root/home/.local"


assert_exit 'set awake (first call)' 0 "$home" set awake
[[ -e $marker ]] || { printf 'set awake did not create the marker\n' >&2; exit 1; }

assert_exit 'set awake (idempotent repeat)' 0 "$home" set awake
[[ -e $marker ]] || { printf 'marker missing after idempotent repeat\n' >&2; exit 1; }


assert_exit 'set idle (removes marker)' 0 "$home" set idle
[[ ! -e $marker ]] || { printf 'set idle did not remove the marker\n' >&2; exit 1; }

assert_exit 'set idle (idempotent repeat)' 0 "$home" set idle
[[ ! -e $marker ]] || { printf 'marker reappeared after idempotent repeat\n' >&2; exit 1; }


assert_exit 'unknown top-level verb' 2 "$home" bogus
assert_exit 'no verb at all' 2 "$home"
assert_exit 'set with no sub-verb' 2 "$home" set
assert_exit 'set with unknown sub-verb' 2 "$home" set bogus
assert_exit 'set awake with extra arg' 2 "$home" set awake extra
assert_exit 'set idle with extra arg' 2 "$home" set idle extra

assert_exit 'set awake with relative HOME' 2 'relative/path' set awake
assert_exit 'set idle with unset HOME' 2 __UNSET__ set idle

printf '%s\n' 'security idle state adapter ABI checks passed'
