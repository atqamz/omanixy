# shellcheck disable=SC2154
bluetooth_device() {
  (($# == 2)) || fail 'Usage: omarchy-bluetooth-device [pair|connect|disconnect|forget] <MAC>' 2
  [[ $2 =~ ^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$ ]] || fail 'Bluetooth address is invalid' 2
  need bluetoothctl
  if [[ $1 == pair || $1 == connect || $1 == forget ]]; then
    bluetooth_power on || fail "$name: Bluetooth adapter could not be powered on"
  fi
  local status=0
  case "$1" in
    pair)
      timed 20 'Bluetooth pairing' bluetoothctl pair "$2" >/dev/null || status=1
      timed 10 'Bluetooth trust' bluetoothctl trust "$2" >/dev/null || status=1
      timed 20 'Bluetooth connection' bluetoothctl connect "$2" >/dev/null || status=1
      ;;
    connect)
      timed 10 'Bluetooth trust' bluetoothctl trust "$2" >/dev/null || status=1
      timed 20 'Bluetooth connection' bluetoothctl connect "$2" >/dev/null || status=1
      ;;
    disconnect) timed 10 'Bluetooth disconnection' bluetoothctl disconnect "$2" >/dev/null || status=1 ;;
    forget)
      timed 10 'Bluetooth disconnection before removal' bluetoothctl disconnect "$2" >/dev/null || status=1
      timed 10 'Bluetooth device removal' bluetoothctl remove "$2" >/dev/null || status=1
      ;;
    *) fail 'Usage: omarchy-bluetooth-device [pair|connect|disconnect|forget] <MAC>' 2 ;;
  esac
  ((status == 0)) || fail "$name: Bluetooth operation failed"
}

bluetooth_power() {
  (($# == 1)) || fail 'Usage: omarchy-bluetooth-power [on|off|toggle|is-on]' 2
  need bluetoothctl
  [[ $1 == is-on ]] || need rfkill
  local deadline
  controllers() {
    timed 2 'Bluetooth controller lookup' bluetoothctl list | awk '{print $2}'
  }
  powered() {
    local current_controller
    current_controller=$(controllers) || return 1
    while read -r current_controller; do
      [[ -n $current_controller ]] || continue
      if [[ $(timed 2 'Bluetooth power state lookup' bluetoothctl show "$current_controller") == *'Powered: yes'* ]]; then
        return 0
      fi
    done <<<"$current_controller"
    return 1
  }
  power_on() {
    timed 5 'Bluetooth rfkill unblock' rfkill unblock bluetooth || return 1
    deadline=$((SECONDS + ${OMARCHY_BLUETOOTH_POWER_WAIT_SECONDS:-2}))
    while :; do
      powered && return 0
      ((SECONDS < deadline)) || break
      timed 1 'Bluetooth power-state wait' sleep 0.2 || return 1
    done
    timed 5 'Bluetooth adapter power-on' bluetoothctl power on >/dev/null || return 1
    powered || fail "$name: Bluetooth adapter did not come up"
  }
  case "$1" in
    on) power_on || fail "$name: Bluetooth adapter could not be powered on" ;;
    off) timed 5 'Bluetooth rfkill block' rfkill block bluetooth || fail "$name: Bluetooth adapter could not be powered off" ;;
    toggle)
      if powered; then
        timed 5 'Bluetooth rfkill block' rfkill block bluetooth ||
          fail "$name: Bluetooth adapter could not be powered off"
      else
        power_on || fail "$name: Bluetooth adapter could not be powered on"
      fi
      ;;
    is-on) powered ;;
    *) fail 'Usage: omarchy-bluetooth-power [on|off|toggle|is-on]' 2 ;;
  esac
}

battery_status() {
  (($# == 1)) && [[ $1 == --shell ]] || fail 'Usage: omarchy-battery-status --shell' 2
  need upower
  local battery_devices battery battery_info percentage percentage_raw capacity time_remaining power_rate_raw power_rate
  local native_path battery_path state threshold_start threshold_end cycles ac_online charge_idle charge_holding
  battery_devices=$(timed 3 'battery device enumeration' upower -e 2>/dev/null) ||
    fail "$name: battery information is unavailable"
  battery=$(awk '/battery|BAT/ { print; exit }' <<<"$battery_devices")
  [[ -n $battery ]] || return 0
  battery_info=$(timed 3 'battery information lookup' upower -i "$battery") ||
    fail "$name: battery information is unavailable"
  percentage_raw=$(awk '/percentage:/ { print $2; exit }' <<<"$battery_info")
  [[ $percentage_raw =~ ^[0-9]+%$ ]] || fail "$name: battery percentage is malformed"
  percentage=${percentage_raw%\%}
  ((percentage <= 100)) || fail "$name: battery percentage is malformed"
  capacity=$(awk '/energy-full:/ { if ($2 ~ /^[0-9]+(\.[0-9]+)?$/ && $3 == "Wh") { printf "%d", $2; exit } }' <<<"$battery_info")
  [[ -n $capacity ]] || capacity=unknown
  time_remaining=$(awk '/time to (empty|full):/ {
    if ($4 !~ /^[0-9]+(\.[0-9]+)?$/ || $5 !~ /^(second|seconds|minute|minutes|hour|hours)$/) exit 1
    value = $4
    unit = $5
    if (unit ~ /^second/) print "unknown"
    else if (unit ~ /^minute/) printf "%dm", int(value)
    else {
      hours = int(value)
      minutes = int((value - hours) * 60)
      if (minutes > 0) printf "%dh %dm", hours, minutes
      else printf "%dh", hours
    }
    exit
  }' <<<"$battery_info") || fail "$name: battery time estimate is malformed"
  [[ -n $time_remaining ]] || time_remaining=unknown
  power_rate_raw=$(awk '/energy-rate:/ { if ($2 ~ /^[0-9]+(\.[0-9]+)?$/ && $3 == "W") print $2; exit }' <<<"$battery_info")
  native_path=$(awk '/native-path:/ { print $2; exit }' <<<"$battery_info")
  battery_path="${OMARCHY_POWER_SUPPLY_PATH:-/sys/class/power_supply}/${native_path:-__missing__}"
  if [[ -r $battery_path/power_now ]] && power_rate_raw=$(awk '$1 ~ /^[0-9]+$/ { print $1 / 1000000; found=1 } END { exit !found }' "$battery_path/power_now"); then
    :
  elif [[ -r $battery_path/current_now && -r $battery_path/voltage_now ]]; then
    current_now=$(<"$battery_path/current_now")
    voltage_now=$(<"$battery_path/voltage_now")
    if [[ $current_now =~ ^[0-9]+$ && $voltage_now =~ ^[0-9]+$ ]]; then
      power_rate_raw=$(awk -v current="$current_now" -v voltage="$voltage_now" 'BEGIN { print current * voltage / 1000000000000 }')
    fi
  fi
  if [[ $power_rate_raw =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
    power_rate=$(awk -v rate="$power_rate_raw" 'BEGIN { rounded = sprintf("%.1f", rate); sub(/\.0$/, "", rounded); print rounded }')
  else
    power_rate=unknown
  fi
  state=$(awk '/state:/ { print $2; exit }' <<<"$battery_info")
  [[ $state =~ ^(unknown|charging|discharging|empty|fully-charged|pending-charge|pending-discharge)$ ]] ||
    fail "$name: battery state is malformed"
  threshold_start=$(awk '/charge-start-threshold:/ { if ($2 !~ /^[0-9]+%$/) exit 1; gsub(/%/, "", $2); if ($2 > 100) exit 1; print $2; exit }' <<<"$battery_info") ||
    fail "$name: battery charge threshold is malformed"
  threshold_end=$(awk '/charge-end-threshold:/ { if ($2 !~ /^[0-9]+%$/) exit 1; gsub(/%/, "", $2); if ($2 > 100) exit 1; print $2; exit }' <<<"$battery_info") ||
    fail "$name: battery charge threshold is malformed"
  if [[ -z $threshold_end ]]; then
    for threshold_file in "${OMARCHY_POWER_SUPPLY_PATH:-/sys/class/power_supply}"/BAT*/charge_control_end_threshold; do
      [[ -r $threshold_file ]] || continue
      threshold_end=$(<"$threshold_file")
      [[ $threshold_end =~ ^[0-9]+$ && $threshold_end -le 100 ]] ||
        fail "$name: battery charge threshold is malformed"
      break
    done
  fi
  if [[ -z $threshold_start ]]; then
    for threshold_file in "${OMARCHY_POWER_SUPPLY_PATH:-/sys/class/power_supply}"/BAT*/charge_control_start_threshold; do
      [[ -r $threshold_file ]] || continue
      threshold_start=$(<"$threshold_file")
      [[ $threshold_start =~ ^[0-9]+$ && $threshold_start -le 100 ]] ||
        fail "$name: battery charge threshold is malformed"
      break
    done
  fi
  ac_online=false
  for supply in "${OMARCHY_POWER_SUPPLY_PATH:-/sys/class/power_supply}"/*; do
    [[ -r $supply/type && -r $supply/online ]] || continue
    [[ $(<"$supply/type") == Mains && $(<"$supply/online") == 1 ]] || continue
    ac_online=true
    break
  done
  charge_idle=false
  [[ $power_rate_raw =~ ^[0-9]+(\.[0-9]+)?$ ]] && awk -v rate="$power_rate_raw" 'BEGIN { exit !(rate <= 0.2) }' && charge_idle=true
  charge_holding=false
  if [[ $ac_online == true && $threshold_end =~ ^[0-9]+$ ]]; then
    if [[ $state == pending-charge || $state == fully-charged && $percentage -lt 99 ]]; then
      charge_holding=true
    elif [[ $state == charging && $charge_idle == true && $threshold_end -lt 99 && $percentage -ge $threshold_end ]]; then
      charge_holding=true
    fi
  fi
  printf 'percentage\t%s%%\nstate\t%s\nrate\t%sW\nsize\t%sWh\ntime\t%s\n' \
    "$percentage" "$(if [[ $charge_holding == true ]]; then printf holding; else printf '%s' "$state"; fi)" "$power_rate" "$capacity" "$time_remaining"
  cycles=""
  for cycle_file in "${OMARCHY_POWER_SUPPLY_PATH:-/sys/class/power_supply}"/BAT*/cycle_count; do
    [[ -r $cycle_file ]] || continue
    cycles=$(<"$cycle_file")
    [[ $cycles =~ ^[0-9]+$ ]] || fail "$name: battery cycle count is malformed"
    break
  done
  [[ -n $cycles ]] && printf 'cycles\t%s\n' "$cycles"
  if [[ -n $threshold_end ]]; then
    if [[ -n $threshold_start && $threshold_start != "$threshold_end" ]]; then
      printf 'threshold\t%s-%s%%\n' "$threshold_start" "$threshold_end"
    else
      printf 'threshold\t%s%%\n' "$threshold_end"
    fi
  fi
}

powerprofiles_list() {
  [[ $# -le 1 && ( -z ${1:-} || ${1:-} == --active-state ) ]] || fail 'Usage: omarchy-powerprofiles-list [--active-state]' 2
  need powerprofilesctl
  local with_state=0 profiles
  [[ ${1:-} == --active-state ]] && with_state=1
  profiles=$(timed 3 'power-profile listing' powerprofilesctl list) || fail "$name: power-profile backend failed"
  [[ -n $profiles ]] || fail "$name: power-profile backend returned no profiles"
  awk -v with_state="$with_state" '
    /^[[:space:]]*[*-]?[[:space:]]*[a-zA-Z0-9-]+:$/ {
      entry = $0
      active = (entry ~ /^[[:space:]]*\*/) ? 1 : 0
      sub(/^[*[:space:]-]+/, "", entry)
      sub(/:$/, "", entry)
      print entry (with_state ? "\t" active : "")
    }
  ' <<<"$profiles" | tac
}

powerprofiles_set() {
  (($# <= 2)) || fail 'Usage: omarchy-powerprofiles-set [autodetect|ac|battery] [power-saver|balanced|performance]' 2
  need powerprofilesctl
  local action=${1:-autodetect} requested_profile=${2:-} profiles state_dir state_file profile on_battery
  [[ -z $requested_profile || $requested_profile =~ ^(power-saver|balanced|performance)$ ]] ||
    fail 'Usage: omarchy-powerprofiles-set [autodetect|ac|battery] [power-saver|balanced|performance]' 2
  case "$action" in
    autodetect)
      need busctl
      on_battery=$(timed 3 'battery-state lookup' busctl get-property org.freedesktop.UPower /org/freedesktop/UPower org.freedesktop.UPower OnBattery 2>/dev/null) ||
        fail "$name: battery state is unavailable"
      case "$on_battery" in
        'b true') action=battery ;;
        'b false') action=ac ;;
        *) fail "$name: battery state backend returned malformed data" ;;
      esac
      ;;
    ac|battery) ;;
    *) fail 'Usage: omarchy-powerprofiles-set [autodetect|ac|battery] [power-saver|balanced|performance]' 2 ;;
  esac
  profiles=$(powerprofiles_list) || fail "$name: power-profile listing failed"
  local previous_profile
  previous_profile=$(powerprofiles_list --active-state | awk -F '\t' '$2 == 1 { print $1; exit }') ||
    fail "$name: active power profile could not be determined"
  [[ -n $previous_profile ]] || fail "$name: active power profile could not be determined"
  profile_available() { grep -Fxq -- "$1" <<<"$profiles"; }
  state_dir=${OMARCHY_POWERPROFILES_STATE_DIR:-$omarchy_state/powerprofiles}
  [[ $state_dir == /* ]] || fail "$name: power-profile state directory must be absolute"
  state_file=$state_dir/$action
  if [[ -n $requested_profile ]]; then
    profile_available "$requested_profile" || fail "Power profile is not available: $requested_profile" 1
    profile=$requested_profile
  elif [[ -r $state_file ]]; then
    profile=$(<"$state_file")
  fi
  if [[ -z ${profile:-} ]] || ! profile_available "$profile"; then
    if [[ $action == ac ]] && profile_available performance; then profile=performance; else profile=balanced; fi
  fi
  profile_available "$profile" || fail "No usable power profile is available" 1
  timed 3 'power-profile selection' powerprofilesctl set "$profile" || fail "$name: power-profile backend rejected $profile"
  if [[ -n $requested_profile ]]; then
    if ! mkdir -p "$state_dir"; then
      if timed 3 'power-profile rollback' powerprofilesctl set "$previous_profile"; then
        fail "$name: power-profile state directory is unavailable; previous profile was restored"
      fi
      fail "$name: power-profile state directory is unavailable and profile rollback failed"
    fi
    local temporary
    if ! temporary=$(mktemp "$state_file.XXXXXX"); then
      if timed 3 'power-profile rollback' powerprofilesctl set "$previous_profile"; then
        fail "$name: power-profile state file could not be created; previous profile was restored"
      fi
      fail "$name: power-profile state file could not be created and profile rollback failed"
    fi
    trap 'rm -f -- "$temporary"' RETURN
    if ! printf '%s\n' "$requested_profile" >"$temporary" || ! chmod 600 "$temporary" || ! mv -f -- "$temporary" "$state_file"; then
      rm -f -- "$temporary"
      if timed 3 'power-profile rollback' powerprofilesctl set "$previous_profile"; then
        fail "$name: power-profile state could not be saved; previous profile was restored"
      fi
      fail "$name: power-profile state could not be saved and profile rollback failed"
    fi
    trap - RETURN
  fi
}

system_stats() {
  (($# == 0)) || fail 'Usage: omarchy-system-stats' 2
  local meminfo=${OMARCHY_PROC_MEMINFO:-/proc/meminfo}
  local stat_before=${OMARCHY_PROC_STAT_BEFORE:-/proc/stat}
  local stat_after=${OMARCHY_PROC_STAT_AFTER:-}
  local loadavg=${OMARCHY_PROC_LOADAVG:-/proc/loadavg}
  local total available used before after cpu load memory_values interval
  [[ -r $meminfo && -r $loadavg ]] || fail "$name: system statistics sources are unavailable"
  memory_values=$(awk '
    /^MemTotal:/ && $3 == "kB" { total = $2 }
    /^MemAvailable:/ && $3 == "kB" { available = $2 }
    END {
      if (total !~ /^[0-9]+$/ || available !~ /^[0-9]+$/ || available > total) exit 1
      printf "%s %s\n", total, available
    }
  ' "$meminfo") || fail "$name: memory statistics are malformed"
  read -r total available <<<"$memory_values"
  used=$((total - available))
  if [[ -z $stat_after ]]; then
    [[ -r $stat_before ]] || fail "$name: CPU statistics source is unavailable"
    before=$(awk '$1 == "cpu" && NF >= 5 { for (i = 2; i <= NF; i++) if ($i !~ /^[0-9]+$/) exit 1; print; exit }' "$stat_before") ||
      fail "$name: CPU statistics are malformed"
    interval=${OMARCHY_CPU_SAMPLE_INTERVAL:-0.1}
    if [[ ! $interval =~ ^[0-9]+([.][0-9]+)?$ ]] ||
      ! awk -v value="$interval" 'BEGIN { exit !(value <= 5) }'; then
      fail "$name: CPU sample interval must be a number no greater than 5 seconds"
    fi
    timed 6 'CPU statistics sample interval' sleep "$interval" ||
      fail "$name: CPU statistics sample interval failed"
    after=$(awk '$1 == "cpu" && NF >= 5 { for (i = 2; i <= NF; i++) if ($i !~ /^[0-9]+$/) exit 1; print; exit }' "$stat_before") ||
      fail "$name: CPU statistics are malformed"
  else
    [[ -r $stat_before && -r $stat_after ]] || fail "$name: CPU statistics sources are unavailable"
    before=$(awk '$1 == "cpu" && NF >= 5 { for (i = 2; i <= NF; i++) if ($i !~ /^[0-9]+$/) exit 1; print; exit }' "$stat_before") ||
      fail "$name: CPU statistics are malformed"
    after=$(awk '$1 == "cpu" && NF >= 5 { for (i = 2; i <= NF; i++) if ($i !~ /^[0-9]+$/) exit 1; print; exit }' "$stat_after") ||
      fail "$name: CPU statistics are malformed"
  fi
  cpu=$(awk '
    NR == 1 { for (i = 2; i <= NF; i++) before[i] = $i; next }
    NR == 2 {
      for (i = 2; i <= NF; i++) {
        if ($i < before[i]) exit 1
        total += $i - before[i]
        idle += (i == 5 || i == 6) ? $i - before[i] : 0
      }
    }
    END {
      if (total <= 0 || idle < 0 || idle > total) exit 1
      printf "%.0f%%\n", (total - idle) * 100 / total
    }
  ' < <(printf '%s\n%s\n' "$before" "$after")) || fail "$name: CPU statistics are invalid"
  load=$(awk '{ if ($1 !~ /^[0-9]+(\.[0-9]+)?$/) exit 1; print $1; exit }' "$loadavg") ||
    fail "$name: load statistics are malformed"
  printf 'cpu\t%s\nmemory\t%.1fGiB / %.0fGiB\nload\t%s\n' \
    "$cpu" "$(awk -v value="$used" 'BEGIN { printf "%.1f", value / 1048576 }')" \
    "$(awk -v value="$total" 'BEGIN { printf "%.0f", value / 1048576 }')" "$load"
}
