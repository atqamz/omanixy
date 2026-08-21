#!/usr/bin/env bash
# Drives the real omanixy-notification-state adapter (notification-state.bash)
# directly, the same way security-idle-state.sh drives the idle adapter -
# never a disconnected reimplementation of its exit-code contract.
set -euo pipefail

notification_state_adapter=${1:?adapters/notification-state.bash path required}

real_bash=$(command -v bash)

test_root=$(mktemp -d)
trap 'chmod -R u+w "$test_root"; rm -rf "$test_root"' EXIT
mkdir -p "$test_root/home"

probe_script="$test_root/probe.sh"
cat >"$probe_script" <<EOF
#!/usr/bin/env bash
set -euo pipefail
source "$notification_state_adapter"
notification_state "\$@"
EOF
chmod +x "$probe_script"
sed -i "1c#!$real_bash" "$probe_script"

home="$test_root/home"
popup_dir="$home/.local/state/omarchy/notifications"
history_dir="$popup_dir/history"
images_dir="$popup_dir/images"

# The external ABI is strictly 0/1/2 - nothing else may leak past this
# adapter. home is one of: an absolute path, a relative path (to test
# rejection), or the literal "__UNSET__" (unset HOME entirely).
run() {
  local home=$1
  shift
  if [[ $home == __UNSET__ ]]; then
    env -u HOME timeout 10s "$probe_script" "$@"
  else
    HOME=$home timeout 10s "$probe_script" "$@"
  fi
}

assert_exit() {
  local description=$1 expected=$2 home=$3 status
  shift 3
  set +e
  run "$home" "$@" >"$test_root/stdout" 2>"$test_root/stderr"
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

# --- HOME validation, every verb ---
for verb in init read-popups read-history clear-history sweep-images; do
  assert_exit "$verb with unset HOME" 2 __UNSET__ "$verb"
  assert_exit "$verb with relative HOME" 2 'relative/path' "$verb"
done
assert_exit 'persist-popup with unset HOME' 2 __UNSET__ persist-popup 1-1 '{}'
assert_exit 'archive-popup with relative HOME' 2 'relative/path' archive-popup 1-1
assert_exit 'delete-popup with unset HOME' 2 __UNSET__ delete-popup 1-1

# --- invalid verb / arity ---
assert_exit 'unknown top-level verb' 2 "$home" bogus
assert_exit 'no verb at all' 2 "$home"
assert_exit 'persist-popup with no args' 2 "$home" persist-popup
assert_exit 'persist-popup with only a stem' 2 "$home" persist-popup 1-1
assert_exit 'archive-popup with extra arg' 2 "$home" archive-popup 1-1 extra
assert_exit 'delete-popup with no args' 2 "$home" delete-popup
assert_exit 'read-popups with extra arg' 2 "$home" read-popups extra
assert_exit 'clear-history with extra arg' 2 "$home" clear-history extra
assert_exit 'init with extra arg' 2 "$home" init extra

# --- stem validation: only <digits>-<digits> is ever accepted ---
for bad_stem in '' '../../etc/passwd' '/etc/passwd' '1-1/../2' '1-1*' 'abc-1' '1-1 ' '1--1'; do
  assert_exit "archive-popup rejects stem '$bad_stem'" 2 "$home" archive-popup "$bad_stem"
  assert_exit "delete-popup rejects stem '$bad_stem'" 2 "$home" delete-popup "$bad_stem"
  assert_exit "persist-popup rejects stem '$bad_stem'" 2 "$home" persist-popup "$bad_stem" '{}'
done

# --- init ---
assert_exit 'init creates only the expected state directories' 0 "$home" init
[[ -d $popup_dir ]] || { printf 'init did not create popup dir\n' >&2; exit 1; }
[[ -d $history_dir ]] || { printf 'init did not create history dir\n' >&2; exit 1; }
[[ -d $images_dir ]] || { printf 'init did not create images dir\n' >&2; exit 1; }
[[ ! -e "$home/.local/state/omarchy/notifications.json" ]] || {
  printf 'init must never create notifications.json - that stays owned by the QML FileView\n' >&2
  exit 1
}

# --- persist-popup / read-popups / delete-popup ---
assert_exit 'persist-popup writes exactly the expected file' 0 "$home" persist-popup 1000-1 '{"id":1}'
[[ -f "$popup_dir/1000-1.json" ]] || { printf 'persist-popup did not create the popup file\n' >&2; exit 1; }
[[ "$(cat "$popup_dir/1000-1.json")" == '{"id":1}' ]] || { printf 'persist-popup wrote unexpected content\n' >&2; exit 1; }

assert_exit 'persist-popup a second entry' 0 "$home" persist-popup 2000-2 '{"id":2}'
run "$home" read-popups >"$test_root/popups.out"
lines=$(wc -l <"$test_root/popups.out")
[[ $lines == 2 ]] || { printf 'read-popups expected 2 deterministic lines, got %s\n' "$lines" >&2; exit 1; }
grep -Fq '{"id":1}' "$test_root/popups.out"
grep -Fq '{"id":2}' "$test_root/popups.out"

assert_exit 'delete-popup removes only the exact popup artifact' 0 "$home" delete-popup 1000-1
[[ ! -e "$popup_dir/1000-1.json" ]] || { printf 'delete-popup did not remove the popup file\n' >&2; exit 1; }
[[ -f "$popup_dir/2000-2.json" ]] || { printf 'delete-popup removed an unrelated popup file\n' >&2; exit 1; }
assert_exit 'delete-popup on an already-absent stem is a no-op, not found' 1 "$home" delete-popup 1000-1

# --- archive-popup moves only the exact popup artifact to history ---
assert_exit 'archive-popup moves the exact popup to history' 0 "$home" archive-popup 2000-2
[[ ! -e "$popup_dir/2000-2.json" ]] || { printf 'archive-popup left the popup file behind\n' >&2; exit 1; }
[[ -f "$history_dir/2000-2.json" ]] || { printf 'archive-popup did not create the history file\n' >&2; exit 1; }
assert_exit 'archive-popup on an already-absent stem is a no-op, not found' 1 "$home" archive-popup 2000-2

# --- persist-history / read-history / history limit never exceeds 10 ---
run "$home" clear-history
for i in $(seq 1 12); do
  assert_exit "persist-history entry $i" 0 "$home" persist-history "$((i * 1000))-$i" "{\"id\":$i}"
done
run "$home" read-history >"$test_root/history.out"
history_lines=$(wc -l <"$test_root/history.out")
[[ $history_lines -le 10 ]] || { printf 'history exceeded the 10-entry limit: %s lines\n' "$history_lines" >&2; exit 1; }
history_files=$(find "$history_dir" -maxdepth 1 -name '*.json' | wc -l)
[[ $history_files -le 10 ]] || { printf 'history directory exceeded the 10-file limit: %s files\n' "$history_files" >&2; exit 1; }
# The two oldest entries (1, 2) must have been trimmed away.
[[ ! -f "$history_dir/1000-1.json" ]] || { printf 'trimming did not remove the oldest history entry\n' >&2; exit 1; }
[[ ! -f "$history_dir/2000-2.json" ]] || { printf 'trimming did not remove the second-oldest history entry\n' >&2; exit 1; }
[[ -f "$history_dir/12000-12.json" ]] || { printf 'trimming removed the newest history entry\n' >&2; exit 1; }

# --- clear-history does not touch live popup state ---
assert_exit 'persist-popup a live popup before clear-history' 0 "$home" persist-popup 9999-9 '{"id":9}'
assert_exit 'clear-history clears only recorded history' 0 "$home" clear-history
[[ -f "$popup_dir/9999-9.json" ]] || { printf 'clear-history touched an unrelated live popup file\n' >&2; exit 1; }
remaining_history=$(find "$history_dir" -maxdepth 1 -name '*.json' | wc -l)
[[ $remaining_history == 0 ]] || { printf 'clear-history left history files behind\n' >&2; exit 1; }
run "$home" delete-popup 9999-9

# --- corrupt/unreadable state: bounded failure, never a crash ---
rm -rf "$history_dir"
assert_exit 'read-history tolerates a missing history directory' 0 "$home" read-history
run "$home" read-history >"$test_root/empty-history.out"
[[ ! -s "$test_root/empty-history.out" ]] || { printf 'read-history on a missing dir must be empty, not fabricated\n' >&2; exit 1; }

# --- image copy bounds ---
assert_exit 'init recreates history dir' 0 "$home" init
big_source="$test_root/big.bin"
head -c 6000000 </dev/zero >"$big_source"
small_source="$test_root/small.bin"
head -c 100 </dev/zero >"$small_source"

assert_exit 'persist-popup with an oversized image source still succeeds (degraded, no image)' 0 "$home" persist-popup 5000-5 '{"id":5}' image "$big_source"
[[ ! -e "$images_dir/5000-5-image" ]] || { printf 'an oversized (>5MiB) image source must never be persisted\n' >&2; exit 1; }
[[ -f "$popup_dir/5000-5.json" ]] || { printf 'an oversized image copy must not fail the whole persist-popup call\n' >&2; exit 1; }
run "$home" delete-popup 5000-5

assert_exit 'persist-popup with an ordinary small image source persists it' 0 "$home" persist-popup 6000-6 '{"id":6}' appIcon "$small_source"
[[ -f "$images_dir/6000-6-appIcon" ]] || { printf 'a small (<=5MiB) regular file image must be persisted\n' >&2; exit 1; }
[[ $(stat -c%s "$images_dir/6000-6-appIcon") == 100 ]] || { printf 'persisted image content size mismatch\n' >&2; exit 1; }
run "$home" delete-popup 6000-6

assert_exit 'persist-popup with a missing image source degrades, does not fail' 0 "$home" persist-popup 7000-7 '{"id":7}' image "$test_root/does-not-exist"
[[ ! -e "$images_dir/7000-7-image" ]] || { printf 'a nonexistent source must never produce a destination file\n' >&2; exit 1; }
run "$home" delete-popup 7000-7

fifo="$test_root/afifo"
mkfifo "$fifo"
assert_exit 'persist-popup with a FIFO image source does not hang and degrades' 0 "$home" persist-popup 8000-8 '{"id":8}' image "$fifo"
[[ ! -e "$images_dir/8000-8-image" ]] || { printf 'a FIFO source must never be persisted as an image\n' >&2; exit 1; }
rm -f "$fifo"
run "$home" delete-popup 8000-8

# --- role/arity validation on image pairs ---
assert_exit 'persist-popup rejects an invalid role literal' 2 "$home" persist-popup 1-2 '{}' bogus "$small_source"
assert_exit 'persist-popup rejects a duplicate role' 2 "$home" persist-popup 1-3 '{}' appIcon "$small_source" appIcon "$small_source"
assert_exit 'persist-popup rejects an odd trailing arg count' 2 "$home" persist-popup 1-4 '{}' appIcon

# --- traversal/escape: destination is always derived internally ---
assert_exit 'persist-history with a legitimate stem succeeds' 0 "$home" persist-history 3000-3 '{"id":3}' appIcon "$small_source"
[[ -f "$images_dir/3000-3-appIcon" ]] || { printf 'persist-history image copy did not land under the images dir\n' >&2; exit 1; }
[[ ! -e "$test_root/home/3000-3-appIcon" ]] || { printf 'an image must never escape the derived images directory\n' >&2; exit 1; }

# --- serialized state payload bound ---
# Independently documented in the adapter (NOTIFICATION_STATE_MAX_PAYLOAD_BYTES) -
# duplicated here as a literal the same way the 10-entry history limit
# above is, not derived from the adapter source.
max_payload=65536

build_payload_of_size() {
  local size=$1 prefix='{"id":1,"pad":"' suffix='"}'
  local pad_len=$((size - ${#prefix} - ${#suffix}))
  ((pad_len >= 0)) || { printf 'requested payload size %s too small for the fixed prefix/suffix\n' "$size" >&2; exit 1; }
  printf '%s%s%s' "$prefix" "$(printf '%*s' "$pad_len" '' | tr ' ' 'x')" "$suffix"
}

payload_at_limit_minus_1=$(build_payload_of_size $((max_payload - 1)))
payload_at_limit=$(build_payload_of_size "$max_payload")
payload_over_limit=$(build_payload_of_size $((max_payload + 1)))
# "Huge" is deliberately kept below Linux's own per-argument hard limit
# (MAX_ARG_STRLEN, 32 pages = 128 KiB) - a payload at or beyond that fails
# exec() itself with E2BIG before the adapter ever runs, which would prove
# the kernel's incidental limit rejects it, not the adapter's own
# documented 64 KiB bound. Comfortably between the two proves the latter.
payload_huge=$(build_payload_of_size 98304)

assert_exit 'persist-popup accepts a payload one byte under the limit' 0 "$home" persist-popup 2001-1 "$payload_at_limit_minus_1"
[[ -f "$popup_dir/2001-1.json" ]] || { printf 'a within-bound payload must be persisted\n' >&2; exit 1; }
run "$home" delete-popup 2001-1

assert_exit 'persist-popup accepts a payload exactly at the limit' 0 "$home" persist-popup 2002-2 "$payload_at_limit"
[[ -f "$popup_dir/2002-2.json" ]] || { printf 'an at-bound payload must be persisted\n' >&2; exit 1; }
run "$home" delete-popup 2002-2

assert_exit 'persist-popup rejects a payload one byte over the limit' 2 "$home" persist-popup 2003-3 "$payload_over_limit"
[[ ! -e "$popup_dir/2003-3.json" ]] || { printf 'an over-bound payload must never be persisted\n' >&2; exit 1; }

assert_exit 'persist-popup rejects a very large payload without hanging' 2 "$home" persist-popup 2004-4 "$payload_huge"
[[ ! -e "$popup_dir/2004-4.json" ]] || { printf 'a huge payload must never be persisted\n' >&2; exit 1; }

assert_exit 'persist-history also enforces the payload bound' 2 "$home" persist-history 2004-5 "$payload_over_limit"
[[ ! -e "$history_dir/2004-5.json" ]] || { printf 'an over-bound history payload must never be persisted\n' >&2; exit 1; }

# The queue continues after an oversized persistence failure: an ordinary
# persist-popup call after the rejected ones above must still succeed, and
# no partial/corrupt JSON is ever left behind by a rejected call.
assert_exit 'persist-popup still works after an oversized-payload rejection' 0 "$home" persist-popup 2005-6 '{"id":6}'
[[ -f "$popup_dir/2005-6.json" ]] || { printf 'persistence must continue working after a bounded rejection\n' >&2; exit 1; }
run "$home" delete-popup 2005-6

# --- transactional validation: an invalid later pair leaves zero artifacts ---
# (Section 6 hardening: validate the complete argument structure before any
# image-copy side effect, so an earlier valid pair's image is never
# orphaned by a later invalid one.)
assert_exit 'persist-popup: valid first pair + invalid second pair leaves no artifacts' 2 \
  "$home" persist-popup 9001-1 '{"id":1}' appIcon "$small_source" bogus "$small_source"
[[ ! -e "$images_dir/9001-1-appIcon" ]] || { printf 'an invalid later pair must not leave an orphaned image from an earlier valid pair\n' >&2; exit 1; }
[[ ! -e "$popup_dir/9001-1.json" ]] || { printf 'an invalid later pair must not leave a JSON artifact\n' >&2; exit 1; }

assert_exit 'persist-popup: valid first pair + duplicate second role leaves no artifacts' 2 \
  "$home" persist-popup 9002-2 '{"id":2}' appIcon "$small_source" appIcon "$small_source"
[[ ! -e "$images_dir/9002-2-appIcon" ]] || { printf 'a duplicate-role rejection must not leave an orphaned image\n' >&2; exit 1; }
[[ ! -e "$popup_dir/9002-2.json" ]] || { printf 'a duplicate-role rejection must not leave a JSON artifact\n' >&2; exit 1; }

assert_exit 'persist-history: valid first pair + invalid second pair leaves no artifacts' 2 \
  "$home" persist-history 9003-3 '{"id":3}' appIcon "$small_source" bogus "$small_source"
[[ ! -e "$images_dir/9003-3-appIcon" ]] || { printf 'an invalid later pair must not leave an orphaned image (history)\n' >&2; exit 1; }
[[ ! -e "$history_dir/9003-3.json" ]] || { printf 'an invalid later pair must not leave a JSON artifact (history)\n' >&2; exit 1; }

printf '%s\n' 'security notifications state adapter ABI checks passed'
