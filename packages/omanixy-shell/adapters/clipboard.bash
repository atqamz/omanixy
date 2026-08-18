# shellcheck disable=SC2154 # shared adapter state is initialized by common.bash.
clipboard_paste_text() {
  local shift_insert=false copy_only=false history_index="" text=""
  while (($#)); do
    case "$1" in
      --shift-insert) shift_insert=true; shift ;;
      --copy-only) copy_only=true; shift ;;
      --history-index) (($# >= 2)) || fail 'Usage: omarchy-clipboard-paste-text [--shift-insert] [--copy-only] [--history-index index|text]' 2; history_index=$2; shift 2 ;;
      *) [[ -z $text ]] || fail 'Usage: omarchy-clipboard-paste-text [--shift-insert] [--copy-only] [--history-index index|text]' 2; text=$1; shift ;;
    esac
  done
  need wl-copy
  if [[ -n $history_index ]]; then
    need jq
    [[ -z $text ]] || fail 'Clipboard history selection cannot include text' 2
    [[ $history_index =~ ^[0-9]+$ ]] || fail 'Clipboard history index must be numeric' 2
    jq -e --argjson index "$history_index" '.[$index].type == "text" and (.[$index].text | type == "string")' "$omarchy_state/clipboard-history.json" >/dev/null || fail "$name: clipboard history entry is unavailable"
    jq -j --argjson index "$history_index" '.[$index].text' "$omarchy_state/clipboard-history.json" |
      timed 5 'clipboard copy' wl-copy
    $copy_only && return 0
    shift_insert=true
  else
    [[ -n $text ]] || fail 'Clipboard text is empty' 2
    printf '%s' "$text" | timed 5 'clipboard copy' wl-copy
  fi
  $copy_only && return 0
  need wtype
  timed 1 'clipboard paste delay' sleep 0.15 || fail "$name: clipboard paste delay failed"
  if $shift_insert; then timed 5 'clipboard paste' wtype -M shift -k Insert -m shift; else timed 5 'clipboard paste' wtype -- "$text"; fi
}

clipboard_paste_file() {
  local copy_only=false
  if [[ ${1:-} == --copy-only ]]; then copy_only=true; shift; fi
  (($# == 2)) || fail 'Usage: omarchy-clipboard-paste-file [--copy-only] <mime-type> <path>' 2
  [[ $1 =~ ^[[:alnum:]][[:alnum:]!#$^_.+-]*/[[:alnum:]][[:alnum:]!#$^_.+-]*$ ]] || fail 'Clipboard MIME type is invalid' 2
  [[ -r $2 ]] || fail "$name: clipboard file is unreadable"
  need wl-copy
  timed 5 'clipboard file copy' wl-copy --type "$1" < "$2"
  $copy_only && return 0
  need wtype
  timed 1 'clipboard paste delay' sleep 0.15 || fail "$name: clipboard paste delay failed"
  timed 5 'clipboard file paste' wtype -M shift -k Insert -m shift
}

clipboard_open() {
  (($# == 2)) && [[ $1 == --history-index && $2 =~ ^[0-9]+$ ]] || fail 'Usage: omarchy-clipboard-open --history-index <index>' 2
  need jq
  local type value file
  type=$(jq -er --argjson index "$2" '.[$index].type' "$omarchy_state/clipboard-history.json") || fail "$name: clipboard history entry is unavailable"
  case "$type" in
    image) value=$(jq -er --argjson index "$2" '.[$index].path' "$omarchy_state/clipboard-history.json") ;;
    text) value=$(jq -er --argjson index "$2" '.[$index].text' "$omarchy_state/clipboard-history.json") ;;
    *) fail "$name: clipboard entry type is unsupported" ;;
  esac
  need xdg-open
  if [[ $type == text ]]; then
    mkdir -p "$omarchy_state/clipboard-open" || fail "$name: clipboard-open state directory is unavailable"
    file=$(mktemp "$omarchy_state/clipboard-open/entry.XXXXXX.txt") || fail "$name: clipboard-open entry could not be created"
    if ! printf '%s' "$value" >"$file"; then
      rm -f -- "$file"
      fail "$name: clipboard-open entry could not be written"
    fi
    if ! timed 5 'clipboard entry open' xdg-open "$file" >/dev/null 2>&1; then
      rm -f -- "$file"
      fail "$name: clipboard entry opener failed"
    fi
  else
    [[ -r $value ]] || fail "$name: clipboard image is unreadable"
    if ! timed 5 'clipboard image open' xdg-open "$value" >/dev/null 2>&1; then
      fail "$name: clipboard image opener failed"
    fi
  fi
}

emoji_insert() {
  (($# == 1)) || fail 'Usage: omarchy-menu-emoji-insert <emoji>' 2
  [[ -n $1 ]] || return 0
  need wl-copy
  need setsid
  local pid status=0 cleanup_status=0 copy_status=0 copy_was_running=false
  printf '%s' "$1" | setsid --wait timeout --kill-after=1s 5s wl-copy --type text/plain --sensitive --foreground &
  pid=$!
  timed 1 'emoji paste delay' sleep 0.15 || status=$?
  timed 5 'emoji paste' wtype -M shift -k Insert -m shift 2>/dev/null || :
  if kill -0 "$pid" 2>/dev/null; then
    copy_was_running=true
    if ! kill -- "-$pid" 2>/dev/null && ! kill "$pid" 2>/dev/null; then
      cleanup_status=1
    fi
  fi
  for _ in {1..20}; do
    kill -0 "$pid" 2>/dev/null || break
    timed 1 'emoji clipboard cleanup wait' sleep 0.1 || cleanup_status=1
  done
  kill -0 "$pid" 2>/dev/null && cleanup_status=1
  if ! wait "$pid" 2>/dev/null && ! $copy_was_running; then copy_status=1; fi
  ((cleanup_status == 0)) || fail "$name: emoji clipboard cleanup failed"
  ((copy_status == 0)) || fail "$name: emoji clipboard copy failed"
  ((status == 0)) || fail "$name: emoji paste failed"
}

screenshot_rectangles() {
  local monitors clients workspace
  monitors=$(timed 3 'screenshot monitor lookup' hyprctl monitors -j) || return
  workspace=$(jq -er '[.[] | select(.focused == true)][0].activeWorkspace.id' <<<"$monitors") || return
  jq -r --argjson workspace "$workspace" '
    def format_monitor:
      .x as $x | .y as $y |
      (.width / .scale | floor) as $w |
      (.height / .scale | floor) as $h |
      if .transform == 1 or .transform == 3 then
        "\($x),\($y) \($h)x\($w)"
      else
        "\($x),\($y) \($w)x\($h)"
      end;
    .[] | select(.activeWorkspace.id == $workspace) | format_monitor
  ' <<<"$monitors"
  clients=$(timed 3 'screenshot window lookup' hyprctl clients -j) || return
  jq -r --argjson workspace "$workspace" '
    .[] | select(.workspace.id == $workspace and .hidden != true) |
    (.at[0] | tostring) + "," + (.at[1] | tostring) + " " +
    (.size[0] | tostring) + "x" + (.size[1] | tostring)
  ' <<<"$clients" | sort -u
}

screenshot_smart_selection() {
  local selection=$1 rectangles=$2 x y width height rect best_rect="" best_area=0 area
  [[ $selection =~ ^(-?[0-9]+),(-?[0-9]+)[[:space:]]([0-9]+)x([0-9]+)$ ]] || {
    printf '%s\n' "$selection"
    return
  }
  x=${BASH_REMATCH[1]}
  y=${BASH_REMATCH[2]}
  width=${BASH_REMATCH[3]}
  height=${BASH_REMATCH[4]}
  if ((width * height >= 20)); then
    printf '%s\n' "$selection"
    return
  fi
  while IFS= read -r rect; do
    [[ $rect =~ ^(-?[0-9]+),(-?[0-9]+)[[:space:]]([0-9]+)x([0-9]+)$ ]] || continue
    if ((x >= BASH_REMATCH[1] && x < BASH_REMATCH[1] + BASH_REMATCH[3] &&
      y >= BASH_REMATCH[2] && y < BASH_REMATCH[2] + BASH_REMATCH[4])); then
      area=$((BASH_REMATCH[3] * BASH_REMATCH[4]))
      if [[ -z $best_rect || $area -lt $best_area ]]; then
        best_rect=$rect
        best_area=$area
      fi
    fi
  done <<<"$rectangles"
  printf '%s\n' "${best_rect:-$selection}"
}

screenshot_set_cursor_mode() {
  local value=$1
  timed 3 'Hyprland cursor mode update' hyprctl eval "hl.config({ cursor = { no_hardware_cursors = $value } })" >/dev/null 2>&1 ||
    timed 3 'Hyprland cursor mode fallback' hyprctl keyword cursor:no_hardware_cursors "$value" >/dev/null 2>&1
}

screenshot_selection() {
  local mode=$1 rectangles selection status freeze_pid=""
  if [[ $mode == fullscreen ]]; then
    timed 3 'screenshot fullscreen lookup' hyprctl monitors -j | jq -er '
      def format_monitor:
        .x as $x | .y as $y |
        (.width / .scale | floor) as $w |
        (.height / .scale | floor) as $h |
        if .transform == 1 or .transform == 3 then
          "\($x),\($y) \($h)x\($w)"
        else
          "\($x),\($y) \($w)x\($h)"
        end;
      .[] | select(.focused == true) | format_monitor
    '
    return
  fi
  need slurp
  need hyprpicker
  rectangles=$(screenshot_rectangles) || fail "$name: screenshot selection geometry is unavailable"
  hyprpicker -r -z >/dev/null 2>&1 &
  freeze_pid=$!
  timed 1 'screenshot freeze startup' sleep 0.1 || {
    kill "$freeze_pid" 2>/dev/null || true
    wait "$freeze_pid" 2>/dev/null || true
    fail "$name: screenshot freeze could not start"
  }
  kill -0 "$freeze_pid" 2>/dev/null || fail "$name: screenshot freeze backend failed"
  # shellcheck disable=SC2329 # RETURN trap invokes this cleanup function indirectly.
  cleanup_selection() {
    if kill -0 "$freeze_pid" 2>/dev/null; then kill "$freeze_pid" 2>/dev/null || :; fi
    wait "$freeze_pid" 2>/dev/null || :
  }
  trap cleanup_selection RETURN
  if [[ $mode == windows ]]; then
    selection=$(timed 60 'screenshot window selection' slurp -r <<<"$rectangles") || status=$?
  elif [[ $mode == smart ]]; then
    selection=$(timed 60 'screenshot smart selection' slurp <<<"$rectangles") || status=$?
    [[ ${status:-0} == 0 && -n $selection ]] && selection=$(screenshot_smart_selection "$selection" "$rectangles")
  else
    selection=$(timed 60 'screenshot region selection' slurp) || status=$?
  fi
  trap - RETURN
  cleanup_selection
  if [[ ${status:-0} == 124 || ${status:-0} == 137 || ${status:-0} == 143 ]]; then
    fail "$name: screenshot selection timed out"
  fi
  [[ ${status:-0} == 0 ]] || return 0
  [[ -n $selection ]] && printf '%s\n' "$selection"
}

screenshot() {
  local editor=${OMARCHY_SCREENSHOT_EDITOR:-tensaku-edit} argument
  local -a screenshot_arguments=()
  for argument; do
    if [[ $argument == --editor=* ]]; then
      editor=${argument#--editor=}
    else
      screenshot_arguments+=("$argument")
    fi
  done
  set -- "${screenshot_arguments[@]}"
  (($# <= 2)) || fail 'Usage: omarchy-capture-screenshot [smart|region|windows|fullscreen] [slurp|copy|save] [--editor=<name>]' 2
  local mode=${1:-smart} processing=${2:-slurp}
  [[ $mode == smart || $mode == region || $mode == windows || $mode == fullscreen ]] ||
    fail 'Usage: omarchy-capture-screenshot [smart|region|windows|fullscreen] [slurp|copy|save] [--editor=<name>]' 2
  [[ $processing == slurp || $processing == copy || $processing == save ]] ||
    fail 'Usage: omarchy-capture-screenshot [smart|region|windows|fullscreen] [slurp|copy|save] [--editor=<name>]' 2
  if command -v pgrep >/dev/null 2>&1 && pgrep -x slurp >/dev/null 2>&1; then
    command -v pkill >/dev/null 2>&1 && pkill -x slurp >/dev/null 2>&1 || true
    return 0
  fi
  need grim
  need jq
  screenshot_original_cursor_mode=$(timed 3 'Hyprland cursor mode lookup' hyprctl getoption cursor:no_hardware_cursors -j | jq -er '.int') ||
    fail "$name: Hyprland cursor mode is unavailable"
  # shellcheck disable=SC2329 # EXIT trap invokes this cleanup function indirectly.
  screenshot_restore_cursor_mode() {
    screenshot_set_cursor_mode "$screenshot_original_cursor_mode" ||
      printf '%s: screenshot cursor mode restoration failed\n' "$name" >&2
  }
  trap screenshot_restore_cursor_mode EXIT
  screenshot_set_cursor_mode 0 || fail "$name: screenshot cursor mode could not be updated"
  local directory=${OMARCHY_SCREENSHOT_DIR:-${XDG_PICTURES_DIR:-}}
  if [[ -z $directory && -r $config_home/user-dirs.dirs ]]; then
    directory=$(awk -F'"' '/^XDG_PICTURES_DIR=/ { print $2; exit }' "$config_home/user-dirs.dirs")
    directory=${directory//\$HOME/$HOME}
  fi
  [[ $directory == /* ]] || directory=$HOME/Pictures
  mkdir -p "$directory" || fail "$name: screenshot directory is unavailable"
  local selection status file
  selection=$(screenshot_selection "$mode") || status=$?
  [[ ${status:-0} == 0 ]] || fail "$name: screenshot selection failed"
  [[ -n $selection ]] || return 0
  if [[ $processing == copy ]]; then
    need wl-copy
    timed 10 'screenshot capture to clipboard' grim -g "$selection" - |
      timed 5 'screenshot clipboard copy' wl-copy --type image/png ||
      fail "$name: screenshot clipboard capture failed"
    return
  fi
  file=$(mktemp "$directory/screenshot-$(date +%Y-%m-%d_%H-%M-%S)-XXXXXX.png") ||
    fail "$name: screenshot filename could not be allocated"
  if ! timed 10 'screenshot capture' grim -g "$selection" "$file"; then
    rm -f -- "$file" || printf '%s: screenshot temporary cleanup failed\n' "$name" >&2
    fail "$name: screenshot backend failed"
  fi
  printf '%s\n' "$file"
  if [[ $processing == slurp ]]; then
    if ! command -v wl-copy >/dev/null 2>&1 || ! timed 5 'screenshot clipboard copy' wl-copy --type image/png < "$file"; then
      printf '%s: screenshot captured but clipboard copy failed\n' "$name" >&2
    fi
    local editor_command
    editor_command=$(printf '%q %q' "$editor" "$file")
    COMPAT_ADAPTER_NAME=omarchy-notification-send notification_send \
      'Screenshot saved to clipboard and file' \
      'Edit with Super + Alt + , (or click this)' \
      --image "$file" --exec "$editor_command" || true
  fi
  return 0
}

remove_launcher_entry() {
  (($# == 2)) || fail 'Usage: omarchy-remove-launcher-entry <desktop-id> <name>' 2
  [[ $1 =~ ^[A-Za-z0-9][A-Za-z0-9_.@+-]*$ ]] || fail 'Desktop ID is invalid' 2
  local id=${1%.desktop} applications_dir="$data_home/applications" file="$data_home/applications/${1%.desktop}.desktop" backup
  [[ ! -L $applications_dir ]] || fail "$name: user launcher directory is a symlink"
  [[ ! -L $file ]] || fail "$name: launcher entry is a symlink"
  [[ -f $file ]] || fail "Could not find user launcher entry: $id.desktop"
  need update-desktop-database
  backup=$(mktemp "${file}.XXXXXX") || fail "$name: launcher entry backup could not be created"
  launcher_backup=$backup
  trap 'rm -f -- "$launcher_backup"' EXIT
  cp -p -- "$file" "$backup" || fail "$name: launcher entry backup could not be created"
  if ! rm -f -- "$file"; then
    fail "$name: launcher entry could not be removed"
  fi
  if ! timed 5 'desktop database update' update-desktop-database "${file%/*}" >/dev/null; then
    if mv -f -- "$backup" "$file" && timed 5 'desktop database rollback' update-desktop-database "${file%/*}" >/dev/null; then
      fail "$name: launcher entry was restored after the desktop database update failed"
    fi
    fail "$name: launcher entry removal rollback failed after the desktop database update failed"
  fi
  if ! rm -f -- "$backup"; then
    printf '%s: launcher entry backup cleanup failed\n' "$name" >&2
  fi
  trap - EXIT
}
