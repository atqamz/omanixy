notification_state_home_valid() {
  [[ -n ${HOME:-} ]] || return 1
  [[ $HOME == /* ]] || return 1
  return 0
}

# Fixed ownership root - never XDG_STATE_HOME-relative, matching the pinned
# Omarchy compatibility path every other notification consumer already
# reads/writes. No caller (QML or otherwise) may override this.
notification_state_root() {
  printf '%s\n' "$HOME/.local/state/omarchy"
}

notification_state_popup_dir() {
  printf '%s/notifications\n' "$(notification_state_root)"
}

notification_state_history_dir() {
  printf '%s/notifications/history\n' "$(notification_state_root)"
}

notification_state_images_dir() {
  printf '%s/notifications/images\n' "$(notification_state_root)"
}

# The only identity shape a stem may take: the exact
# "<timestamp>-<originalId>" format the adapted NotificationLogic.js
# generates (see imageStem). This single regex is sufficient to rule out a
# leading slash, "..", glob metacharacters, and an empty stem all at once -
# nothing but digits and one literal hyphen is ever accepted.
notification_state_stem_valid() {
  [[ $1 =~ ^[0-9]+-[0-9]+$ ]]
}

notification_state_role_valid() {
  [[ $1 == appIcon || $1 == image ]]
}

# Bounded, best-effort image copy. A missing/unreadable/oversized/non-regular
# source degrades to "no persisted image" - it never fails the caller, which
# is always in the middle of persisting the notification's own JSON and must
# not lose that over an unrelated image problem. The destination is always
# derived internally (images dir + stem + role); the source is the only
# caller-influenced path, and it is never executed, sourced, or interpreted.
notification_state_copy_image() {
  local stem=$1 role=$2 source=$3 images_dir dest tmp size
  [[ $source == /* ]] || return 0
  [[ -f $source && -r $source ]] || return 0

  images_dir=$(notification_state_images_dir)
  mkdir -p -- "$images_dir" 2>/dev/null || return 0
  dest="$images_dir/$stem-$role"
  tmp="$dest.tmp.$$"

  if ! timeout 5 head -c 5242881 -- "$source" >"$tmp" 2>/dev/null; then
    rm -f -- "$tmp"
    return 0
  fi
  size=$(stat -c%s -- "$tmp" 2>/dev/null) || size=0
  if ((size > 5242880)); then
    rm -f -- "$tmp"
    return 0
  fi
  mv -f -- "$tmp" "$dest" 2>/dev/null || rm -f -- "$tmp"
  return 0
}

# Shared arg-walk for persist-popup/persist-history: stem, json, then zero to
# two "<role> <source>" pairs (bounded by the two roles Notifications ever
# persists images under - appIcon and image - each accepted at most once).
notification_state_persist_common() {
  local stem=$1 json=$2 seen_appicon=0 seen_image=0
  shift 2

  while (($#)); do
    (($# >= 2)) || return 2
    local role=$1 source=$2
    shift 2
    notification_state_role_valid "$role" || return 2
    if [[ $role == appIcon ]]; then
      ((seen_appicon == 0)) || return 2
      seen_appicon=1
    else
      ((seen_image == 0)) || return 2
      seen_image=1
    fi
    notification_state_copy_image "$stem" "$role" "$source"
  done

  printf '%s\n' "$json"
  return 0
}

notification_state_trim_history() {
  local limit=10 history_dir images_dir stale stem
  history_dir=$(notification_state_history_dir)
  images_dir=$(notification_state_images_dir)
  [[ -d $history_dir ]] || return 0

  local -a names=()
  local f
  shopt -s nullglob
  for f in "$history_dir"/*.json; do
    names+=("$(basename -- "$f")")
  done
  shopt -u nullglob

  ((${#names[@]} > limit)) || return 0

  local -a sorted
  mapfile -t sorted < <(printf '%s\n' "${names[@]}" | sort -n)
  local drop=$((${#sorted[@]} - limit))
  local i
  for ((i = 0; i < drop; i++)); do
    stale=${sorted[$i]}
    stem=${stale%.json}
    rm -f -- "$history_dir/$stale" "$images_dir/$stem"-*
  done
}

# Every popup/history file is written via persist-popup/persist-history,
# which always terminates it with exactly one trailing newline. A file torn
# by a crash mid-write may lack one - concatenating it as-is would glue its
# last line onto the next file's first line. Guarantee termination per file
# so a torn file can never corrupt an unrelated neighbor.
notification_state_cat_terminated() {
  cat -- "$1"
  [[ -z $(tail -c1 -- "$1") ]] || printf '\n'
}

notification_state_init() {
  (($# == 0)) || return 2
  notification_state_home_valid || return 2
  mkdir -p -- "$(notification_state_popup_dir)" "$(notification_state_history_dir)" "$(notification_state_images_dir)" 2>/dev/null || return 2
  return 0
}

notification_state_persist_popup() {
  (($# >= 2)) || return 2
  notification_state_home_valid || return 2
  local stem=$1
  notification_state_stem_valid "$stem" || return 2

  local payload
  payload=$(notification_state_persist_common "$@") || return $?

  local popup_dir
  popup_dir=$(notification_state_popup_dir)
  mkdir -p -- "$popup_dir" 2>/dev/null || return 2
  printf '%s\n' "$payload" >"$popup_dir/$stem.json" || return 2
  return 0
}

notification_state_persist_history() {
  (($# >= 2)) || return 2
  notification_state_home_valid || return 2
  local stem=$1
  notification_state_stem_valid "$stem" || return 2

  local payload
  payload=$(notification_state_persist_common "$@") || return $?

  local history_dir
  history_dir=$(notification_state_history_dir)
  mkdir -p -- "$history_dir" 2>/dev/null || return 2
  printf '%s\n' "$payload" >"$history_dir/$stem.json" || return 2
  notification_state_trim_history
  return 0
}

notification_state_archive_popup() {
  (($# == 1)) || return 2
  notification_state_home_valid || return 2
  local stem=$1
  notification_state_stem_valid "$stem" || return 2

  local popup_dir history_dir
  popup_dir=$(notification_state_popup_dir)
  history_dir=$(notification_state_history_dir)
  mkdir -p -- "$history_dir" 2>/dev/null || return 2

  if [[ ! -f "$popup_dir/$stem.json" ]]; then
    return 1
  fi
  mv -f -- "$popup_dir/$stem.json" "$history_dir/$stem.json" 2>/dev/null || return 2
  notification_state_trim_history
  return 0
}

notification_state_delete_popup() {
  (($# == 1)) || return 2
  notification_state_home_valid || return 2
  local stem=$1
  notification_state_stem_valid "$stem" || return 2

  local popup_dir images_dir existed=1
  popup_dir=$(notification_state_popup_dir)
  images_dir=$(notification_state_images_dir)
  [[ -f "$popup_dir/$stem.json" ]] && existed=0
  rm -f -- "$popup_dir/$stem.json" "$images_dir/$stem"-* 2>/dev/null
  ((existed == 0)) && return 0
  return 1
}

notification_state_read_popups() {
  (($# == 0)) || return 2
  notification_state_home_valid || return 2
  local popup_dir f
  popup_dir=$(notification_state_popup_dir)
  shopt -s nullglob
  for f in "$popup_dir"/*.json; do
    [[ -f $f ]] || continue
    notification_state_cat_terminated "$f"
  done
  shopt -u nullglob
  return 0
}

notification_state_read_history() {
  (($# == 0)) || return 2
  notification_state_home_valid || return 2
  local history_dir f
  history_dir=$(notification_state_history_dir)
  shopt -s nullglob
  for f in "$history_dir"/*.json; do
    [[ -f $f ]] || continue
    notification_state_cat_terminated "$f"
  done
  shopt -u nullglob
  return 0
}

notification_state_clear_history() {
  (($# == 0)) || return 2
  notification_state_home_valid || return 2
  local history_dir images_dir f stem
  history_dir=$(notification_state_history_dir)
  images_dir=$(notification_state_images_dir)
  shopt -s nullglob
  for f in "$history_dir"/*.json; do
    [[ -f $f ]] || continue
    stem=$(basename -- "$f")
    stem=${stem%.json}
    rm -f -- "$f" "$images_dir/$stem"-*
  done
  shopt -u nullglob
  return 0
}

notification_state_sweep_images() {
  (($# == 0)) || return 2
  notification_state_home_valid || return 2
  local popup_dir history_dir images_dir img base stem
  popup_dir=$(notification_state_popup_dir)
  history_dir=$(notification_state_history_dir)
  images_dir=$(notification_state_images_dir)
  shopt -s nullglob
  for img in "$images_dir"/*; do
    [[ -f $img ]] || continue
    base=$(basename -- "$img")
    if [[ $base == *.tmp.* ]]; then
      rm -f -- "$img"
      continue
    fi
    stem=${base%-*}
    if [[ -f "$popup_dir/$stem.json" || -f "$history_dir/$stem.json" ]]; then
      continue
    fi
    rm -f -- "$img"
  done
  shopt -u nullglob
  return 0
}

notification_state() {
  local verb=${1:-}
  case $verb in
    init)
      shift
      notification_state_init "$@"
      ;;
    persist-popup)
      shift
      notification_state_persist_popup "$@"
      ;;
    persist-history)
      shift
      notification_state_persist_history "$@"
      ;;
    archive-popup)
      shift
      notification_state_archive_popup "$@"
      ;;
    delete-popup)
      shift
      notification_state_delete_popup "$@"
      ;;
    read-popups)
      shift
      notification_state_read_popups "$@"
      ;;
    read-history)
      shift
      notification_state_read_history "$@"
      ;;
    clear-history)
      shift
      notification_state_clear_history "$@"
      ;;
    sweep-images)
      shift
      notification_state_sweep_images "$@"
      ;;
    *) exit 2 ;;
  esac
}
