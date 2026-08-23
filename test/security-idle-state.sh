#!/usr/bin/env bash
# Drives the real omanixy-idle-state adapter (idle.bash) directly, the same
# way security-lock-fingerprint-ready.sh drives the fingerprint adapter -
# never a disconnected reimplementation of its exit-code contract.
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

# The external ABI is strictly 0/1/2 - probe: exists/absent/indeterminate;
# set: success/failure. Nothing else may leak past this adapter.
#
# home is one of: an absolute path, a relative path (to test rejection), or
# the literal "__UNSET__" (to test HOME being entirely unset) - passed
# explicitly rather than via env-var-prefix so the unset case can be
# expressed without trying to `env -u HOME` a shell function.
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

# --- probe ---

# No marker present.
assert_exit 'probe absent' 1 "$home" probe

# Marker present.
mkdir -p "$(dirname "$marker")"
: > "$marker"
assert_exit 'probe present' 0 "$home" probe
rm -f "$marker"

# Invalid HOME: unset entirely.
assert_exit 'probe with unset HOME' 2 __UNSET__ probe

# Invalid HOME: relative path.
assert_exit 'probe with relative HOME' 2 'relative/path' probe

# Extra argument after the verb is rejected before touching the marker.
assert_exit 'probe with extra arg' 2 "$home" probe extra

# Permission failure: parent directory exists but is not searchable, so
# existence is unprovable - fail closed as indeterminate (2), never
# silently reported as absent (1).
indicators_dir="$test_root/home/.local/state/omarchy/indicators"
mkdir -p "$indicators_dir"
chmod 000 "$indicators_dir"
assert_exit 'probe with unsearchable parent' 2 "$home" probe
chmod 755 "$indicators_dir"
rm -rf "$test_root/home/.local"

# --- set awake ---

assert_exit 'set awake (first call)' 0 "$home" set awake
[[ -e $marker ]] || { printf 'set awake did not create the marker\n' >&2; exit 1; }

# Idempotent: calling again with the marker already present still succeeds.
assert_exit 'set awake (idempotent repeat)' 0 "$home" set awake
[[ -e $marker ]] || { printf 'marker missing after idempotent repeat\n' >&2; exit 1; }

# --- set idle ---

assert_exit 'set idle (removes marker)' 0 "$home" set idle
[[ ! -e $marker ]] || { printf 'set idle did not remove the marker\n' >&2; exit 1; }

# Idempotent: calling again with the marker already absent still succeeds.
assert_exit 'set idle (idempotent repeat)' 0 "$home" set idle
[[ ! -e $marker ]] || { printf 'marker reappeared after idempotent repeat\n' >&2; exit 1; }

# --- invalid verbs / args ---

assert_exit 'unknown top-level verb' 2 "$home" bogus
assert_exit 'no verb at all' 2 "$home"
assert_exit 'set with no sub-verb' 2 "$home" set
assert_exit 'set with unknown sub-verb' 2 "$home" set bogus
assert_exit 'set awake with extra arg' 2 "$home" set awake extra
assert_exit 'set idle with extra arg' 2 "$home" set idle extra

# set also fails closed under an invalid HOME.
assert_exit 'set awake with relative HOME' 2 'relative/path' set awake
assert_exit 'set idle with unset HOME' 2 __UNSET__ set idle

printf '%s\n' 'security idle state adapter ABI checks passed'
