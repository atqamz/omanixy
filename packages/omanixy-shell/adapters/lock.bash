hyprland_session_locked() {
  (($# == 0)) || fail 'Usage: omarchy-hyprland-session-locked' 2
  need hyprctl
  need jq

  local monitors state
  monitors=$(timed 3 'stranded lock lookup' hyprctl monitors -j) || exit 2
  state=$(jq '
    def blockers: .solitaryBlockedBy // [];
    def readable: blockers | index("WORKSPACE") | not;
    if   any(.[]; blockers | index("LOCK")) then 0
    elif any(.[]; readable)                 then 1
    else                                         2
    end
  ' <<<"$monitors" 2>/dev/null) || exit 2
  case $state in
    0 | 1) exit "$state" ;;
    *) exit 2 ;;
  esac
}
