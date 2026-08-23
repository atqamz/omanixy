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
