#!/usr/bin/env bash
set -euo pipefail

name=${COMPAT_ADAPTER_NAME:-${0##*/}}
state_home=${XDG_STATE_HOME:-$HOME/.local/state}
omarchy_state="$state_home/omarchy"

fail() {
  printf '%s\n' "$1" >&2
  exit "${2:-1}"
}

need() {
  command -v "$1" >/dev/null 2>&1 || fail "$name: required backend is unavailable: $1" 127
}

weather_location() {
  local file="$omarchy_state/settings/weather.json"
  case "${1:-}" in
    "")
      if [[ -r $file ]]; then
        jq -er '.name // empty | select(type == "string")' "$file" 2>/dev/null || true
      else
        need curl
        curl -fsS --max-time 4 'https://wttr.in/?format=%l' 2>/dev/null | sed 's/,.*//' || true
      fi
      ;;
    --set)
      (($# >= 2 && $# <= 3)) || fail 'Usage: omarchy-weather-location --set <name> [lat,lon]' 2
      local name_value=$2
      local json
      if (($# == 3)); then
        [[ $3 =~ ^-?[0-9]+(\.[0-9]+)?,-?[0-9]+(\.[0-9]+)?$ ]] || fail "Invalid coordinates: $3 (expected lat,lon)" 2
        need jq
        json=$(jq -cn --arg name "$name_value" --arg coords "$3" \
          '$coords | split(",") | {$name, latitude:(.[0] | tonumber), longitude:(.[1] | tonumber)}')
      else
        need jq
        json=$(jq -cn --arg name "$name_value" '{$name}')
      fi
      mkdir -p "${file%/*}"
      local temporary
      temporary=$(mktemp "${file}.XXXXXX")
      trap 'rm -f -- "$temporary"' RETURN
      printf '%s\n' "$json" > "$temporary"
      chmod 600 "$temporary"
      mv -f -- "$temporary" "$file"
      trap - RETURN
      ;;
    --clear)
      (($# == 1)) || fail 'Usage: omarchy-weather-location --clear' 2
      rm -f -- "$file"
      ;;
    *)
      fail 'Usage: omarchy-weather-location [--set <name> [lat,lon]|--clear]' 2
      ;;
  esac
}

pipewire_dump() {
  timeout 2s pw-dump
}

pipewire_node_name() {
  local node_id=$1
  local media_class=$2
  pipewire_dump | jq -er --argjson node_id "$node_id" --arg media_class "$media_class" '
    .[] |
    select(.type == "PipeWire:Interface:Node" and .id == $node_id and .info.props["media.class"] == $media_class) |
    .info.props["node.name"] // empty
  '
}

pipewire_node_name_by_name() {
  local node_name=$1
  local media_class=$2
  pipewire_dump | jq -er --arg node_name "$node_name" --arg media_class "$media_class" '
    .[] |
    select(.type == "PipeWire:Interface:Node" and .info.props["node.name"] == $node_name and .info.props["media.class"] == $media_class) |
    .info.props["node.name"] // empty
  '
}

audio_output_set_default() {
  (($# == 2)) || fail 'Usage: omarchy-audio-output-set-default <node-id> <sink-name>' 2
  [[ $1 =~ ^[0-9]+$ && -n $2 ]] || fail 'Usage: omarchy-audio-output-set-default <node-id> <sink-name>' 2
  need wpctl
  need pw-dump
  local resolved_name
  resolved_name=$(pipewire_node_name "$1" Audio/Sink) || fail "$name: output node is unavailable"
  [[ $resolved_name == "$2" ]] || fail "$name: output node name does not match PipeWire metadata"
  timeout 2s wpctl set-default "$1" || fail "$name: could not set PipeWire default output"
}

audio_input_set_default() {
  (($# == 2)) || fail 'Usage: omarchy-audio-input-set-default <node-id> <source-name>' 2
  [[ $1 =~ ^[0-9]+$ && -n $2 ]] || fail 'Usage: omarchy-audio-input-set-default <node-id> <source-name>' 2
  need wpctl
  need pw-dump
  local resolved_name
  resolved_name=$(pipewire_node_name "$1" Audio/Source) || fail "$name: input node is unavailable"
  [[ $resolved_name == "$2" ]] || fail "$name: input node name does not match PipeWire metadata"
  timeout 2s wpctl set-default "$1" || fail "$name: could not set PipeWire default input"
}

audio_output_sink() {
  (($# == 0)) || fail 'Usage: omarchy-audio-output-sink' 2
  need wpctl
  need pw-dump
  local default_name
  default_name=$(timeout 2s wpctl inspect @DEFAULT_AUDIO_SINK@ |
    sed -n 's/^[[:space:]]*node.name = "\(.*\)"$/\1/p' | head -n 1) || true
  [[ -n $default_name ]] || fail "$name: default output is unavailable"
  pipewire_node_name_by_name "$default_name" Audio/Sink || fail "$name: default output is unavailable"
}

audio_sink_availability() {
  (($# == 0)) || fail 'Usage: omarchy-audio-sink-availability' 2
  need pw-dump
  pipewire_dump | jq -er '
    map(select(.type == "PipeWire:Interface:Node" and .info.props["media.class"] == "Audio/Sink")) as $nodes |
    map(select(.type == "PipeWire:Interface:Port")) as $ports |
    $nodes[] |
    .id as $id |
    .info.props["node.name"] as $node |
    ($ports | map(select(.info.props["port.node"] == $id and .info.props["port.direction"] == "out"))) as $node_ports |
    [$node_ports[].info.props["port.availability"]?] as $availability |
    "\($node)\t\(if (($availability | length) == 0 or any($availability[]; . != "no")) then 1 else 0 end)"
  '
}

network_device() {
  need ip
  ip route get 1.1.1.1 2>/dev/null | awk '{ for (i = 1; i <= NF; i++) if ($i == "dev") { print $(i + 1); exit } }'
}

network_ping() {
  local host=$1
  timeout 2s ping -n -c 1 -W 1 "$host" 2>/dev/null |
    awk -F'time[=<]' '/time[=<]/ { split($2, parts, " "); print parts[1]; exit }' || true
}

network_status() {
  (($# <= 1)) || fail 'Usage: omarchy-network-status [--verbose]' 2
  need ip
  need jq
  local device
  device=$(network_device || true)
  if [[ -z $device ]]; then
    printf 'disconnected\t\t\t\n'
    return
  fi
  if [[ ! -d /sys/class/net/$device/wireless ]]; then
    if [[ ${1:-} == --verbose ]]; then
      local route_json iface gateway address prefix
      route_json=$(ip -j route get 1.1.1.1 2>/dev/null || printf '[]')
      iface=$(jq -r '.[0].dev // ""' <<<"$route_json")
      gateway=$(jq -r '.[0].gateway // ""' <<<"$route_json")
      address=$(jq -r '.[0].prefsrc // ""' <<<"$route_json")
      prefix=$(ip -j addr show "$device" 2>/dev/null | jq -r '.[0].addr_info[]? | select(.family == "inet") | .prefixlen // ""' | head -n 1 || true)
      printf 'iface\t%s\nip\t%s\nprefix\t%s\ngateway\t%s\ntype\tethernet\n' "$iface" "$address" "$prefix" "$gateway"
      [[ -r /sys/class/net/$device/speed ]] && printf 'speed\t%s\n' "$(<"/sys/class/net/$device/speed")"
      [[ -r /sys/class/net/$device/duplex ]] && printf 'duplex\t%s\n' "$(<"/sys/class/net/$device/duplex")"
      [[ -n $gateway ]] && printf 'router_ping_ms\t%s\n' "$(network_ping "$gateway")"
      printf 'internet_ping_ms\t%s\n' "$(network_ping 1.1.1.1)"
    else
      printf 'ethernet\t%s\t\t\n' "$device"
    fi
    return
  fi
  local ssid signal freq state
  if command -v nmcli >/dev/null 2>&1; then
    state=$(nmcli -t -f GENERAL.STATE device show "$device" 2>/dev/null | sed -n 's/^GENERAL.STATE://p' | head -n 1 || true)
    ssid=$(nmcli -t -f GENERAL.CONNECTION device show "$device" 2>/dev/null | sed -n 's/^GENERAL.CONNECTION://p' | head -n 1 || true)
    signal=$(nmcli -t -f IN-USE,SIGNAL device wifi list ifname "$device" --rescan no 2>/dev/null | awk -F: '$1 == "*" { print $2; exit }' || true)
  fi
  freq=$(iw dev "$device" link 2>/dev/null | awk '/freq:/ { print $2; exit }' || true)
  [[ $state == 100* || -n $ssid ]] || { printf 'disconnected\t\t\t\n'; return; }
  if [[ ${1:-} == --verbose ]]; then
    local route_json iface gateway address prefix
    route_json=$(ip -j route get 1.1.1.1 2>/dev/null || printf '[]')
    iface=$(jq -r '.[0].dev // ""' <<<"$route_json")
    gateway=$(jq -r '.[0].gateway // ""' <<<"$route_json")
    address=$(jq -r '.[0].prefsrc // ""' <<<"$route_json")
    prefix=$(ip -j addr show "$device" 2>/dev/null | jq -r '.[0].addr_info[]? | select(.family == "inet") | .prefixlen // ""' | head -n 1 || true)
    printf 'iface\t%s\nip\t%s\nprefix\t%s\ngateway\t%s\ntype\twifi\n' "$iface" "$address" "$prefix" "$gateway"
    [[ -r /sys/class/net/$device/statistics/rx_bytes ]] && printf 'rx_bytes\t%s\n' "$(<"/sys/class/net/$device/statistics/rx_bytes")"
    [[ -r /sys/class/net/$device/statistics/tx_bytes ]] && printf 'tx_bytes\t%s\n' "$(<"/sys/class/net/$device/statistics/tx_bytes")"
    local link
    link=$(iw dev "$device" link 2>/dev/null || true)
    printf 'ssid\t%s\nsignal_dbm\t%s\nfreq\t%s\n' \
      "$(awk '/SSID:/ { sub(/.*SSID: /, ""); print; exit }' <<<"$link")" \
      "$(awk '/signal:/ { print $2; exit }' <<<"$link")" \
      "$freq"
    printf 'bitrate\t%s %s\n' \
      "$(awk '/tx bitrate:/ { print $3; exit }' <<<"$link")" \
      "$(awk '/tx bitrate:/ { print $4; exit }' <<<"$link")"
    [[ -n $gateway ]] && printf 'router_ping_ms\t%s\n' "$(network_ping "$gateway")"
    printf 'internet_ping_ms\t%s\n' "$(network_ping 1.1.1.1)"
    return
  fi
  printf 'wifi\t%s\t%s\t%s\n' "${ssid:-$device}" "${signal:-}" "$freq"
}

network_qr_escape() {
  local value=$1
  value=${value//\\/\\\\}
  value=${value//;/\\;}
  value=${value//,/\\,}
  value=${value//:/\\:}
  printf '%s' "$value"
}

network_password() {
  (($# == 1)) || fail 'Usage: omarchy-network-password <interface>' 2
  need nmcli
  local interface=$1 uuid key_management password wep_key
  uuid=$(nmcli --get-values GENERAL.CON-UUID device show "$interface" | head -n 1)
  [[ -n $uuid && $uuid != -- ]] || fail 'No active Wi-Fi connection' 1
  mapfile -t fields < <(nmcli --show-secrets --escape no --get-values \
    802-11-wireless-security.key-mgmt,802-11-wireless-security.psk,802-11-wireless-security.wep-key0 \
    connection show uuid "$uuid")
  key_management=${fields[0]:-}
  password=${fields[1]:-}
  wep_key=${fields[2]:-}
  [[ $key_management != *eap* && $key_management != *ieee8021x* ]] ||
    fail 'Enterprise Wi-Fi has no shareable password' 1
  if [[ -z $key_management || $key_management == none ]]; then
    password=$wep_key
    [[ -n $password ]] || fail 'This network has no password' 1
  fi
  [[ -n $password ]] || fail 'Could not read the Wi-Fi password' 1
  printf '%s\n' "$password"
}

network_qr() {
  (($# <= 2)) || fail 'Usage: omarchy-network-qr [--meta] [interface]' 2
  need nmcli
  need qrencode
  local emit_meta=false interface="" arg uuid fields ssid key_management password hidden wep_key security payload ascii line row column
  for arg in "$@"; do
    case "$arg" in
      --meta) emit_meta=true ;;
      *) [[ -z $interface ]] || fail 'Usage: omarchy-network-qr [--meta] [interface]' 2; interface=$arg ;;
    esac
  done
  if [[ -z $interface ]]; then
    interface=$(network_device || true)
    if [[ -z $interface || ! -d /sys/class/net/$interface/wireless ]]; then
      interface=$(nmcli -t -f DEVICE,TYPE,STATE device status 2>/dev/null |
        awk -F: '$2 == "wifi" && $3 ~ /^connected/ { print $1; exit }')
    fi
  fi
  [[ $interface =~ ^[[:alnum:]_.:-]+$ ]] || fail "$name: no active Wi-Fi connection" 1
  uuid=$(timeout 2s nmcli --get-values GENERAL.CON-UUID device show "$interface" | head -n 1)
  [[ -n $uuid && $uuid != -- ]] || fail "$name: no active Wi-Fi connection" 1
  mapfile -t fields < <(timeout 2s nmcli --show-secrets --escape no --get-values \
    802-11-wireless.ssid,802-11-wireless-security.key-mgmt,802-11-wireless-security.psk,802-11-wireless.hidden,802-11-wireless-security.wep-key0 \
    connection show uuid "$uuid")
  ssid=${fields[0]:-}
  key_management=${fields[1]:-}
  password=${fields[2]:-}
  hidden=${fields[3]:-no}
  wep_key=${fields[4]:-}
  [[ -n $ssid ]] || fail "$name: could not read the Wi-Fi name" 1
  [[ $key_management != *eap* && $key_management != *ieee8021x* ]] || fail "$name: enterprise Wi-Fi cannot be shared" 1
  if [[ -n $key_management && $key_management != none ]]; then
    [[ -n $password ]] || fail "$name: could not read the Wi-Fi password" 1
    security=WPA
  elif [[ -n $wep_key ]]; then
    password=$wep_key
    security=WEP
  else
    security=nopass
  fi
  payload="WIFI:T:$security;S:$(network_qr_escape "$ssid");P:$(network_qr_escape "$password");"
  [[ $hidden == yes ]] && payload+=H:true\;
  payload+=';'
  [[ $emit_meta == true ]] && printf 'meta\t%s\t%s\t%s\n' "$interface" "$security" "$ssid"
  ascii=$(timeout 4s qrencode --type ASCII --margin 4 --output - <<<"$payload") || fail "$name: QR encoder failed" 1
  while IFS= read -r line; do
    row=
    for ((column = 0; column < ${#line}; column += 2)); do
      if [[ ${line:column:2} == *#* ]]; then row="${row}1"; else row="${row}0"; fi
    done
    printf '%s\n' "$row"
  done <<<"$ascii"
}

network_speedtest() {
  (($# == 1)) || fail 'Usage: omarchy-network-speedtest [down|up]' 2
  [[ $1 == down || $1 == up ]] || fail 'Usage: omarchy-network-speedtest [down|up]' 2
  need curl
  need ip
  need jq
  local direction=$1 iface api urls url start rx_before tx_before rx_after tx_after rate
  iface=$(network_device || true)
  [[ -n $iface && -r /sys/class/net/$iface/statistics/rx_bytes && -r /sys/class/net/$iface/statistics/tx_bytes ]] || fail "$name: no active network interface" 1
  api='https://api.fast.com/netflix/speedtest/v2?https=true&token=YXNkZmFzZGxmbnNkYWZoYXNkZmhrYWxm&urlCount=3'
  urls=$(timeout 4s curl -fsS --max-time 3 "$api" 2>/dev/null | jq -r '.targets[]?.url // empty') || fail "$name: failed to fetch speed test endpoints" 1
  [[ -n $urls ]] || fail "$name: failed to fetch speed test endpoints" 1
  rx_before=$(<"/sys/class/net/$iface/statistics/rx_bytes")
  tx_before=$(<"/sys/class/net/$iface/statistics/tx_bytes")
  start=$SECONDS
  while ((SECONDS < start + 5)); do
    url=$(printf '%s\n' "$urls" | sed -n "$(( (SECONDS - start) % $(wc -l <<<"$urls") + 1 ))p")
    if [[ $direction == down ]]; then
      timeout 2s curl -fsS -o /dev/null --max-time 2 "$url" 2>/dev/null &
    else
      head -c 1048576 /dev/zero | timeout 2s curl -fsS -o /dev/null -X POST --data-binary @- --max-time 2 "$url" 2>/dev/null &
    fi
    sleep 1
    rx_after=$(<"/sys/class/net/$iface/statistics/rx_bytes")
    tx_after=$(<"/sys/class/net/$iface/statistics/tx_bytes")
    if [[ $direction == down ]]; then
      rate=$(awk -v before="$rx_before" -v after="$rx_after" 'BEGIN { if (after < before) print 0; else print (after - before) * 8 / 1000000 }')
    else
      rate=$(awk -v before="$tx_before" -v after="$tx_after" 'BEGIN { if (after < before) print 0; else print (after - before) * 8 / 1000000 }')
    fi
    awk -v value="$rate" 'BEGIN { if (value <= 0) print "0.0"; else if (value < 10) printf "%.1f\\n", value; else printf "%.0f\\n", value }'
    rx_before=$rx_after
    tx_before=$tx_after
  done
  wait 2>/dev/null || true
}

network_available_bands() {
  local device=$1 ssid=$2 current=$3
  {
    [[ -n $current ]] && printf '%s\n' "$current"
    nmcli -t -e no -f FREQ,SSID device wifi list ifname "$device" --rescan no 2>/dev/null |
      awk -F: -v wanted="$ssid" '
        {
          name = $2
          for (i = 3; i <= NF; i++) name = name ":" $i
          if (name == wanted) print $1
        }' |
      while read -r frequency; do
        awk -v frequency="$frequency" 'BEGIN {
          gsub(/[^0-9].*/, "", frequency)
          if (frequency >= 2400 && frequency < 2500) print "2.4"
          else if (frequency >= 4900 && frequency < 5925) print "5"
          else if (frequency >= 5925 && frequency < 7125) print "6"
        }'
      done
  } | sort -u -g | tr '\n' ' ' | sed 's/ $//'
}

network_band() {
  (($# <= 1)) || fail 'Usage: omarchy-network-band [auto|2.4|5|6]' 2
  need nmcli
  need iw
  local device profile freq target ssid available previous desired
  device=$(nmcli -t -f DEVICE,TYPE,STATE device status | awk -F: '$2 == "wifi" && $3 == "connected" { print $1; exit }')
  [[ -n $device ]] || fail "$name: no connected Wi-Fi device"
  profile=$(nmcli -g GENERAL.CONNECTION device show "$device" | head -n 1)
  [[ -n $profile ]] || fail "$name: no active Wi-Fi profile"
  ssid=$(iw dev "$device" link | awk '/SSID:/ { sub(/.*SSID: /, ""); print; exit }')
  freq=$(iw dev "$device" link | awk '/freq:/ { print $2; exit }')
  target=$(awk -v frequency="$freq" 'BEGIN { if (frequency >= 2400 && frequency < 2500) print "2.4"; else if (frequency >= 4900 && frequency < 5925) print "5"; else if (frequency >= 5925 && frequency < 7125) print "6" }')
  available=$(network_available_bands "$device" "$ssid" "$target")
  if (($# == 0)); then
    printf 'band\t%s\navailable\t%s\nselected\t%s\n' "$target" "$available" "$(nmcli -g 802-11-wireless.band connection show "$profile" | sed 's/^$/auto/;s/^bg$/2.4/;s/^a$/5/;s/^6GHz$/6/')"
    return
  fi
  case "$1" in
    auto) target="" ;;
    2*)
      if [[ $1 == 2.4 ]]; then
        target='bg'
      else
        fail 'Usage: omarchy-network-band [auto|2.4|5|6]' 2
      fi
      ;;
    5) target=a ;;
    6) target=6GHz ;;
    *) fail 'Usage: omarchy-network-band [auto|2.4|5|6]' 2 ;;
  esac
  desired=$target
  if [[ -n $desired && " $available " != *" $1 "* ]]; then
    fail "$name: requested Wi-Fi band is unavailable" 1
  fi
  previous=$(nmcli -g 802-11-wireless.band connection show "$profile")
  [[ $previous == "$desired" ]] && return 0
  nmcli connection modify "$profile" 802-11-wireless.band "$desired" >/dev/null
  if ! nmcli connection up "$profile" >/dev/null 2>&1; then
    nmcli connection modify "$profile" 802-11-wireless.band "$previous" >/dev/null
    nmcli connection up "$profile" >/dev/null 2>&1 || true
    fail "$name: NetworkManager could not reassociate on the requested band"
  fi
}

network_dns() {
  (($# <= 1)) || fail 'Usage: omarchy-dns [DHCP|Cloudflare|Google]' 2
  need nmcli
  local profile dns ignore provider
  profile=$(nmcli -t -f NAME,TYPE connection show --active | awk -F: '$2 != "loopback" { print $1; exit}')
  [[ -n $profile ]] || fail "$name: no active NetworkManager connection"
  if (($# == 0)); then
    ignore=$(nmcli -g ipv4.ignore-auto-dns connection show "$profile")
    dns=$(nmcli -g ipv4.dns connection show "$profile")
    if [[ $ignore != yes && -z $dns ]]; then provider=DHCP
    elif [[ $dns == *1.1.1.1* && $dns == *1.0.0.1* ]]; then provider=Cloudflare
    elif [[ $dns == *8.8.8.8* && $dns == *8.8.4.4* ]]; then provider=Google
    else provider=Custom
    fi
    printf '%s\n' "$provider"
    return
  fi
  case "$1" in
    DHCP) nmcli connection modify "$profile" ipv4.ignore-auto-dns no ipv4.dns "" ;;
    Cloudflare) nmcli connection modify "$profile" ipv4.ignore-auto-dns yes ipv4.dns '1.1.1.1,1.0.0.1' ;;
    Google) nmcli connection modify "$profile" ipv4.ignore-auto-dns yes ipv4.dns '8.8.8.8,8.8.4.4' ;;
    Custom) fail "$name: custom DNS requires an explicit NetworkManager profile edit" 2 ;;
    *) fail 'Usage: omarchy-dns [DHCP|Cloudflare|Google]' 2 ;;
  esac
  nmcli connection up "$profile" >/dev/null 2>&1 || fail "$name: NetworkManager could not apply DNS settings"
}

bluetooth_device() {
  (($# == 2)) || fail 'Usage: omarchy-bluetooth-device [pair|connect|disconnect|forget] <MAC>' 2
  [[ $2 =~ ^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$ ]] || fail 'Bluetooth address is invalid' 2
  need bluetoothctl
  case "$1" in
    pair) timeout 20s bluetoothctl pair "$2" >/dev/null; timeout 10s bluetoothctl trust "$2" >/dev/null 2>&1 || true; timeout 20s bluetoothctl connect "$2" >/dev/null ;;
    connect) timeout 10s bluetoothctl trust "$2" >/dev/null 2>&1 || true; timeout 20s bluetoothctl connect "$2" >/dev/null ;;
    disconnect) timeout 10s bluetoothctl disconnect "$2" >/dev/null ;;
    forget) timeout 10s bluetoothctl remove "$2" >/dev/null ;;
    *) fail 'Usage: omarchy-bluetooth-device [pair|connect|disconnect|forget] <MAC>' 2 ;;
  esac
}

bluetooth_power() {
  (($# == 1)) || fail 'Usage: omarchy-bluetooth-power [on|off]' 2
  need bluetoothctl
  case "$1" in
    on|off) timeout 5s bluetoothctl power "$1" >/dev/null ;;
    *) fail 'Usage: omarchy-bluetooth-power [on|off]' 2 ;;
  esac
}

battery_status() {
  (($# == 1)) && [[ $1 == --shell ]] || fail 'Usage: omarchy-battery-status --shell' 2
  need upower
  local battery battery_info percentage capacity time_remaining power_rate_raw power_rate
  local native_path battery_path state threshold_start threshold_end cycles
  battery=$(upower -e 2>/dev/null | grep BAT | head -n 1 || true)
  [[ -n $battery ]] || return 0
  battery_info=$(upower -i "$battery") || fail "$name: battery information is unavailable"
  percentage=$(awk '/percentage:/ { gsub(/%/, "", $2); print int($2); exit }' <<<"$battery_info")
  capacity=$(awk '/energy-full:/ { printf "%d", $2; exit }' <<<"$battery_info")
  time_remaining=$(awk '/time to (empty|full):/ {
    value = $4
    unit = $5
    if (unit ~ /^minute/) printf "%dm", int(value)
    else {
      hours = int(value)
      minutes = int((value - hours) * 60)
      if (minutes > 0) printf "%dh %dm", hours, minutes
      else printf "%dh", hours
    }
    exit
  }' <<<"$battery_info")
  power_rate_raw=$(awk '/energy-rate:/ { print $2; exit }' <<<"$battery_info")
  native_path=$(awk '/native-path:/ { print $2; exit }' <<<"$battery_info")
  battery_path="${OMARCHY_POWER_SUPPLY_PATH:-/sys/class/power_supply}/$native_path"
  if [[ -r $battery_path/power_now ]]; then
    power_rate_raw=$(awk '{ print $1 / 1000000 }' "$battery_path/power_now")
  elif [[ -r $battery_path/current_now && -r $battery_path/voltage_now ]]; then
    power_rate_raw=$(awk -v current="$(<"$battery_path/current_now")" -v voltage="$(<"$battery_path/voltage_now")" 'BEGIN { print current * voltage / 1000000000000 }')
  fi
  power_rate=$(awk -v rate="${power_rate_raw:-0}" 'BEGIN { rounded = sprintf("%.1f", rate); sub(/\.0$/, "", rounded); print rounded }')
  state=$(awk '/state:/ { print $2; exit }' <<<"$battery_info")
  threshold_start=$(awk '/charge-start-threshold:/ { gsub(/%/, "", $2); print int($2); exit }' <<<"$battery_info")
  threshold_end=$(awk '/charge-end-threshold:/ { gsub(/%/, "", $2); print int($2); exit }' <<<"$battery_info")
  [[ -z $threshold_end ]] && threshold_end=$(cat "${OMARCHY_POWER_SUPPLY_PATH:-/sys/class/power_supply}"/BAT*/charge_control_end_threshold 2>/dev/null | head -n 1 || true)
  [[ -z $threshold_start ]] && threshold_start=$(cat "${OMARCHY_POWER_SUPPLY_PATH:-/sys/class/power_supply}"/BAT*/charge_control_start_threshold 2>/dev/null | head -n 1 || true)
  printf 'percentage\t%s%%\nstate\t%s\nrate\t%sW\nsize\t%sWh\ntime\t%s\n' \
    "${percentage:-0}" "${state:-unknown}" "${power_rate:-0}" "${capacity:-0}" "${time_remaining:-}"
  cycles=$(cat "${OMARCHY_POWER_SUPPLY_PATH:-/sys/class/power_supply}"/BAT*/cycle_count 2>/dev/null | head -n 1 || true)
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
  local with_state=0
  [[ ${1:-} == --active-state ]] && with_state=1
  powerprofilesctl list | awk -v with_state="$with_state" '
    /^[[:space:]]*[*-]?[[:space:]]*[a-zA-Z0-9-]+:$/ {
      entry = $0
      active = (entry ~ /^[[:space:]]*\*/) ? 1 : 0
      sub(/^[*[:space:]-]+/, "", entry)
      sub(/:$/, "", entry)
      print entry (with_state ? "\t" active : "")
    }
  ' | tac
}

powerprofiles_set() {
  (($# == 2)) || fail 'Usage: omarchy-powerprofiles-set [ac|battery] [power-saver|balanced|performance]' 2
  need powerprofilesctl
  local action=$1 profile=$2 current
  [[ $action == ac || $action == battery ]] || fail 'Usage: omarchy-powerprofiles-set [ac|battery] [power-saver|balanced|performance]' 2
  current=$(powerprofilesctl list | sed -n -E 's/^[[:space:]]*[*-]?[[:space:]]*([a-zA-Z0-9-]+):$/\1/p' | grep -Fx "$profile" || true)
  [[ -n $current ]] || fail "Power profile is not available: $profile" 2
  powerprofilesctl set "$profile"
  mkdir -p "$omarchy_state/powerprofiles"
  printf '%s\n' "$profile" > "$omarchy_state/powerprofiles/$action"
}

system_stats() {
  (($# == 0)) || fail 'Usage: omarchy-system-stats' 2
  local total available used
  total=$(awk '/^MemTotal:/ { print $2; exit }' /proc/meminfo)
  available=$(awk '/^MemAvailable:/ { print $2; exit }' /proc/meminfo)
  used=$((total - available))
  printf 'cpu\t%s\nmemory\t%.1fGB / %.0fGB\nload\t%s\n' \
    "$(awk '/^cpu / { idle=$5; total=0; for (i=2; i<=NF; i++) total += $i; if (total) printf "%.0f%%", 100 - idle * 100 / total; exit }' /proc/stat)" \
    "$((used / 1024))" "$((total / 1024))" "$(awk '{ print $1 }' /proc/loadavg)"
}

brightness_display() {
  local monitor=""
  while (($#)); do
    case "$1" in
      --no-osd) shift ;;
      --monitor) (($# >= 2)) || fail 'Usage: omarchy-brightness-display [--no-osd] [--monitor name] [percent]' 2; monitor=$2; shift 2 ;;
      *) break ;;
    esac
  done
  need brightnessctl
  if [[ -n $monitor && ! $monitor =~ ^(eDP|LVDS|DSI)- ]]; then
    fail "$name: external-display brightness is unavailable"
  fi
  if (($# == 0)); then
    brightnessctl -m 2>/dev/null | awk -F, '{ gsub("%", "", $4); print $4; found=1 } END { if (!found) print "unavailable" }'
    return
  fi
  (($# == 1)) || fail 'Usage: omarchy-brightness-display [--no-osd] [--monitor name] [percent]' 2
  [[ $1 =~ ^([+]?[0-9]+%|[0-9]+%-)$ ]] || fail 'Brightness must be a percentage' 2
  brightnessctl set "$1" >/dev/null || fail "$name: brightness backend failed"
}

monitor_state() {
  (($# == 0)) || fail 'Usage: omarchy-monitor-state' 2
  need hyprctl
  need jq
  local monitors focused brightness
  monitors=$(hyprctl monitors all -j)
  focused=$(jq -r '[.[] | select(.focused == true)][0].name // ""' <<<"$monitors")
  brightness=$(COMPAT_ADAPTER_NAME=omarchy-brightness-display brightness_display --monitor "$focused" 2>/dev/null | head -n 1 || true)
  [[ -n $brightness ]] || brightness=unavailable
  printf '%s\n' "$brightness"
  jq -r '([.[] | select(.name | test("^(eDP|LVDS|DSI)-"))][0].name // ""), ([.[] | select((.name | test("^(eDP|LVDS|DSI)-")) | not)][0].name // ""), ([.[] | select((.name | test("^(eDP|LVDS|DSI)-")) and .disabled != true)][0].name // ""), ([.[] | select(.mirrorOf != "none") | if (.name | test("^(eDP|LVDS|DSI)-")) then .mirrorOf else .name end][0] // ""), ([.[] | select(.focused == true)][0].name // ""), ([.[] | select(.focused == true)][0].scale // ""), ([.[] | {name, enabled:(.disabled != true), focused:(.focused == true), width, height}] | tostring)' <<<"$monitors"
}

monitor_scaling() {
  (($# <= 1)) || fail 'Usage: omarchy-hyprland-monitor-scaling [SCALE]' 2
  need hyprctl
  need jq
  local info name
  info=$(hyprctl monitors -j | jq -e -c '.[] | select(.focused == true)') || fail "$name: focused monitor is unavailable"
  name=$(jq -r .name <<<"$info")
  if (($# == 0)); then jq -r .scale <<<"$info"; return; fi
  if [[ ! $1 =~ ^[0-9]+(\.[0-9]+)?$ ]] || ! awk -v scale="$1" 'BEGIN { exit !(scale >= 1 && scale <= 4) }'; then
    fail 'Monitor scale must be between 1 and 4' 2
  fi
  hyprctl keyword monitor "$name,preferred,auto,auto,$1" >/dev/null || fail "$name: Hyprland rejected monitor scale"
}

display_text_size() {
  (($# == 1)) || fail 'Usage: omarchy-display-text-size <size>' 2
  local file="$HOME/.config/omarchy/shell.toml"
  [[ $1 =~ ^[0-9]+$ && $1 -ge 9 && $1 -le 20 ]] || fail 'Text size must be an integer between 9 and 20' 2
  mkdir -p "${file%/*}"
  local temporary
  temporary=$(mktemp)
  if [[ -f $file ]]; then
    awk -v size="$1" 'BEGIN { in_font=0; done=0 } /^\[font\]/{in_font=1; print; next} /^\[/{if(in_font&&!done){print "base-size = " size; done=1}; in_font=0; print; next} in_font && /^base-size[[:space:]]*=/ {if(!done){print "base-size = " size; done=1}; next} {print} END {if(in_font&&!done) print "base-size = " size; if(!done){print "[font]"; print "base-size = " size}}' "$file" > "$temporary"
  else
    printf '[font]\nbase-size = %s\n' "$1" > "$temporary"
  fi
  mv -f "$temporary" "$file"
}

weather_status() {
  (($# == 0)) || fail 'Usage: omarchy-weather-status' 2
  local place weather encoded_place
  place=$(COMPAT_ADAPTER_NAME=omarchy-weather-location weather_location)
  [[ -n $place ]] || fail "$name: weather location is unavailable"
  need curl
  encoded_place=$(jq -rn --arg place "$place" '$place|@uri')
  weather=$(curl -fsS --max-time 4 "https://wttr.in/$encoded_place?format=%t|%w" | tr -d '\n') || fail "$name: weather service is unavailable"
  [[ -n $weather ]] || fail "$name: weather service returned no data"
  printf '%s\n' "${place^}  ·  Temp ${weather%%|*}  ·  Wind ${weather#*|}"
}

notification_send() {
  (($# >= 1)) || fail 'Usage: omarchy-notification-send <headline> [description] [-r id] [-p]' 2
  local headline=$1 description="" replace_id="" persistent=false has_description=false
  shift
  if (($#)) && [[ $1 != -* ]]; then
    description=$1
    has_description=true
    shift
  fi
  while (($#)); do
    case $1 in
      -r)
        (($# >= 2)) || fail 'Usage: omarchy-notification-send <headline> [description] [-r id] [-p]' 2
        [[ $2 =~ ^[0-9]+$ ]] || fail 'Notification replacement id must be numeric' 2
        replace_id=$2
        shift 2
        ;;
      -p)
        persistent=true
        shift
        ;;
      *)
        fail 'Usage: omarchy-notification-send <headline> [description] [-r id] [-p]' 2
        ;;
    esac
  done
  need notify-send
  local notification_args=("$headline")
  $has_description && notification_args+=("$description")
  [[ -n $replace_id ]] && notification_args+=(-r "$replace_id")
  $persistent && notification_args+=(-p)
  timeout 5s notify-send -a omanixy-action -u low "${notification_args[@]}"
}

clipboard_paste_text() {
  local shift_insert=false copy_only=false history_index="" text=""
  while (($#)); do
    case "$1" in
      --shift-insert) shift_insert=true; shift ;;
      --copy-only) copy_only=true; shift ;;
      --history-index) (($# >= 2)) || fail 'Usage: omarchy-clipboard-paste-text [--shift-insert] [--copy-only] [--history-index index|text]' 2; history_index=$2; shift 2 ;;
      *) text=$1; shift ;;
    esac
  done
  need wl-copy
  if [[ -n $history_index ]]; then
    [[ $history_index =~ ^[0-9]+$ ]] || fail 'Clipboard history index must be numeric' 2
    jq -e --argjson index "$history_index" '.[$index].type == "text" and (.[$index].text | type == "string")' "$omarchy_state/clipboard-history.json" >/dev/null || fail "$name: clipboard history entry is unavailable"
    jq -j --argjson index "$history_index" '.[$index].text' "$omarchy_state/clipboard-history.json" | timeout 5s wl-copy
    $copy_only && return 0
    shift_insert=true
  else
    [[ -n $text ]] || fail 'Clipboard text is empty' 2
    printf '%s' "$text" | timeout 5s wl-copy
  fi
  $copy_only && return 0
  need wtype
  sleep 0.15
  if $shift_insert; then timeout 5s wtype -M shift -k Insert -m shift; else timeout 5s wtype "$text"; fi
}

clipboard_paste_file() {
  local copy_only=false
  if [[ ${1:-} == --copy-only ]]; then copy_only=true; shift; fi
  (($# == 2)) || fail 'Usage: omarchy-clipboard-paste-file [--copy-only] <mime-type> <path>' 2
  [[ -r $2 ]] || fail "$name: clipboard file is unreadable"
  need wl-copy
  timeout 5s wl-copy --type "$1" < "$2"
  $copy_only && return 0
  need wtype
  sleep 0.15
  timeout 5s wtype -M shift -k Insert -m shift
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
    mkdir -p "$omarchy_state/clipboard-open"
    file=$(mktemp "$omarchy_state/clipboard-open/entry.XXXXXX.txt")
    printf '%s' "$value" > "$file"
    xdg-open "$file" >/dev/null 2>&1 &
  else
    [[ -r $value ]] || fail "$name: clipboard image is unreadable"
    xdg-open "$value" >/dev/null 2>&1 &
  fi
}

emoji_insert() {
  (($# == 1)) && [[ -n $1 ]] || fail 'Usage: omarchy-menu-emoji-insert <emoji>' 2
  need wl-copy
  need wtype
  local pid
  printf '%s' "$1" | timeout 5s wl-copy --type text/plain --foreground &
  pid=$!
  sleep 0.15
  timeout 5s wtype -M shift -k Insert -m shift
  kill "$pid" 2>/dev/null || true
}

screenshot() {
  (($# == 0)) || fail 'Usage: omarchy-capture-screenshot' 2
  need grim
  local directory=${OMARCHY_SCREENSHOT_DIR:-${XDG_PICTURES_DIR:-$HOME/Pictures}}
  mkdir -p "$directory"
  local file
  file="$directory/screenshot-$(date +%Y-%m-%d_%H-%M-%S).png"
  timeout 10s grim "$file" || fail "$name: screenshot backend failed"
  if command -v wl-copy >/dev/null 2>&1; then wl-copy --type image/png < "$file"; fi
  printf '%s\n' "$file"
}

remove_launcher_entry() {
  (($# == 2)) || fail 'Usage: omarchy-remove-launcher-entry <desktop-id> <name>' 2
  [[ $1 =~ ^[A-Za-z0-9][A-Za-z0-9_.@+-]*$ ]] || fail 'Desktop ID is invalid' 2
  local id=${1%.desktop} file="${XDG_DATA_HOME:-$HOME/.local/share}/applications/${1%.desktop}.desktop"
  [[ -f $file ]] || fail "Could not find user launcher entry: $id.desktop"
  rm -f -- "$file"
  if command -v update-desktop-database >/dev/null 2>&1; then timeout 5s update-desktop-database "${file%/*}" >/dev/null 2>&1 || true; fi
}

case "$name" in
  omarchy-shell) exec @IPC@ "$@" ;;
  omarchy-weather-location) weather_location "$@" ;;
  omarchy-weather-status) weather_status "$@" ;;
  omarchy-notification-send) notification_send "$@" ;;
  omarchy-audio-output-set-default) audio_output_set_default "$@" ;;
  omarchy-audio-input-set-default) audio_input_set_default "$@" ;;
  omarchy-audio-output-sink) audio_output_sink "$@" ;;
  omarchy-audio-sink-availability) audio_sink_availability "$@" ;;
  omarchy-network-status) network_status "$@" ;;
  omarchy-network-qr) network_qr "$@" ;;
  omarchy-network-password) network_password "$@" ;;
  omarchy-network-speedtest) network_speedtest "$@" ;;
  omarchy-network-band) network_band "$@" ;;
  omarchy-dns) network_dns "$@" ;;
  omarchy-bluetooth-device) bluetooth_device "$@" ;;
  omarchy-bluetooth-power) bluetooth_power "$@" ;;
  omarchy-battery-status) battery_status "$@" ;;
  omarchy-powerprofiles-list) powerprofiles_list "$@" ;;
  omarchy-powerprofiles-set) powerprofiles_set "$@" ;;
  omarchy-system-stats) system_stats "$@" ;;
  omarchy-monitor-state) monitor_state "$@" ;;
  omarchy-brightness-display) brightness_display "$@" ;;
  omarchy-hyprland-monitor-scaling) monitor_scaling "$@" ;;
  omarchy-display-text-size) display_text_size "$@" ;;
  omarchy-clipboard-paste-text) clipboard_paste_text "$@" ;;
  omarchy-clipboard-paste-file) clipboard_paste_file "$@" ;;
  omarchy-clipboard-open) clipboard_open "$@" ;;
  omarchy-menu-emoji-insert) emoji_insert "$@" ;;
  omarchy-capture-screenshot) screenshot "$@" ;;
  omarchy-remove-launcher-entry) remove_launcher_entry "$@" ;;
  uwsm-app)
    (($# >= 2)) && [[ $1 == -- && $2 == gtk-launch ]] || fail 'Usage: uwsm-app -- gtk-launch <desktop-id>' 2
    shift 2
    (($# == 1)) || fail 'Usage: uwsm-app -- gtk-launch <desktop-id>' 2
    exec gtk-launch "$1"
    ;;
  *) fail "$name: unsupported compatibility command" 127 ;;
esac
