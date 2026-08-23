# shellcheck disable=SC2154
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
  state=$(network_nmcli -t -f GENERAL.STATE device show "$device" | sed -n 's/^GENERAL.STATE://p') ||
    fail "$name: NetworkManager state lookup failed"
  ssid=$(network_nmcli -t -f GENERAL.CONNECTION device show "$device" | sed -n 's/^GENERAL.CONNECTION://p') ||
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
  value=${value//\"/\\\"}
  value=${value//;/\\;}
  value=${value//,/\\,}
  value=${value//:/\\:}
  printf '%s' "$value"
}

network_password() {
  (($# == 1)) || fail 'Usage: omarchy-network-password <interface>' 2
  need nmcli
  local interface=$1 uuid key_management password wep_key
  uuid=$(network_nmcli --get-values GENERAL.CON-UUID device show "$interface") ||
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
  uuid=$(network_nmcli --get-values GENERAL.CON-UUID device show "$interface") ||
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

network_band_from_frequency() {
  awk -v frequency="$1" 'BEGIN {
    if (frequency >= 2400 && frequency < 2500) print "2.4"
    else if (frequency >= 4900 && frequency < 5925) print "5"
    else if (frequency >= 5925 && frequency < 7125) print "6"
  }'
}

network_band() {
  (($# <= 1)) || fail 'Usage: omarchy-network-band [auto|2.4|5|6]' 2
  need nmcli
  local device profile freq target ssid available previous desired current_band selected
  device=$(network_nmcli -t -f DEVICE,TYPE,STATE device status | awk -F: '$2 == "wifi" && $3 == "connected" { print $1; exit }') ||
    fail "$name: NetworkManager device lookup failed"
  [[ -n $device ]] || fail "$name: no connected Wi-Fi device"
  profile=$(network_nmcli -g GENERAL.CONNECTION device show "$device") ||
    fail "$name: NetworkManager profile lookup failed"
  [[ -n $profile ]] || fail "$name: no active Wi-Fi profile"
  if (($# == 0)); then
    need iw
    ssid=$(network_iw dev "$device" link | awk '/SSID:/ && !found { sub(/.*SSID: /, ""); value=$0; found=1 } END { if (found) print value; else exit 1 }') ||
      fail "$name: wireless SSID lookup failed"
    freq=$(network_iw dev "$device" link | awk '/freq:/ && !found { value=$2; found=1 } END { if (found) print value; else exit 1 }') ||
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
    ssid=$(network_iw dev "$device" link | awk '/SSID:/ && !found { sub(/.*SSID: /, ""); value=$0; found=1 } END { if (found) print value; else exit 1 }') ||
      fail "$name: wireless SSID lookup failed"
    freq=$(network_iw dev "$device" link | awk '/freq:/ && !found { value=$2; found=1 } END { if (found) print value; else exit 1 }') ||
      fail "$name: wireless frequency lookup failed"
    current_band=$(network_band_from_frequency "$freq")
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
  if [[ -n $desired ]]; then
    freq=$(network_iw dev "$device" link | awk '/freq:/ && !found { value=$2; found=1 } END { if (found) print value; else exit 1 }') || {
      if restore_band; then
        fail "$name: Wi-Fi band activation could not be verified; the previous band was restored"
      fi
      fail "$name: Wi-Fi band activation could not be verified; rollback failed and the profile may still be changed"
    }
    current_band=$(network_band_from_frequency "$freq")
    if [[ $current_band != "$1" ]]; then
      if restore_band; then
        fail "$name: Wi-Fi band activation reached ${current_band:-unknown} instead of $1; the previous band was restored"
      fi
      fail "$name: Wi-Fi band activation reached ${current_band:-unknown} instead of $1; rollback failed and the profile may still be changed"
    fi
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
