#!/usr/bin/env bash
set -euo pipefail

repo=$(cd "${1:?repository path required}" && pwd)
adapter="$repo/packages/omanixy-shell/compat-adapter.bash"
test_root=$(mktemp -d)
bin="$test_root/bin"
home="$test_root/home"
state="$home/.local/state/omarchy"
log="$test_root/adapter.log"
mkdir -p "$bin" "$home" "$state"
trap 'rm -rf "$test_root"' EXIT
export HOME="$home"
export XDG_STATE_HOME="$home/.local/state"
export PATH="$bin:$PATH"

run_adapter() {
  local command=$1
  shift
  env \
    HOME="$HOME" \
    PATH="$PATH" \
    XDG_STATE_HOME="${XDG_STATE_HOME:-}" \
    TEST_CLIPBOARD="${TEST_CLIPBOARD:-}" \
    TEST_WTYPE="${TEST_WTYPE:-}" \
    TEST_NOTIFICATION="${TEST_NOTIFICATION:-}" \
    TEST_QR_PAYLOAD="${TEST_QR_PAYLOAD:-}" \
    TEST_PROFILE="${TEST_PROFILE:-}" \
    HYPRCTL_LOG="${HYPRCTL_LOG:-}" \
    OMARCHY_POWER_SUPPLY_PATH="${OMARCHY_POWER_SUPPLY_PATH:-}" \
    COMPAT_ADAPTER_NAME="$command" \
    bash "$adapter" "$@"
}

ln -s "$adapter" "$bin/omarchy-weather-location"
ln -s "$adapter" "$bin/omarchy-audio-output-set-default"
ln -s "$adapter" "$bin/omarchy-menu-emoji-insert"
ln -s "$adapter" "$bin/omarchy-notification-send"
ln -s "$adapter" "$bin/omarchy-clipboard-paste-text"
ln -s "$adapter" "$bin/omarchy-clipboard-paste-file"
ln -s "$adapter" "$bin/omarchy-clipboard-open"
ln -s "$adapter" "$bin/omarchy-capture-screenshot"
ln -s "$adapter" "$bin/omarchy-remove-launcher-entry"
ln -s "$adapter" "$bin/uwsm-app"

HOME="$home" XDG_STATE_HOME="$home/.local/state" PATH="$bin:$PATH" \
  run_adapter omarchy-weather-location --set 'City & Name' '1.25,-2.5'
jq -e '.name == "City & Name" and .latitude == 1.25 and .longitude == -2.5' \
  "$state/settings/weather.json" >/dev/null

if HOME="$home" XDG_STATE_HOME="$home/.local/state" PATH="$bin:$PATH" \
  run_adapter omarchy-weather-location --set broken 'not-coordinates' 2>"$test_root/error"; then
  printf '%s\n' 'malformed weather coordinates unexpectedly succeeded' >&2
  exit 1
fi
grep -q 'Invalid coordinates' "$test_root/error"

printf '%s\n' 'audio' > "$log"
cat > "$bin/wpctl" <<EOF
#!/usr/bin/env bash
printf 'wpctl %s\n' "\$*" >> "$log"
EOF
cat > "$bin/pactl" <<EOF
#!/usr/bin/env bash
if [[ \$1 == get-default-sink ]]; then
  printf '%s\n' alsa_output.pci-1
elif [[ \$1 == list && \$2 == sinks ]]; then
  printf 'Sink #42\\n\\tName: alsa_output.pci-1\\n\\tPorts:\\n\\t\\tanalog-output-speaker: Speakers (priority 100, available)\\n\\tActive Port: analog-output-speaker\\n\\n'
  printf 'Sink #43\\n\\tName: alsa_output.usb-1\\n\\tPorts:\\n\\t\\tanalog-output-headphones: Headphones (priority 100, not available)\\n\\tActive Port: analog-output-headphones\\n'
  exit 0
fi
printf 'pactl %s\n' "\$*" >> "$log"
EOF
chmod +x "$bin/wpctl" "$bin/pactl"
sed -i "1c#!$(command -v bash)" "$bin/wpctl" "$bin/pactl"
HOME="$home" PATH="$bin:$PATH" run_adapter omarchy-audio-output-set-default 42 'sink with spaces'
grep -q '^wpctl set-default 42$' "$log"
grep -q '^pactl set-default-sink sink with spaces$' "$log"

ln -s "$adapter" "$bin/omarchy-audio-sink-availability"
HOME="$home" PATH="$bin:$PATH" run_adapter omarchy-audio-sink-availability > "$test_root/sinks"
grep -Fqx $'alsa_output.pci-1\t1' "$test_root/sinks"
grep -Fqx $'alsa_output.usb-1\t0' "$test_root/sinks"
ln -s "$adapter" "$bin/omarchy-audio-output-sink"
HOME="$home" PATH="$bin:$PATH" run_adapter omarchy-audio-output-sink > "$test_root/default-sink"
grep -Fqx -- 'alsa_output.pci-1' "$test_root/default-sink"
ln -s "$adapter" "$bin/omarchy-audio-input-set-default"
HOME="$home" PATH="$bin:$PATH" run_adapter omarchy-audio-input-set-default 43 source-with-spaces
grep -q '^pactl set-default-source source-with-spaces$' "$log"

if HOME="$home" PATH="$bin:$PATH" run_adapter omarchy-audio-output-set-default 2>"$test_root/error"; then
  printf '%s\n' 'invalid audio arguments unexpectedly succeeded' >&2
  exit 1
fi
grep -q 'Usage: omarchy-audio-output-set-default' "$test_root/error"

cat > "$bin/wl-copy" <<'EOF'
#!/usr/bin/env bash
cat > "$TEST_CLIPBOARD"
EOF
cat > "$bin/wtype" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$TEST_WTYPE"
EOF
chmod +x "$bin/wl-copy" "$bin/wtype"
emoji=$'\U0001F642'
sed -i "1c#!$(command -v bash)" "$bin/wl-copy" "$bin/wtype"
TEST_CLIPBOARD="$test_root/clipboard" TEST_WTYPE="$test_root/wtype" \
  HOME="$home" PATH="$bin:$PATH" run_adapter omarchy-menu-emoji-insert "$emoji"
grep -Fqx -- "$emoji" "$test_root/clipboard"

printf '%s\n' '[{"type":"text","text":"history text"}]' > "$state/clipboard-history.json"
TEST_CLIPBOARD="$test_root/clipboard" TEST_WTYPE="$test_root/wtype" \
  HOME="$home" PATH="$bin:$PATH" run_adapter omarchy-clipboard-paste-text --copy-only 'copied text'
grep -Fqx -- 'copied text' "$test_root/clipboard"
TEST_CLIPBOARD="$test_root/clipboard" TEST_WTYPE="$test_root/wtype" \
  HOME="$home" PATH="$bin:$PATH" run_adapter omarchy-clipboard-paste-text --copy-only --history-index 0
grep -Fqx -- 'history text' "$test_root/clipboard"
printf '%s\n' 'file payload' > "$test_root/payload.txt"
TEST_CLIPBOARD="$test_root/clipboard" TEST_WTYPE="$test_root/wtype" \
  HOME="$home" PATH="$bin:$PATH" run_adapter omarchy-clipboard-paste-file --copy-only text/plain "$test_root/payload.txt"
grep -Fqx -- 'file payload' "$test_root/clipboard"
cat > "$bin/xdg-open" <<EOF
#!/usr/bin/env bash
cat "\$1" > "$test_root/opened-entry"
EOF
chmod +x "$bin/xdg-open"
sed -i "1c#!$(command -v bash)" "$bin/xdg-open"
HOME="$home" PATH="$bin:$PATH" run_adapter omarchy-clipboard-open --history-index 0
for _ in $(seq 1 10); do
  [[ -f "$test_root/opened-entry" ]] && break
  sleep 0.1
done
grep -Fqx -- 'history text' "$test_root/opened-entry"

cat > "$bin/notify-send" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" > "$TEST_NOTIFICATION"
EOF
chmod +x "$bin/notify-send"
sed -i "1c#!$(command -v bash)" "$bin/notify-send"
TEST_NOTIFICATION="$test_root/notification" HOME="$home" PATH="$bin:$PATH" \
  run_adapter omarchy-notification-send 'Weather' 'Clear skies'
grep -Fqx -- '-a omanixy-action -u low Weather Clear skies' "$test_root/notification"

cat > "$bin/curl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' '12°C|5 km/h'
EOF
chmod +x "$bin/curl"
sed -i "1c#!$(command -v bash)" "$bin/curl"
ln -s "$adapter" "$bin/omarchy-weather-status"
HOME="$home" XDG_STATE_HOME="$home/.local/state" PATH="$bin:$PATH" \
  run_adapter omarchy-weather-status > "$test_root/weather"
grep -Fqx -- 'City & Name  ·  Temp 12°C  ·  Wind 5 km/h' "$test_root/weather"

cat > "$bin/grim" <<EOF
#!/usr/bin/env bash
printf 'PNG fixture' > "\$1"
EOF
chmod +x "$bin/grim"
sed -i "1c#!$(command -v bash)" "$bin/grim"
XDG_PICTURES_DIR="$test_root/pictures" TEST_CLIPBOARD="$test_root/clipboard" \
  HOME="$home" PATH="$bin:$PATH" run_adapter omarchy-capture-screenshot > "$test_root/screenshot"
test -f "$(<"$test_root/screenshot")"
grep -Fqx -- 'PNG fixture' "$test_root/clipboard"

cat > "$bin/gtk-launch" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" > "$test_root/gtk-launch"
EOF
chmod +x "$bin/gtk-launch"
sed -i "1c#!$(command -v bash)" "$bin/gtk-launch"
HOME="$home" PATH="$bin:$PATH" run_adapter uwsm-app -- gtk-launch org.example.App
grep -Fqx -- 'org.example.App' "$test_root/gtk-launch"

mkdir -p "$home/.local/share/applications"
printf '%s\n' '[Desktop Entry]' > "$home/.local/share/applications/org.example.Remove.desktop"
XDG_DATA_HOME="$home/.local/share" HOME="$home" PATH="$bin:$PATH" \
  run_adapter omarchy-remove-launcher-entry org.example.Remove 'Remove me'
test ! -e "$home/.local/share/applications/org.example.Remove.desktop"
if XDG_DATA_HOME="$home/.local/share" HOME="$home" PATH="$bin:$PATH" \
  run_adapter omarchy-remove-launcher-entry ../outside 'Invalid' 2>"$test_root/error"; then
  printf '%s\n' 'path traversal launcher ID unexpectedly succeeded' >&2
  exit 1
fi
grep -q 'Desktop ID is invalid' "$test_root/error"

cat > "$bin/brightnessctl" <<EOF
#!/usr/bin/env bash
if [[ \$1 == -m ]]; then
  printf 'backlight,sysfs/brightness,100,42%%,42%%\n'
else
  printf 'brightnessctl %s\n' "\$*" >> "$log"
fi
EOF
chmod +x "$bin/brightnessctl"
sed -i "1c#!$(command -v bash)" "$bin/brightnessctl"
ln -s "$adapter" "$bin/omarchy-brightness-display"
HOME="$home" PATH="$bin:$PATH" run_adapter omarchy-brightness-display --no-osd --monitor eDP-1 50%
grep -q '^brightnessctl set 50%$' "$log"
if HOME="$home" PATH="$bin:$PATH" run_adapter omarchy-brightness-display --monitor DP-1 50% 2>"$test_root/error"; then
  printf '%s\n' 'external brightness unexpectedly succeeded' >&2
  exit 1
fi
grep -q 'external-display brightness is unavailable' "$test_root/error"

cat > "$bin/nmcli" <<'EOF'
#!/usr/bin/env bash
if [[ $* == *GENERAL.CON-UUID* ]]; then
  printf '%s\n' uuid-1
else
  printf '%s\n' 'My;Wi,Fi:Zone' 'wpa-psk' 's e;cret' 'no' ''
fi
EOF
cat > "$bin/qrencode" <<'EOF'
#!/usr/bin/env bash
cat > "$TEST_QR_PAYLOAD"
printf '##\n  #\n'
EOF
chmod +x "$bin/nmcli" "$bin/qrencode"
sed -i "1c#!$(command -v bash)" "$bin/nmcli" "$bin/qrencode"
ln -s "$adapter" "$bin/omarchy-network-qr"
TEST_QR_PAYLOAD="$test_root/qr-payload" HOME="$home" PATH="$bin:$PATH" \
  run_adapter omarchy-network-qr --meta wlan0 > "$test_root/qr"
grep -Fqx $'meta\twlan0\tWPA\tMy;Wi,Fi:Zone' "$test_root/qr"
grep -Fqx '1' "$test_root/qr"
grep -Fqx 'WIFI:T:WPA;S:My\;Wi\,Fi\:Zone;P:s e\;cret;;' "$test_root/qr-payload"

cat > "$bin/ip" <<'EOF'
#!/usr/bin/env bash
if [[ $* == 'route get 1.1.1.1' ]]; then
  printf '%s\n' '1.1.1.1 dev fixture0 src 192.0.2.10'
elif [[ $* == '-j route get 1.1.1.1' ]]; then
  printf '%s\n' '[{"dev":"fixture0","prefsrc":"192.0.2.10","gateway":"192.0.2.1"}]'
elif [[ $* == '-j addr show fixture0' ]]; then
  printf '%s\n' '[{"addr_info":[{"family":"inet","prefixlen":24}]}]'
fi
EOF
chmod +x "$bin/ip"
sed -i "1c#!$(command -v bash)" "$bin/ip"
ln -s "$adapter" "$bin/omarchy-network-status"
HOME="$home" PATH="$bin:$PATH" run_adapter omarchy-network-status --verbose > "$test_root/network"
grep -Fqx -- $'iface\tfixture0' "$test_root/network"
grep -Fqx -- $'type\tethernet' "$test_root/network"
ln -s "$adapter" "$bin/omarchy-network-band"
if HOME="$home" PATH="$bin:$PATH" run_adapter omarchy-network-band invalid extra 2>"$test_root/error"; then
  printf '%s\n' 'invalid network band arguments unexpectedly succeeded' >&2
  exit 1
fi
grep -q 'Usage: omarchy-network-band' "$test_root/error"
ln -s "$adapter" "$bin/omarchy-dns"
if HOME="$home" PATH="$bin:$PATH" run_adapter omarchy-dns Invalid extra 2>"$test_root/error"; then
  printf '%s\n' 'invalid DNS arguments unexpectedly succeeded' >&2
  exit 1
fi
grep -q 'Usage: omarchy-dns' "$test_root/error"

cat > "$bin/bluetoothctl" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$log"
EOF
chmod +x "$bin/bluetoothctl"
sed -i "1c#!$(command -v bash)" "$bin/bluetoothctl"
ln -s "$adapter" "$bin/omarchy-bluetooth-device"
ln -s "$adapter" "$bin/omarchy-bluetooth-power"
HOME="$home" PATH="$bin:$PATH" run_adapter omarchy-bluetooth-device disconnect 00:11:22:33:44:55
HOME="$home" PATH="$bin:$PATH" run_adapter omarchy-bluetooth-power off
grep -q '^disconnect 00:11:22:33:44:55$' "$log"
grep -q '^power off$' "$log"

ln -s "$adapter" "$bin/omarchy-system-stats"
HOME="$home" PATH="$bin:$PATH" run_adapter omarchy-system-stats > "$test_root/system-stats"
grep -Fq $'cpu\t' "$test_root/system-stats"
ln -s "$adapter" "$bin/omarchy-display-text-size"
HOME="$home" PATH="$bin:$PATH" run_adapter omarchy-display-text-size 14
grep -Fqx -- 'base-size = 14' "$home/.config/omarchy/shell.toml"

cat > "$bin/hyprctl" <<'EOF'
#!/usr/bin/env bash
if [[ $* == 'monitors all -j' || $* == 'monitors -j' ]]; then
  printf '%s\n' '[{"name":"eDP-1","focused":true,"disabled":false,"width":1920,"height":1080,"scale":1.25,"mirrorOf":"none"}]'
else
  printf '%s\n' "$*" >> "$HYPRCTL_LOG"
fi
EOF
chmod +x "$bin/hyprctl"
sed -i "1c#!$(command -v bash)" "$bin/hyprctl"
ln -s "$adapter" "$bin/omarchy-monitor-state"
ln -s "$adapter" "$bin/omarchy-hyprland-monitor-scaling"
HYPRCTL_LOG="$test_root/hyprctl" HOME="$home" PATH="$bin:$PATH" \
  run_adapter omarchy-monitor-state > "$test_root/monitor"
head -n 1 "$test_root/monitor" | grep -Fqx -- '42'
HYPRCTL_LOG="$test_root/hyprctl" HOME="$home" PATH="$bin:$PATH" \
  run_adapter omarchy-hyprland-monitor-scaling > "$test_root/scaling"
grep -Fqx -- '1.25' "$test_root/scaling"

ln -s "$adapter" "$bin/omarchy-network-speedtest"
if HOME="$home" PATH="$bin:$PATH" run_adapter omarchy-network-speedtest invalid 2>"$test_root/error"; then
  printf '%s\n' 'invalid speed-test arguments unexpectedly succeeded' >&2
  exit 1
fi
grep -q 'Usage: omarchy-network-speedtest' "$test_root/error"

cat > "$bin/upower" <<'EOF'
#!/usr/bin/env bash
if [[ $1 == -e ]]; then
  printf '%s\n' '/org/freedesktop/UPower/devices/battery_BAT0'
else
  cat <<'BATTERY'
  native-path:          BAT0
  state:                charging
  percentage:           57%
  energy-full:         48 Wh
  energy-rate:         12.3 W
  time to full:         2.5 hours
BATTERY
fi
EOF
chmod +x "$bin/upower"
sed -i "1c#!$(command -v bash)" "$bin/upower"
mkdir -p "$test_root/power/BAT0"
printf '%s\n' 10000000 > "$test_root/power/BAT0/power_now"
printf '%s\n' 112 > "$test_root/power/BAT0/cycle_count"
ln -s "$adapter" "$bin/omarchy-battery-status"
OMARCHY_POWER_SUPPLY_PATH="$test_root/power" HOME="$home" PATH="$bin:$PATH" \
  run_adapter omarchy-battery-status --shell > "$test_root/battery"
grep -Fqx $'percentage\t57%' "$test_root/battery"
grep -Fqx $'state\tcharging' "$test_root/battery"
grep -Fqx $'rate\t10W' "$test_root/battery"
grep -Fqx $'size\t48Wh' "$test_root/battery"
grep -Fqx $'time\t2h 30m' "$test_root/battery"
grep -Fqx $'cycles\t112' "$test_root/battery"

cat > "$bin/powerprofilesctl" <<'EOF'
#!/usr/bin/env bash
if [[ $1 == list ]]; then
  cat <<'PROFILES'
  performance:
* balanced:
  power-saver:
PROFILES
elif [[ $1 == set ]]; then
  printf '%s\n' "$2" > "$TEST_PROFILE"
else
  exit 2
fi
EOF
chmod +x "$bin/powerprofilesctl"
sed -i "1c#!$(command -v bash)" "$bin/powerprofilesctl"
ln -s "$adapter" "$bin/omarchy-powerprofiles-list"
ln -s "$adapter" "$bin/omarchy-powerprofiles-set"
HOME="$home" XDG_STATE_HOME="$home/.local/state" PATH="$bin:$PATH" \
  run_adapter omarchy-powerprofiles-list --active-state > "$test_root/profiles"
grep -Fqx $'performance\t0' "$test_root/profiles"
grep -Fqx $'balanced\t1' "$test_root/profiles"
grep -Fqx $'power-saver\t0' "$test_root/profiles"
TEST_PROFILE="$test_root/profile" HOME="$home" XDG_STATE_HOME="$home/.local/state" PATH="$bin:$PATH" \
  run_adapter omarchy-powerprofiles-set ac performance
grep -Fqx performance "$test_root/profile"
grep -Fqx performance "$state/powerprofiles/ac"

printf '%s\n' 'compat adapter tests passed'
