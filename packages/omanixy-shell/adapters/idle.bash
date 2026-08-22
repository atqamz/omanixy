idle_state_marker_path() {
  [[ -n ${HOME:-} ]] || return 2
  [[ $HOME == /* ]] || return 2
  printf '%s\n' "$HOME/.local/state/omarchy/indicators/stay-awake"
}

idle_state_probe() {
  (($# == 0)) || exit 2
  local marker parent
  marker=$(idle_state_marker_path) || exit 2
  parent=${marker%/*}
  if [[ -d $parent && ! -x $parent ]]; then
    exit 2
  fi
  if [[ -e $marker ]]; then
    exit 0
  fi
  exit 1
}

idle_state_set_awake() {
  local marker parent
  marker=$(idle_state_marker_path) || exit 2
  parent=${marker%/*}
  ( umask 022 && mkdir -p -- "$parent" ) 2>/dev/null || exit 2
  ( umask 022 && : > "$marker" ) 2>/dev/null || exit 2
  exit 0
}

idle_state_set_idle() {
  local marker
  marker=$(idle_state_marker_path) || exit 2
  rm -f -- "$marker" 2>/dev/null || exit 2
  exit 0
}

idle_state() {
  local verb=${1:-}
  case $verb in
    probe)
      shift
      idle_state_probe "$@"
      ;;
    set)
      case ${2:-} in
        awake)
          (($# == 2)) || exit 2
          idle_state_set_awake
          ;;
        idle)
          (($# == 2)) || exit 2
          idle_state_set_idle
          ;;
        *) exit 2 ;;
      esac
      ;;
    *) exit 2 ;;
  esac
}
