hyprland_session_locked() {
  (($# == 0)) || fail 'Usage: omarchy-hyprland-session-locked' 2

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
