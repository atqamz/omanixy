# shellcheck disable=SC2154 # shared adapter state is initialized by common.bash.
brightness_display() {
  local monitor=""
  while (($#)); do
    case "$1" in
      --no-osd) shift ;;
      --monitor) (($# >= 2)) || fail 'Usage: omarchy-brightness-display [--no-osd] [--monitor name] [percent]' 2; monitor=$2; shift 2 ;;
      *) break ;;
    esac
  done
  if [[ ${1:-} == off || ${1:-} == on ]]; then
    need hyprctl
    if [[ $1 == off ]]; then
      timed 3 'display power-off' hyprctl dispatch 'hl.dsp.dpms({ action = "disable" })' >/dev/null ||
        fail "$name: display power-off failed"
      return
    fi
    if timed 3 'display state lookup' hyprctl monitors -j 2>/dev/null |
      jq -e '[.[] | select(.disabled == false)] | length > 0 and all(.dpmsStatus)' >/dev/null; then
      return
    fi
    timed 3 'display power-on' hyprctl dispatch 'hl.dsp.dpms({ action = "enable" })' >/dev/null ||
      fail "$name: display power-on failed"
    return
  fi
  need brightnessctl
  if [[ -n $monitor && ! $monitor =~ ^(eDP|LVDS|DSI)- ]]; then
    fail "$name: external-display brightness is unavailable"
  fi
  if (($# == 0)); then
    local brightness_output
    if brightness_output=$(timed 3 'brightness lookup' brightnessctl -m 2>/dev/null); then
      awk -F, '{ gsub("%", "", $4); print $4; found=1 } END { if (!found) print "unavailable" }' <<<"$brightness_output"
    else
      printf '%s\n' unavailable
    fi
    return
  fi
  (($# == 1)) || fail 'Usage: omarchy-brightness-display [--no-osd] [--monitor name] [percent]' 2
  [[ $1 =~ ^([+]?[0-9]+%|[0-9]+%-)$ ]] || fail 'Brightness must be a percentage' 2
  local absolute_brightness
  absolute_brightness=$(sed 's/%$//; s/^+//' <<<"$1")
  if [[ $1 =~ ^[+]?[0-9]+%$ && $absolute_brightness -gt 100 ]]; then
    fail 'Brightness must be between 0% and 100%' 2
  fi
  timed 3 'brightness update' brightnessctl set "$1" >/dev/null || fail "$name: brightness backend failed"
}

monitor_state() {
  (($# == 0)) || fail 'Usage: omarchy-monitor-state' 2
  need hyprctl
  need jq
  local monitors focused brightness
  monitors=$(timed 3 'monitor state lookup' hyprctl monitors all -j) || fail "$name: monitor state is unavailable"
  focused=$(jq -r '[.[] | select(.focused == true)][0].name // ""' <<<"$monitors")
  brightness=$(COMPAT_ADAPTER_NAME=omarchy-brightness-display brightness_display --monitor "$focused" 2>/dev/null || true)
  [[ -n $brightness ]] || brightness=unavailable
  printf '%s\n' "$brightness"
  jq -r '([.[] | select(.name | test("^(eDP|LVDS|DSI)-"))][0].name // ""), ([.[] | select((.name | test("^(eDP|LVDS|DSI)-")) | not)][0].name // ""), ([.[] | select((.name | test("^(eDP|LVDS|DSI)-")) and .disabled != true)][0].name // ""), ([.[] | select(.mirrorOf != "none") | if (.name | test("^(eDP|LVDS|DSI)-")) then .mirrorOf else .name end][0] // ""), ([.[] | select(.focused == true)][0].name // ""), ([.[] | select(.focused == true)][0].scale // "")' <<<"$monitors"
  jq -c '[.[] | {name, enabled:(.disabled != true), focused:(.focused == true), width, height}]' <<<"$monitors"
}

monitor_config_mode() {
  local file="$config_home/hypr/monitors.lua"
  [[ -f $file ]] || { printf 'none\n'; return; }
  if grep -q '^local omarchy_monitor_scale = ' "$file"; then
    printf 'omarchy\n'
  elif grep -Eq '^hl\.monitor\(\{ output = "", mode = "preferred", position = "auto", scale = ("auto"|[0-9.]+) \}\)$' "$file"; then
    printf 'generic\n'
  else
    printf 'none\n'
  fi
}

persist_monitor_scale() {
  local mode=$1 scale=$2 file="$config_home/hypr/monitors.lua" temporary gdk_scale
  [[ $mode == none ]] && return 0
  gdk_scale=$(awk -v scale="$scale" 'BEGIN { printf "%d", int(scale + 0.5) }')
  temporary=$(mktemp "${file}.XXXXXX") || return 1
  trap 'rm -f -- "$temporary"; trap - RETURN' RETURN
  if [[ $mode == omarchy ]]; then
    sed -E \
      -e "s|^local omarchy_monitor_scale = .*|local omarchy_monitor_scale = $scale|" \
      -e "s|^local omarchy_gdk_scale = .*|local omarchy_gdk_scale = $gdk_scale|" \
      "$file" >"$temporary" || return 1
  else
    sed -E \
      -e "s|^(hl\.monitor\(\{ output = \"\", mode = \"preferred\", position = \"auto\", scale = ).*( \}\))$|\1$scale\2|" \
      -e "s|^hl\.env\(\"GDK_SCALE\", \".*\"\)$|hl.env(\"GDK_SCALE\", \"$gdk_scale\")|" \
      "$file" >"$temporary" || return 1
  fi
  chmod --reference="$file" "$temporary" || return 1
  mv -f -- "$temporary" "$file" || return 1
  trap - RETURN
}

monitor_clean_scale() {
  awk -v requested="$1" -v width="$2" -v height="$3" '
    function gcd(a, b, remainder) {
      while (b) { remainder = a % b; a = b; b = remainder }
      return a
    }
    BEGIN {
      divisor = gcd(width * 120, height * 120)
      units = int(requested * 120 + 0.5)
      if (units > divisor) units = divisor
      while (divisor % units != 0) units++
      printf "%g\n", units / 120
    }
  '
}

monitor_step_scale() {
  awk -v current="$1" -v direction="$2" -v width="$3" -v height="$4" '
    function gcd(a, b, remainder) {
      while (b) { remainder = a % b; a = b; b = remainder }
      return a
    }
    function clean(scale, divisor, units) {
      divisor = gcd(width * 120, height * 120)
      units = int(scale * 120 + 0.5)
      if (units > divisor) units = divisor
      while (divisor % units != 0) units++
      return units / 120
    }
    BEGIN {
      count = split("1 1.25 1.6 2 3 4", scales, " ")
      for (i = 1; i <= count; i++) {
        effective = clean(scales[i])
        key = sprintf("%.8f", effective)
        difference = scales[i] - effective
        if (difference < 0) difference = -difference
        if (!(key in effective_index)) {
          effective_index[key] = ++effective_count
          effective_scales[effective_count] = effective
          labels[effective_count] = scales[i]
          distances[effective_count] = difference
        } else {
          bucket = effective_index[key]
          if (difference < distances[bucket]) {
            labels[bucket] = scales[i]
            distances[bucket] = difference
          }
        }
      }
      nearest = 1
      distance = 1e9
      for (i = 1; i <= effective_count; i++) {
        difference = current - effective_scales[i]
        if (difference < 0) difference = -difference
        if (difference < distance) { distance = difference; nearest = i }
      }
      if (direction == "up" && nearest < effective_count) nearest++
      if (direction == "down" && nearest > 1) nearest--
      print labels[nearest]
    }
  '
}

monitor_scaling() {
  (($# <= 1)) || fail 'Usage: omarchy-hyprland-monitor-scaling [up|down|SCALE]' 2
  need hyprctl
  need jq
  local info name="" old_scale width height refresh_rate mode config_mode
  info=$(timed 3 'focused monitor lookup' hyprctl monitors -j | jq -e -c '.[] | select(.focused == true)') || fail "$name: focused monitor is unavailable"
  name=$(jq -r .name <<<"$info")
  old_scale=$(jq -er '.scale | numbers' <<<"$info") || fail "$name: focused monitor scale is unavailable"
  width=$(jq -er '.width | numbers | select(. > 0)' <<<"$info") || fail "$name: focused monitor width is unavailable"
  height=$(jq -er '.height | numbers | select(. > 0)' <<<"$info") || fail "$name: focused monitor height is unavailable"
  refresh_rate=$(jq -er '.refreshRate | numbers | select(. > 0)' <<<"$info") || fail "$name: focused monitor refresh rate is unavailable"
  mode="${width}x${height}@${refresh_rate}"
  if (($# == 0)); then jq -r .scale <<<"$info"; return; fi
  local requested_scale
  case $1 in
    up|down) requested_scale=$(monitor_step_scale "$old_scale" "$1" "$width" "$height") ;;
    *) requested_scale=$1 ;;
  esac
  if [[ ! $requested_scale =~ ^[0-9]+(\.[0-9]+)?$ ]] ||
    ! awk -v scale="$requested_scale" 'BEGIN { exit !(scale >= 1 && scale <= 4) }'; then
    fail 'Monitor scale must be between 1 and 4, or up/down' 2
  fi
  local scale
  scale=$(monitor_clean_scale "$requested_scale" "$width" "$height") || fail "$name: monitor scale is invalid"
  config_mode=$(monitor_config_mode)
  local command=(hyprctl eval "hl.monitor({ output = \"$name\", mode = \"$mode\", position = \"auto\", scale = $scale })")
  local rollback_command=(hyprctl eval "hl.monitor({ output = \"$name\", mode = \"$mode\", position = \"auto\", scale = $old_scale })")
  if ! timed 3 'monitor scaling update' "${command[@]}" >/dev/null; then
    if timed 3 'monitor scaling rollback' "${rollback_command[@]}" >/dev/null; then
      fail "$name: Hyprland rejected monitor scale; previous live scale was restored"
    fi
    fail "$name: Hyprland rejected monitor scale and live-scale rollback failed"
  fi
  if ! persist_monitor_scale "$config_mode" "$scale"; then
    if timed 3 'monitor scaling rollback' "${rollback_command[@]}" >/dev/null; then
      fail "$name: monitor scale configuration failed; previous live scale was restored"
    fi
    fail "$name: monitor scale configuration failed and live-scale rollback failed"
  fi
}

display_text_size() {
  (($# <= 1)) || fail 'Usage: omarchy-display-text-size [size|reset]' 2
  local file="$config_home/omarchy/shell.toml" action=${1:-query} size gtk_old gtk_new terminal_pt
  local temporary directory backup moved=0 apply_shell=true
  local -a terminal_files=()
  if [[ $action == -h || $action == --help ]]; then
    printf 'Usage: omarchy-display-text-size [size|reset]\n'
    return
  fi
  need gsettings
  case $action in
    query)
      local shell_size gtk_size terminal_size
      shell_size=$(awk '
        /^[[:space:]]*\[/ { in_font = ($0 ~ /^[[:space:]]*\[font\]/); next }
        in_font && /^[[:space:]]*base-size[[:space:]]*=/ {
          sub(/^[^=]*=[[:space:]]*/, "")
          sub(/[[:space:]]*(#.*)?$/, "")
          print
          exit
        }
      ' "$file" 2>/dev/null || true)
      gtk_size=$(timed 3 'GTK text-size lookup' gsettings get org.gnome.desktop.interface text-scaling-factor) ||
        fail "$name: GTK text-size lookup failed"
      terminal_size=n/a
      for terminal in ghostty alacritty kitty foot; do
        case $terminal in
          ghostty) terminal_file="$config_home/ghostty/config"; pattern='^font-size = ' ;;
          alacritty) terminal_file="$config_home/alacritty/alacritty.toml"; pattern='^size[[:space:]]*=' ;;
          kitty) terminal_file="$config_home/kitty/kitty.conf"; pattern='^font_size[[:space:]]+' ;;
          foot) terminal_file="$config_home/foot/foot.ini"; pattern=':size=' ;;
        esac
        if [[ -f $terminal_file ]]; then
          terminal_size=$(awk -v pattern="$pattern" '$0 ~ pattern { match($0, /[0-9]+([.][0-9]+)?/); if (RSTART) { print substr($0, RSTART, RLENGTH); exit } }' "$terminal_file" || true)
          [[ -n $terminal_size ]] || terminal_size=n/a
          break
        fi
      done
      printf 'text size: %s px\ngtk text-scaling-factor: %s\nterminal font: %s pt\n' \
        "${shell_size:-12 (default)}" "$gtk_size" "$terminal_size"
      return
      ;;
    reset|default) action=reset; size=12 ;;
    *)
      [[ $action =~ ^[0-9]+$ && $action -ge 9 && $action -le 20 ]] ||
        fail 'Text size must be an integer between 9 and 20' 2
      size=$action
      ;;
  esac
  [[ ! -e $file || ( -f $file && ! -L $file ) ]] || fail "$name: shell.toml is not a regular file or is a symlink"
  if [[ -f $file ]] && ! awk '
    /^[[:space:]]*$/ || /^[[:space:]]*#/ { next }
    /^[[:space:]]*\[font\][[:space:]]*(#.*)?$/ { count++; next }
    /^[[:space:]]*\[[^][]+\][[:space:]]*(#.*)?$/ { next }
    /^[[:space:]]*\[/ { invalid=1; next }
    /^[[:space:]]*[^=[:space:]][^=]*=[[:space:]]*/ { next }
    { invalid=1 }
    END { exit (invalid || count > 1) }
  ' "$file"; then
    fail "$name: shell.toml has malformed or duplicate font sections"
  fi
  gtk_old=$(timed 3 'GTK text-size lookup' gsettings get org.gnome.desktop.interface text-scaling-factor) ||
    fail "$name: GTK text-size lookup failed"
  if [[ $action == reset ]]; then gtk_new=1.0; else
    local gtk_font_pt
    gtk_font_pt=$(timed 3 'GTK font lookup' gsettings get org.gnome.desktop.interface font-name |
      sed -n -E "s/^.* ([0-9]+([.][0-9]+)?)'.*$/\1/p")
    [[ $gtk_font_pt =~ ^[0-9]+([.][0-9]+)?$ ]] || gtk_font_pt=11
    gtk_new=$(awk -v size="$size" -v font="$gtk_font_pt" 'BEGIN { printf "%.4f", int(font * size / 12 + 0.5) / font }')
  fi
  terminal_pt=$(awk -v size="$size" 'BEGIN { printf "%d", int(size * 9 / 12 + 0.5) }')
  mkdir -p "${file%/*}" || fail "$name: configuration directory is unavailable"
  directory=$(mktemp -d "${file%/*}/.text-size.XXXXXX") || fail "$name: configuration staging directory could not be created"
  text_size_directory=$directory
  backup="$directory/backup"
  mkdir -p "$backup" || fail "$name: configuration staging directory could not be created"
  shell_existed=false
  trap 'rm -rf -- "$text_size_directory"' EXIT
  if [[ -f $file ]]; then
    shell_existed=true
    cp -p -- "$file" "$backup/shell.toml" || fail "$name: shell.toml backup could not be created"
    awk -v size="$size" -v reset="$([[ $action == reset ]] && echo 1 || echo 0)" '
      BEGIN { in_font=0; done=0 }
      /^[[:space:]]*\[/ {
        if (in_font && !reset && !done) { print "base-size = " size; done=1 }
        in_font = ($0 ~ /^[[:space:]]*\[font\]/)
        print
        next
      }
      in_font && /^[[:space:]]*base-size[[:space:]]*=/ { if (!reset && !done) { print "base-size = " size; done=1 }; next }
      { print }
      END { if (!reset && !done) print "\n[font]\nbase-size = " size }
    ' "$file" > "$directory/shell.toml" || fail "$name: shell.toml could not be staged"
  else
    if [[ $action == reset ]]; then
      apply_shell=false
      : > "$directory/shell.toml"
    else
      printf '[font]\nbase-size = %s\n' "$size" > "$directory/shell.toml"
    fi
  fi
  if [[ -f $file ]]; then chmod --reference="$file" "$directory/shell.toml" || fail "$name: shell.toml permissions could not be preserved"; fi
  for terminal in ghostty alacritty kitty foot; do
    case $terminal in
      ghostty) terminal_file="$config_home/ghostty/config"; replacement="font-size = $terminal_pt"; expression='^font-size = .*' ;;
      alacritty) terminal_file="$config_home/alacritty/alacritty.toml"; replacement="size = $terminal_pt"; expression='^size[[:space:]]*=.*' ;;
      kitty) terminal_file="$config_home/kitty/kitty.conf"; replacement="font_size $terminal_pt.0"; expression='^font_size[[:space:]]+.*' ;;
      foot) terminal_file="$config_home/foot/foot.ini"; replacement=":size=$terminal_pt"; expression=':size=[0-9.]*' ;;
    esac
    [[ -f $terminal_file ]] || continue
    [[ -f $terminal_file && ! -L $terminal_file ]] || fail "$name: terminal configuration is a symlink"
    terminal_files+=("$terminal_file")
    target="$directory/$(basename "$terminal_file")"
    cp -p -- "$terminal_file" "$backup/$(basename "$terminal_file")" || fail "$name: terminal configuration backup failed"
    sed -E "s|$expression|$replacement|" "$terminal_file" > "$target" || fail "$name: terminal configuration could not be staged"
    chmod --reference="$terminal_file" "$target" || fail "$name: terminal configuration permissions could not be preserved"
  done
  if [[ $action == reset ]]; then
    timed 3 'GTK text-size reset' gsettings reset org.gnome.desktop.interface text-scaling-factor || {
      fail "$name: GTK text-size reset failed"
    }
  else
    timed 3 'GTK text-size update' gsettings set org.gnome.desktop.interface text-scaling-factor "$gtk_new" || {
      fail "$name: GTK text-size update failed"
    }
  fi
  if $apply_shell && ! mv -f -- "$directory/shell.toml" "$file"; then
    if timed 3 'GTK text-size rollback' gsettings set org.gnome.desktop.interface text-scaling-factor "$gtk_old" >/dev/null; then
      fail "$name: shell.toml could not be replaced; GTK setting was restored"
    fi
    fail "$name: shell.toml replacement failed and GTK rollback failed"
  fi
  if $apply_shell; then moved=1; else rm -f -- "$directory/shell.toml"; fi
  for terminal_file in "${terminal_files[@]}"; do
    target="$directory/$(basename "$terminal_file")"
    if ! mv -f -- "$target" "$terminal_file"; then
      local rollback_status=0
      if ((moved)); then
        if $shell_existed; then
          cp -p -- "$backup/shell.toml" "$file" || rollback_status=1
        else
          rm -f -- "$file" || rollback_status=1
        fi
      fi
      for rollback_file in "${terminal_files[@]}"; do
        if [[ -f $backup/$(basename "$rollback_file") ]] &&
          ! cp -p -- "$backup/$(basename "$rollback_file")" "$rollback_file"; then
          rollback_status=1
        fi
      done
      timed 3 'GTK text-size rollback' gsettings set org.gnome.desktop.interface text-scaling-factor "$gtk_old" >/dev/null || rollback_status=1
      if ((rollback_status == 0)); then
        fail "$name: text-size update failed; previous settings were restored"
      fi
      fail "$name: text-size update failed and rollback was incomplete"
    fi
  done
  if [[ -f $config_home/foot/foot.ini ]] && timed 2 'Foot process lookup' pgrep -x foot >/dev/null 2>&1; then
    local foot_notification_file="${XDG_RUNTIME_DIR:-/tmp}/omarchy-display-text-size.foot-notif-id"
    local previous_notification_id=""
    [[ -f $foot_notification_file ]] && read -r previous_notification_id <"$foot_notification_file" 2>/dev/null || true
    local -a notification_replacement=()
    [[ $previous_notification_id =~ ^[0-9]+$ ]] && notification_replacement=(-r "$previous_notification_id")
    local notification_id
    notification_id=$(notification_send \
      'Restart Foot to apply the new terminal font size' \
      "${notification_replacement[@]}" -p 2>/dev/null) || true
    if [[ $notification_id =~ ^[0-9]+$ ]]; then
      printf '%s\n' "$notification_id" >"$foot_notification_file" || true
    fi
  fi
  timed 2 'kitty font reload' pkill -USR1 kitty >/dev/null 2>&1 || true
  timed 2 'Ghostty font reload' pkill -SIGUSR2 ghostty >/dev/null 2>&1 || true
  rm -rf -- "$directory"
  trap - EXIT
}
