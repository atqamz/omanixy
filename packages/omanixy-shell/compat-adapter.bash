#!/usr/bin/env bash
set -euo pipefail

name=${COMPAT_ADAPTER_NAME:-${0##*/}}
state_home=${XDG_STATE_HOME:-$HOME/.local/state}
data_home=${XDG_DATA_HOME:-$HOME/.local/share}
config_home=${XDG_CONFIG_HOME:-$HOME/.config}
omarchy_state="$state_home/omarchy"

fail() {
  printf '%s\n' "$1" >&2
  exit "${2:-1}"
}

need() {
  command -v "$1" >/dev/null 2>&1 || fail "$name: required backend is unavailable: $1" 127
}

[[ $state_home == /* ]] || fail "$name: XDG_STATE_HOME must be an absolute path"
[[ $data_home == /* ]] || fail "$name: XDG_DATA_HOME must be an absolute path"
[[ $config_home == /* ]] || fail "$name: XDG_CONFIG_HOME must be an absolute path"

timed() {
  local seconds=$1 label=$2 status
  shift 2
  if timeout --kill-after=1s "${seconds}s" "$@"; then
    return 0
  else
    status=$?
  fi
  if [[ $status == 124 || $status == 137 || $status == 143 ]]; then
    printf '%s: %s timed out\n' "$name" "$label" >&2
  fi
  return "$status"
}

weather_location() {
  local file="$omarchy_state/settings/weather.json"
  case "${1:-}" in
    "")
      if [[ -r $file ]]; then
        local saved_location
        saved_location=$(jq -er '.name | select(type == "string" and length > 0)' "$file") ||
          fail "$name: saved weather location is malformed"
        printf '%s\n' "$saved_location"
      else
        need curl
        local detected_location
        detected_location=$(timed 4 'weather location lookup' curl -fsS --max-time 3 'https://wttr.in/?format=%l' 2>/dev/null | sed 's/,.*//') ||
          fail "$name: weather location lookup failed"
        [[ -n $detected_location ]] || fail "$name: weather location lookup returned no location"
        printf '%s\n' "$detected_location"
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
      mkdir -p "${file%/*}" || fail "$name: weather state directory is unavailable"
      local temporary
      temporary=$(mktemp "${file}.XXXXXX") || fail "$name: weather state file could not be created"
      trap 'rm -f -- "$temporary"' RETURN
      if ! printf '%s\n' "$json" >"$temporary" || ! chmod 600 "$temporary" || ! mv -f -- "$temporary" "$file"; then
        rm -f -- "$temporary"
        fail "$name: weather state could not be saved"
      fi
      trap - RETURN
      ;;
    --clear)
      (($# == 1)) || fail 'Usage: omarchy-weather-location --clear' 2
      rm -f -- "$file" || fail "$name: weather state could not be cleared"
      ;;
    *)
      fail 'Usage: omarchy-weather-location [--set <name> [lat,lon]|--clear]' 2
      ;;
  esac
}

pipewire_dump() {
  timed 2 'PipeWire inspection' pw-dump
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
  timed 2 'PipeWire output selection' wpctl set-default "$1" || fail "$name: could not set PipeWire default output"
}

audio_input_set_default() {
  (($# == 2)) || fail 'Usage: omarchy-audio-input-set-default <node-id> <source-name>' 2
  [[ $1 =~ ^[0-9]+$ && -n $2 ]] || fail 'Usage: omarchy-audio-input-set-default <node-id> <source-name>' 2
  need wpctl
  need pw-dump
  local resolved_name
  resolved_name=$(pipewire_node_name "$1" Audio/Source) || fail "$name: input node is unavailable"
  [[ $resolved_name == "$2" ]] || fail "$name: input node name does not match PipeWire metadata"
  timed 2 'PipeWire input selection' wpctl set-default "$1" || fail "$name: could not set PipeWire default input"
}

audio_output_sink() {
  (($# == 0)) || fail 'Usage: omarchy-audio-output-sink' 2
  need wpctl
  need pw-dump
  local default_name
  default_name=$(timed 2 'PipeWire default output inspection' wpctl inspect @DEFAULT_AUDIO_SINK@ |
    sed -n 's/^[[:space:]]*node.name = "\(.*\)"$/\1/p' | head -n 1) ||
    fail "$name: default output inspection failed"
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
  local route_output status
  if route_output=$(timed 2 'route lookup' ip route get 1.1.1.1); then
    awk '{ for (i = 1; i <= NF; i++) if ($i == "dev") { print $(i + 1); exit } }' <<<"$route_output"
  else
    status=$?
    [[ $status == 2 ]] && return 0
    return "$status"
  fi
}

network_nmcli() {
  LC_ALL=C timed 3 'NetworkManager request' nmcli "$@"
}

network_iw() {
  timed 3 'wireless request' iw "$@"
}

network_ip() {
  timed 2 'network address request' ip "$@"
}

network_ping() {
  local host=$1
  timed 2 'network ping' ping -n -c 1 -W 1 "$host" 2>/dev/null |
    awk -F'time[=<]' '/time[=<]/ { split($2, parts, " "); print parts[1]; exit }' || true
}

network_route_json() {
  local route_json status
  if route_json=$(network_ip -j route get 1.1.1.1); then
    printf '%s\n' "$route_json"
  else
    status=$?
    [[ $status == 2 ]] && printf '%s\n' '[]' && return 0
    fail "$name: network route details are unavailable"
  fi
}

network_prefix() {
  local address_json
  address_json=$(network_ip -j addr show "$1") || fail "$name: network address details are unavailable"
  jq -er '([.[0].addr_info[]? | select(.family == "inet") | .prefixlen][0] // "")' <<<"$address_json" ||
    fail "$name: network address details are malformed"
}

network_status() {
  (($# <= 1)) || fail 'Usage: omarchy-network-status [--verbose]' 2
  need ip
  need jq
  local device
  device=$(network_device)
  if [[ -z $device ]]; then
    printf 'disconnected\t\t\t\n'
    return
  fi
  if [[ ! -d /sys/class/net/$device/wireless ]]; then
    if [[ ${1:-} == --verbose ]]; then
      local route_json iface gateway address prefix
      route_json=$(network_route_json)
      iface=$(jq -r '.[0].dev // ""' <<<"$route_json")
      gateway=$(jq -r '.[0].gateway // ""' <<<"$route_json")
      address=$(jq -r '.[0].prefsrc // ""' <<<"$route_json")
      prefix=$(network_prefix "$device")
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
  need nmcli
  state=$(network_nmcli -t -f GENERAL.STATE device show "$device" | sed -n 's/^GENERAL.STATE://p' | head -n 1) ||
    fail "$name: NetworkManager state lookup failed"
  ssid=$(network_nmcli -t -f GENERAL.CONNECTION device show "$device" | sed -n 's/^GENERAL.CONNECTION://p' | head -n 1) ||
    fail "$name: NetworkManager connection lookup failed"
  signal=$(network_nmcli -t -f IN-USE,SIGNAL device wifi list ifname "$device" --rescan no | awk -F: '$1 == "*" { print $2; exit }') ||
    fail "$name: Wi-Fi signal lookup failed"
  freq=$(network_iw dev "$device" link | awk '/freq:/ { print $2; exit }') ||
    fail "$name: wireless frequency lookup failed"
  [[ $state == 100* || -n $ssid ]] || { printf 'disconnected\t\t\t\n'; return; }
  if [[ ${1:-} == --verbose ]]; then
    local route_json iface gateway address prefix
    route_json=$(network_route_json)
    iface=$(jq -r '.[0].dev // ""' <<<"$route_json")
    gateway=$(jq -r '.[0].gateway // ""' <<<"$route_json")
    address=$(jq -r '.[0].prefsrc // ""' <<<"$route_json")
    prefix=$(network_prefix "$device")
    printf 'iface\t%s\nip\t%s\nprefix\t%s\ngateway\t%s\ntype\twifi\n' "$iface" "$address" "$prefix" "$gateway"
    [[ -r /sys/class/net/$device/statistics/rx_bytes ]] && printf 'rx_bytes\t%s\n' "$(<"/sys/class/net/$device/statistics/rx_bytes")"
    [[ -r /sys/class/net/$device/statistics/tx_bytes ]] && printf 'tx_bytes\t%s\n' "$(<"/sys/class/net/$device/statistics/tx_bytes")"
    local link
    link=$(network_iw dev "$device" link 2>/dev/null || true)
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
  uuid=$(network_nmcli --get-values GENERAL.CON-UUID device show "$interface" | head -n 1) ||
    fail "$name: NetworkManager connection lookup failed"
  [[ -n $uuid && $uuid != -- ]] || fail 'No active Wi-Fi connection' 1
  local fields_output
  fields_output=$(network_nmcli --show-secrets --escape no --get-values \
    802-11-wireless-security.key-mgmt,802-11-wireless-security.psk,802-11-wireless-security.wep-key0 \
    connection show uuid "$uuid") || fail "$name: NetworkManager secret lookup failed"
  mapfile -t fields <<<"$fields_output"
  ((${#fields[@]} <= 3)) || fail "$name: NetworkManager returned an unsupported multiline secret"
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
    interface=$(network_device)
    if [[ -z $interface || ! -d /sys/class/net/$interface/wireless ]]; then
      interface=$(network_nmcli -t -f DEVICE,TYPE,STATE device status 2>/dev/null |
        awk -F: '$2 == "wifi" && $3 ~ /^connected/ { print $1; exit }')
    fi
  fi
  [[ $interface =~ ^[[:alnum:]_.:-]+$ ]] || fail "$name: no active Wi-Fi connection" 1
  uuid=$(network_nmcli --get-values GENERAL.CON-UUID device show "$interface" | head -n 1) ||
    fail "$name: NetworkManager connection lookup failed"
  [[ -n $uuid && $uuid != -- ]] || fail "$name: no active Wi-Fi connection" 1
  local fields_output
  fields_output=$(network_nmcli --show-secrets --escape no --get-values \
    802-11-wireless.ssid,802-11-wireless-security.key-mgmt,802-11-wireless-security.psk,802-11-wireless.hidden,802-11-wireless-security.wep-key0 \
    connection show uuid "$uuid") || fail "$name: NetworkManager secret lookup failed"
  mapfile -t fields <<<"$fields_output"
  ((${#fields[@]} <= 5)) || fail "$name: NetworkManager returned an unsupported multiline Wi-Fi profile"
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
  ascii=$(timed 4 'Wi-Fi QR encoding' qrencode --type ASCII --margin 4 --output - <<<"$payload") || fail "$name: QR encoder failed" 1
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
  need pkill
  need jq
  local direction=$1 iface api urls_raw start rx_before tx_before rx_after tx_after rate sample_count=0 worker_failed=0 worker_status_file
  local sysfs=${OMARCHY_SPEEDTEST_SYSFS:-/sys/class/net}
  iface=$(network_device)
  [[ -n $iface && -r $sysfs/$iface/statistics/rx_bytes && -r $sysfs/$iface/statistics/tx_bytes ]] || fail "$name: no active network interface" 1
  api='https://api.fast.com/netflix/speedtest/v2?https=true&token=YXNkZmFzZGxmbnNkYWZoYXNkZmhrYWxm&urlCount=3'
  urls_raw=$(timed 4 'speed-test endpoint discovery' curl -fsS --max-time 3 "$api" 2>/dev/null | jq -r '.targets[]?.url // empty') ||
    fail "$name: failed to fetch speed test endpoints" 1
  [[ -n $urls_raw ]] || fail "$name: failed to fetch speed test endpoints" 1
  mapfile -t urls <<<"$urls_raw"
  rx_before=$(<"$sysfs/$iface/statistics/rx_bytes")
  tx_before=$(<"$sysfs/$iface/statistics/tx_bytes")
  worker_status_file=$(mktemp) || fail "$name: speed-test worker status could not be created"
  local -a traffic_pids=()
  cleanup_speedtest() {
    local pid cleanup_status=0
    for pid in "${traffic_pids[@]}"; do
      [[ -n $pid ]] || continue
      if kill -0 "$pid" 2>/dev/null; then
        pkill -TERM -P "$pid" 2>/dev/null || :
        kill "$pid" 2>/dev/null || cleanup_status=1
      fi
    done
    for pid in "${traffic_pids[@]}"; do
      [[ -n $pid ]] || continue
      wait "$pid" 2>/dev/null || true
      if kill -0 "$pid" 2>/dev/null; then cleanup_status=1; fi
    done
    if ((cleanup_status)); then
      printf '%s: speed-test worker cleanup failed\n' "$name" >&2
    fi
    rm -f -- "$worker_status_file" || cleanup_status=1
    return "$cleanup_status"
  }
  speedtest_worker() {
    local worker_url
    while :; do
      worker_url=${urls[RANDOM % ${#urls[@]}]}
      if [[ $direction == down ]]; then
        timed 3 'speed-test download worker' curl -fsS -o /dev/null --max-time 2 "$worker_url" 2>/dev/null || {
          printf '%s\n' failed >>"$worker_status_file"
          return 1
        }
      else
        head -c 1048576 /dev/zero | timed 3 'speed-test upload worker' curl -fsS -o /dev/null -X POST --data-binary @- --max-time 2 "$worker_url" 2>/dev/null || {
          printf '%s\n' failed >>"$worker_status_file"
          return 1
        }
      fi
    done
  }
  for _ in {1..8}; do speedtest_worker & traffic_pids+=("$!"); done
  trap cleanup_speedtest EXIT
  start=$SECONDS
  while ((SECONDS < start + 5)); do
    timed 2 'speed-test sample interval' sleep 1 ||
      fail "$name: speed-test sample interval failed"
    for pid in "${traffic_pids[@]}"; do
      if ! kill -0 "$pid" 2>/dev/null; then worker_failed=1; fi
    done
    [[ ! -s $worker_status_file && $worker_failed == 0 ]] ||
      fail "$name: speed-test worker failed before producing a complete sample"
    rx_after=$(<"$sysfs/$iface/statistics/rx_bytes")
    tx_after=$(<"$sysfs/$iface/statistics/tx_bytes")
    if [[ $direction == down ]]; then
      rate=$(awk -v before="$rx_before" -v after="$rx_after" 'BEGIN { if (after < before) print 0; else print (after - before) * 8 / 1000000 }')
    else
      rate=$(awk -v before="$tx_before" -v after="$tx_after" 'BEGIN { if (after < before) print 0; else print (after - before) * 8 / 1000000 }')
    fi
    awk -v value="$rate" 'BEGIN { if (value <= 0) print "0.0"; else if (value < 10) printf "%.1f\\n", value; else printf "%.0f\\n", value }'
    sample_count=$((sample_count + 1))
    rx_before=$rx_after
    tx_before=$tx_after
  done
  [[ ! -s $worker_status_file && $worker_failed == 0 ]] || fail "$name: speed-test worker failed"
  if ((sample_count == 0)); then
    fail "$name: speed-test workers produced no usable samples" 1
  fi
}

network_available_bands() {
  local device=$1 ssid=$2 current=$3 scan
  scan=$(network_nmcli -t -e no -f FREQ,SSID device wifi list ifname "$device" --rescan no 2>/dev/null) || return 1
  {
    [[ -n $current ]] && printf '%s\n' "$current"
    while read -r frequency; do
      awk -v frequency="$frequency" 'BEGIN {
        gsub(/[^0-9].*/, "", frequency)
        if (frequency >= 2400 && frequency < 2500) print "2.4"
        else if (frequency >= 4900 && frequency < 5925) print "5"
        else if (frequency >= 5925 && frequency < 7125) print "6"
      }'
    done < <(awk -F: -v wanted="$ssid" '
      {
        name = $2
        for (i = 3; i <= NF; i++) name = name ":" $i
        if (name == wanted) print $1
      }' <<<"$scan")
  } | sort -u -g | tr '\n' ' ' | sed 's/ $//'
}

network_band() {
  (($# <= 1)) || fail 'Usage: omarchy-network-band [auto|2.4|5|6]' 2
  need nmcli
  local device profile freq target ssid available previous desired current_band selected
  device=$(network_nmcli -t -f DEVICE,TYPE,STATE device status | awk -F: '$2 == "wifi" && $3 == "connected" { print $1; exit }') ||
    fail "$name: NetworkManager device lookup failed"
  [[ -n $device ]] || fail "$name: no connected Wi-Fi device"
  profile=$(network_nmcli -g GENERAL.CONNECTION device show "$device" | head -n 1) ||
    fail "$name: NetworkManager profile lookup failed"
  [[ -n $profile ]] || fail "$name: no active Wi-Fi profile"
  if (($# == 0)); then
    need iw
    ssid=$(network_iw dev "$device" link | awk '/SSID:/ { sub(/.*SSID: /, ""); print; exit }') ||
      fail "$name: wireless SSID lookup failed"
    freq=$(network_iw dev "$device" link | awk '/freq:/ { print $2; exit }') ||
      fail "$name: wireless frequency lookup failed"
    target=$(awk -v frequency="$freq" 'BEGIN { if (frequency >= 2400 && frequency < 2500) print "2.4"; else if (frequency >= 4900 && frequency < 5925) print "5"; else if (frequency >= 5925 && frequency < 7125) print "6" }')
    available=$(network_available_bands "$device" "$ssid" "$target") ||
      fail "$name: available Wi-Fi bands could not be determined"
    selected=$(network_nmcli -g 802-11-wireless.band connection show "$profile" | sed 's/^$/auto/;s/^bg$/2.4/;s/^a$/5/;s/^6GHz$/6/') ||
      fail "$name: NetworkManager band state lookup failed"
    printf 'band\t%s\navailable\t%s\nselected\t%s\n' "$target" "$available" "$selected"
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
  if [[ -n $desired ]]; then
    need iw
    ssid=$(network_iw dev "$device" link | awk '/SSID:/ { sub(/.*SSID: /, ""); print; exit }') ||
      fail "$name: wireless SSID lookup failed"
    freq=$(network_iw dev "$device" link | awk '/freq:/ { print $2; exit }') ||
      fail "$name: wireless frequency lookup failed"
    current_band=$(awk -v frequency="$freq" 'BEGIN { if (frequency >= 2400 && frequency < 2500) print "2.4"; else if (frequency >= 4900 && frequency < 5925) print "5"; else if (frequency >= 5925 && frequency < 7125) print "6" }')
    available=$(network_available_bands "$device" "$ssid" "$current_band") ||
      fail "$name: available Wi-Fi bands could not be determined"
    if [[ " $available " != *" $1 "* ]]; then
      fail "$name: requested Wi-Fi band is unavailable" 1
    fi
  fi
  previous=$(network_nmcli -g 802-11-wireless.band connection show "$profile") ||
    fail "$name: NetworkManager band state lookup failed"
  [[ $previous == "$desired" ]] && return 0
  if ! network_nmcli connection modify "$profile" 802-11-wireless.band "$desired" >/dev/null; then
    fail "$name: NetworkManager could not update the requested band; the profile was not changed"
  fi
  restore_band() {
    local restore_status=0
    network_nmcli connection modify "$profile" 802-11-wireless.band "$previous" >/dev/null || restore_status=1
    network_nmcli connection up "$profile" >/dev/null 2>&1 || restore_status=1
    return "$restore_status"
  }
  if ! network_nmcli connection up "$profile" >/dev/null 2>&1; then
    if restore_band; then
      fail "$name: NetworkManager could not reassociate on the requested band; the previous band was restored"
    fi
    fail "$name: NetworkManager could not reassociate on the requested band; rollback failed and the profile may still be changed"
  fi
  local applied
  applied=$(network_nmcli -g 802-11-wireless.band connection show "$profile") || {
    if restore_band; then
      fail "$name: NetworkManager did not verify the requested band; the previous band was restored"
    fi
    fail "$name: NetworkManager did not verify the requested band; rollback failed and the profile may still be changed"
  }
  if [[ $applied != "$desired" ]]; then
    if restore_band; then
      fail "$name: NetworkManager reported an unexpected band after activation; the previous band was restored"
    fi
    fail "$name: NetworkManager reported an unexpected band after activation; rollback failed and the profile may still be changed"
  fi
}

network_dns() {
  (($# <= 1)) || fail 'Usage: omarchy-dns [DHCP|Cloudflare|Google]' 2
  need nmcli
  local profile dns ignore provider desired_ignore desired_dns
  profile=$(network_nmcli -t -e no -f NAME,TYPE connection show --active | awk -F: '$NF != "loopback" { name=$1; for (i = 2; i < NF; i++) name=name ":" $i; print name; exit}') ||
    fail "$name: active NetworkManager connection lookup failed"
  [[ -n $profile ]] || fail "$name: no active NetworkManager connection"
  ignore=$(network_nmcli -g ipv4.ignore-auto-dns connection show "$profile") ||
    fail "$name: NetworkManager DNS state lookup failed"
  dns=$(network_nmcli -g ipv4.dns connection show "$profile") ||
    fail "$name: NetworkManager DNS state lookup failed"
  if (($# == 0)); then
    if [[ $ignore != yes && -z $dns ]]; then provider=DHCP
    elif [[ $dns == *1.1.1.1* && $dns == *1.0.0.1* ]]; then provider=Cloudflare
    elif [[ $dns == *8.8.8.8* && $dns == *8.8.4.4* ]]; then provider=Google
    else provider=Custom
    fi
    printf '%s\n' "$provider"
    return
  fi
  case "$1" in
    DHCP) desired_ignore=no; desired_dns="" ;;
    Cloudflare) desired_ignore=yes; desired_dns='1.1.1.1,1.0.0.1' ;;
    Google) desired_ignore=yes; desired_dns='8.8.8.8,8.8.4.4' ;;
    Custom) fail "$name: custom DNS requires an explicit NetworkManager profile edit" 2 ;;
    *) fail 'Usage: omarchy-dns [DHCP|Cloudflare|Google]' 2 ;;
  esac
  if [[ $ignore == "$desired_ignore" && $dns == "$desired_dns" ]]; then return 0; fi
  if ! network_nmcli connection modify "$profile" ipv4.ignore-auto-dns "$desired_ignore" ipv4.dns "$desired_dns" >/dev/null; then
    fail "$name: NetworkManager could not update DNS settings; the profile was not changed"
  fi
  restore_dns() {
    local restore_status=0
    network_nmcli connection modify "$profile" ipv4.ignore-auto-dns "$ignore" ipv4.dns "$dns" >/dev/null || restore_status=1
    network_nmcli connection up "$profile" >/dev/null 2>&1 || restore_status=1
    return "$restore_status"
  }
  if ! network_nmcli connection up "$profile" >/dev/null 2>&1; then
    if restore_dns; then
      fail "$name: NetworkManager could not apply DNS settings; the previous settings were restored"
    fi
    fail "$name: NetworkManager could not apply DNS settings; rollback failed and the profile may still be changed"
  fi
  local applied_ignore applied_dns
  if ! applied_ignore=$(network_nmcli -g ipv4.ignore-auto-dns connection show "$profile"); then
    if restore_dns; then
      fail "$name: NetworkManager did not verify DNS settings; the previous settings were restored"
    fi
    fail "$name: NetworkManager could not verify DNS settings; rollback failed and the profile may still be changed"
  fi
  if ! applied_dns=$(network_nmcli -g ipv4.dns connection show "$profile"); then
    if restore_dns; then
      fail "$name: NetworkManager did not verify DNS settings; the previous settings were restored"
    fi
    fail "$name: NetworkManager could not verify DNS settings; rollback failed and the profile may still be changed"
  fi
  if [[ $applied_ignore != "$desired_ignore" || $applied_dns != "$desired_dns" ]]; then
    if restore_dns; then
      fail "$name: NetworkManager did not verify DNS settings; the previous settings were restored"
    fi
    fail "$name: NetworkManager did not verify DNS settings; rollback failed and the profile may still be changed"
  fi
}

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
  need rfkill
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
    mkdir -p "$state_dir" || fail "$name: power-profile state directory is unavailable"
    local temporary
    temporary=$(mktemp "$state_file.XXXXXX") || fail "$name: power-profile state file could not be created"
    trap 'rm -f -- "$temporary"' RETURN
    if ! printf '%s\n' "$requested_profile" >"$temporary" || ! chmod 600 "$temporary" || ! mv -f -- "$temporary" "$state_file"; then
      rm -f -- "$temporary"
      fail "$name: power-profile state could not be saved"
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
    after=$(awk '$1 == "cpu" && NF >= 5 { for (i = 2; i <= NF; i++) if ($i !~ /^[0-9]+$/) exit 1; print; exit }' /proc/stat) ||
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
  printf 'cpu\t%s\nmemory\t%.1fGB / %.0fGB\nload\t%s\n' \
    "$cpu" "$(awk -v value="$used" 'BEGIN { printf "%.1f", value / 1048576 }')" \
    "$(awk -v value="$total" 'BEGIN { printf "%.0f", value / 1048576 }')" "$load"
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
  brightness=$(COMPAT_ADAPTER_NAME=omarchy-brightness-display brightness_display --monitor "$focused" 2>/dev/null | head -n 1 || true)
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

monitor_scaling() {
  (($# <= 1)) || fail 'Usage: omarchy-hyprland-monitor-scaling [SCALE]' 2
  need hyprctl
  need jq
  local info name="" config_mode
  info=$(timed 3 'focused monitor lookup' hyprctl monitors -j | jq -e -c '.[] | select(.focused == true)') || fail "$name: focused monitor is unavailable"
  name=$(jq -r .name <<<"$info")
  if (($# == 0)); then jq -r .scale <<<"$info"; return; fi
  if [[ ! $1 =~ ^[0-9]+(\.[0-9]+)?$ ]] || ! awk -v scale="$1" 'BEGIN { exit !(scale >= 1 && scale <= 4) }'; then
    fail 'Monitor scale must be between 1 and 4' 2
  fi
  config_mode=$(monitor_config_mode)
  timed 3 'monitor scaling update' hyprctl keyword monitor "$name,preferred,auto,auto,$1" >/dev/null ||
    fail "$name: Hyprland rejected monitor scale"
  persist_monitor_scale "$config_mode" "$1" ||
    fail "$name: monitor scale changed, but the Hyprland configuration could not be updated"
}

display_text_size() {
  (($# == 1)) || fail 'Usage: omarchy-display-text-size <size>' 2
  local file="$config_home/omarchy/shell.toml"
  [[ $1 =~ ^[0-9]+$ && $1 -ge 9 && $1 -le 20 ]] || fail 'Text size must be an integer between 9 and 20' 2
  mkdir -p "${file%/*}" || fail "$name: configuration directory is unavailable"
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
  local temporary
  temporary=$(mktemp "${file}.XXXXXX") || fail "$name: configuration temporary file could not be created"
  trap 'rm -f -- "$temporary"' RETURN
  if [[ -f $file ]]; then
    if ! awk -v size="$1" 'BEGIN { in_font=0; done=0 } /^[[:space:]]*\[font\][[:space:]]*(#.*)?$/{in_font=1; print; next} /^[[:space:]]*\[/{if(in_font&&!done){print "base-size = " size; done=1}; in_font=0; print; next} in_font && /^[[:space:]]*base-size[[:space:]]*=/ {if(!done){print "base-size = " size; done=1}; next} {print} END {if(in_font&&!done) print "base-size = " size; if(!done){print "[font]"; print "base-size = " size}}' "$file" > "$temporary"; then
      rm -f -- "$temporary"
      fail "$name: shell.toml could not be rewritten"
    fi
  else
    if ! printf '[font]\nbase-size = %s\n' "$1" > "$temporary"; then
      rm -f -- "$temporary"
      fail "$name: shell.toml could not be created"
    fi
  fi
  if [[ -f $file ]] && ! chmod --reference="$file" "$temporary"; then
    rm -f -- "$temporary"
    fail "$name: shell.toml permissions could not be preserved"
  fi
  if ! mv -f -- "$temporary" "$file"; then
    fail "$name: shell.toml could not be replaced"
  fi
  trap - RETURN
}

weather_status() {
  (($# == 0)) || fail 'Usage: omarchy-weather-status' 2
  local place weather encoded_place
  place=$(COMPAT_ADAPTER_NAME=omarchy-weather-location weather_location)
  [[ -n $place ]] || fail "$name: weather location is unavailable"
  need curl
  encoded_place=$(jq -rn --arg place "$place" '$place|@uri')
  weather=$(timed 5 'weather lookup' curl -fsS --max-time 4 "https://wttr.in/$encoded_place?format=%t|%w" | tr -d '\n') ||
    fail "$name: weather service is unavailable"
  [[ -n $weather ]] || fail "$name: weather service returned no data"
  printf '%s\n' "${place^}  ·  Temp ${weather%%|*}  ·  Wind ${weather#*|}"
}

notification_send() {
  (($# >= 1)) || fail 'Usage: omarchy-notification-send [--exec <command>] [--app-name <app-name>] [-g <glyph>] [-u <low|normal|critical>] [--image <path-or-uri>] <headline> [description] [notify-send options]' 2
  local headline description="" glyph="" urgency=low app_name=omarchy-action image="" exec_command="" has_description=false
  local parsed_option_args
  local -a notification_args=()
  parse_notification_option() {
    case $1 in
      -g|--glyph)
        (($# >= 2)) || fail "Missing value for $1" 2
        glyph=$2
        parsed_option_args=2
        return 0
        ;;
      -u|--urgency)
        (($# >= 2)) || fail "Missing value for $1" 2
        [[ $2 =~ ^(low|normal|critical)$ ]] || fail 'Notification urgency is invalid' 2
        urgency=$2
        parsed_option_args=2
        return 0
        ;;
      --app-name)
        (($# >= 2)) || fail 'Missing value for --app-name' 2
        app_name=$2
        parsed_option_args=2
        return 0
        ;;
      --image)
        (($# >= 2)) || fail 'Missing value for --image' 2
        image=$2
        parsed_option_args=2
        return 0
        ;;
      --exec)
        (($# >= 2)) || fail 'Missing value for --exec' 2
        exec_command=$2
        parsed_option_args=2
        return 0
        ;;
    esac
    return 1
  }
  while (($#)) && parse_notification_option "$@"; do shift "$parsed_option_args"; done
  (($# >= 1)) || fail 'Usage: omarchy-notification-send [--exec <command>] [--app-name <app-name>] [-g <glyph>] [-u <low|normal|critical>] [--image <path-or-uri>] <headline> [description] [notify-send options]' 2
  headline=$1
  shift
  if (($#)) && [[ $1 != -* ]]; then
    description=$1
    has_description=true
    shift
  fi
  while (($#)); do
    if parse_notification_option "$@"; then
      shift "$parsed_option_args"
    else
      if [[ $1 == -r ]]; then
        (($# >= 2)) || fail 'Notification replacement id is missing' 2
        [[ $2 =~ ^[0-9]+$ ]] || fail 'Notification replacement id must be numeric' 2
        notification_args+=(-r "$2")
        shift 2
      else
        notification_args+=("$1")
        shift
      fi
    fi
  done
  notification_args+=(-a "$app_name" -u "$urgency")
  [[ -z $glyph ]] || notification_args+=(--hint="string:omarchy-glyph:$glyph")
  [[ -z $image ]] || notification_args+=(--hint="string:image-path:$image")
  [[ -z $exec_command ]] || notification_args+=(--hint="string:omarchy-exec:$exec_command")
  need notify-send
  if $has_description; then
    timed 5 'notification delivery' notify-send "${notification_args[@]}" "$headline" "$description"
  else
    timed 5 'notification delivery' notify-send "${notification_args[@]}" "$headline"
  fi
}

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
  if $shift_insert; then timed 5 'clipboard paste' wtype -M shift -k Insert -m shift; else timed 5 'clipboard paste' wtype "$text"; fi
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
  (($# == 1)) && [[ -n $1 ]] || fail 'Usage: omarchy-menu-emoji-insert <emoji>' 2
  need wl-copy
  need wtype
  need setsid
  local pid status=0 cleanup_status=0
  printf '%s' "$1" | setsid --wait timeout --kill-after=1s 5s wl-copy --type text/plain --sensitive --foreground &
  pid=$!
  timed 1 'emoji paste delay' sleep 0.15 || status=$?
  timed 5 'emoji paste' wtype -M shift -k Insert -m shift || status=$?
  if kill -0 "$pid" 2>/dev/null; then
    if ! kill -- "-$pid" 2>/dev/null && ! kill "$pid" 2>/dev/null; then
      cleanup_status=1
    fi
  fi
  for _ in {1..20}; do
    kill -0 "$pid" 2>/dev/null || break
    timed 1 'emoji clipboard cleanup wait' sleep 0.1 || cleanup_status=1
  done
  kill -0 "$pid" 2>/dev/null && cleanup_status=1
  if wait "$pid" 2>/dev/null; then :; fi
  ((cleanup_status == 0)) || fail "$name: emoji clipboard cleanup failed"
  ((status == 0)) || fail "$name: emoji paste failed"
}

screenshot() {
  (($# == 0)) || fail 'Usage: omarchy-capture-screenshot' 2
  need grim
  local directory=${OMARCHY_SCREENSHOT_DIR:-${XDG_PICTURES_DIR:-}}
  if [[ -z $directory && -r $config_home/user-dirs.dirs ]]; then
    directory=$(sed -n 's/^XDG_PICTURES_DIR="\(.*\)"$/\1/p' "$config_home/user-dirs.dirs" | head -n 1)
    directory=${directory//\$HOME/$HOME}
  fi
  [[ $directory == /* ]] || directory=$HOME/Pictures
  mkdir -p "$directory" || fail "$name: screenshot directory is unavailable"
  local file
  file=$(mktemp "$directory/screenshot-$(date +%Y-%m-%d_%H-%M-%S)-XXXXXX.png") ||
    fail "$name: screenshot filename could not be allocated"
  if ! timed 10 'screenshot capture' grim "$file"; then
    rm -f -- "$file" || printf '%s: screenshot temporary cleanup failed\n' "$name" >&2
    fail "$name: screenshot backend failed"
  fi
  if command -v wl-copy >/dev/null 2>&1 &&
    ! timed 5 'screenshot clipboard copy' wl-copy --type image/png < "$file"; then
    printf '%s: screenshot captured but clipboard copy failed\n' "$name" >&2
  fi
  printf '%s\n' "$file"
}

remove_launcher_entry() {
  (($# == 2)) || fail 'Usage: omarchy-remove-launcher-entry <desktop-id> <name>' 2
  [[ $1 =~ ^[A-Za-z0-9][A-Za-z0-9_.@+-]*$ ]] || fail 'Desktop ID is invalid' 2
  local id=${1%.desktop} file="$data_home/applications/${1%.desktop}.desktop" backup
  [[ ! -L $file ]] || fail "$name: launcher entry is a symlink"
  [[ -f $file ]] || fail "Could not find user launcher entry: $id.desktop"
  need update-desktop-database
  backup=$(mktemp "${file}.XXXXXX") || fail "$name: launcher entry backup could not be created"
  trap 'rm -f -- "$backup"' RETURN
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
  trap - RETURN
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
    timed 10 'application launch' gtk-launch "$1"
    ;;
  *) fail "$name: unsupported compatibility command" 127 ;;
esac
