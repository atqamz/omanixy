hyprland_session_locked() {
  (($# == 0)) || fail 'Usage: omarchy-hyprland-session-locked' 2

  # Service.qml's recovery state machine only retries on exit 2; every other
  # code is a resolved state. need() exits 127 on a missing backend, which
  # would leak past that ABI, so a missing hyprctl/jq is normalized to 2
  # here instead of going through need().
  command -v hyprctl >/dev/null 2>&1 || exit 2
  command -v jq >/dev/null 2>&1 || exit 2

  local monitors state
  monitors=$(timed 3 'stranded lock lookup' hyprctl monitors -j) || exit 2
  state=$(jq '
    def blockers: .solitaryBlockedBy // [];
    def readable: blockers | index("WORKSPACE") | not;
    if   (type != "array")                  then 2
    elif any(.[]; blockers | index("LOCK")) then 0
    elif any(.[]; readable)                 then 1
    else                                         2
    end
  ' <<<"$monitors" 2>/dev/null) || exit 2
  case $state in
    0 | 1) exit "$state" ;;
    *) exit 2 ;;
  esac
}

lock_fingerprint_ready() {
  (($# == 0)) || fail 'Usage: omarchy-lock-fingerprint-ready' 2

  # fprintd-list (fprintd's utils/list.c) only distinguishes success/failure
  # via exit code 0/1, and puts every message - including errors - on
  # stdout, never stderr. A successful call still prints "has no fingers
  # enrolled" rather than failing when the daemon and reader are fine but
  # nothing is enrolled; a failed call says "No devices available" only for
  # a missing reader specifically. Anything else on either exit code (D-Bus
  # timeout, permission denial, a malformed response) is a shape this probe
  # cannot classify, so it degrades to indeterminate rather than guessing.
  #
  # A multi-reader machine can print both a negative line for one device and
  # a positive one for another in the same exit-0 run (list.c iterates every
  # device in turn), so the positive pattern must be tested first: one
  # enrolled, usable fingerprint anywhere makes the answer READY regardless
  # of what an earlier device in the loop reported.
  command -v fprintd-list >/dev/null 2>&1 || exit 2

  local user output status
  user=$(id -un) || exit 2
  if output=$(timed 3 'fingerprint enrollment lookup' fprintd-list "$user" 2>&1); then
    status=0
  else
    status=$?
  fi

  case $status in
    0)
      case $output in
        *'Fingerprints for user'*) exit 0 ;;
        *'has no fingers enrolled'*) exit 1 ;;
        *) exit 2 ;;
      esac
      ;;
    1)
      case $output in
        *'No devices available'*) exit 1 ;;
        *) exit 2 ;;
      esac
      ;;
    *) exit 2 ;;
  esac
}
