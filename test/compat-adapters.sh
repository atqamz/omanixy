#!/usr/bin/env bash
set -euo pipefail

repo=$(cd "${1:?repository path required}" && pwd)
runtime_bin=${3:-}
adapter="$repo/packages/omanixy-shell/compat-adapter-test.bash"
test_root=$(mktemp -d)
bin="$test_root/bin"
home="$test_root/home"
state="$home/.local/state/omarchy"
log="$test_root/adapter.log"
mkdir -p "$bin" "$home" "$state"
trap 'rm -rf "$test_root"' EXIT
export HOME="$home"
export XDG_STATE_HOME="$home/.local/state"
export XDG_CONFIG_HOME="$home/.config"
export XDG_DATA_HOME="$home/.local/share"
export PATH="$bin:$PATH"
export OMANIXY_ADAPTER_DIR="$repo/packages/omanixy-shell"
case_log="$test_root/cases"
last_status=
record_case() {
  printf 'CASE\t%s\t%s\n' "$1" "$2" >> "$case_log"
  if [[ -n $last_status ]]; then
    printf 'STATUS\t%s\t%s\t%s\n' "$1" "$2" "$last_status" >> "$case_log"
  fi
}
bash_dir=$(dirname "$(command -v bash)")
env_bin=$(command -v env)

run_adapter() {
  local command=$1
  shift
  if "$env_bin" \
    HOME="$HOME" \
    PATH="$PATH" \
    XDG_STATE_HOME="${XDG_STATE_HOME:-}" \
    XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-}" \
    XDG_DATA_HOME="${XDG_DATA_HOME:-}" \
    XDG_PICTURES_DIR="${XDG_PICTURES_DIR:-}" \
    TEST_CLIPBOARD="${TEST_CLIPBOARD:-}" \
    TEST_WTYPE="${TEST_WTYPE:-}" \
    TEST_WTYPE_FAIL="${TEST_WTYPE_FAIL:-}" \
    TEST_WL_COPY_HOLD="${TEST_WL_COPY_HOLD:-}" \
    TEST_WL_COPY_FAIL="${TEST_WL_COPY_FAIL:-}" \
    TEST_XDG_OPEN_FAIL="${TEST_XDG_OPEN_FAIL:-}" \
    TEST_NOTIFICATION="${TEST_NOTIFICATION:-}" \
    TEST_NOTIFICATION_FAIL="${TEST_NOTIFICATION_FAIL:-}" \
    TEST_NOTIFICATION_PRINT_ID="${TEST_NOTIFICATION_PRINT_ID:-}" \
    TEST_WEATHER_MALFORMED="${TEST_WEATHER_MALFORMED:-}" \
    TEST_WEATHER_FAIL="${TEST_WEATHER_FAIL:-}" \
    TEST_QR_PAYLOAD="${TEST_QR_PAYLOAD:-}" \
    TEST_PROFILE="${TEST_PROFILE:-}" \
    TEST_PROFILE_FAIL="${TEST_PROFILE_FAIL:-}" \
    TEST_PROFILE_TIMEOUT="${TEST_PROFILE_TIMEOUT:-}" \
    TEST_RFKILL="${TEST_RFKILL:-}" \
    TEST_BLUETOOTH_FAIL="${TEST_BLUETOOTH_FAIL:-}" \
    TEST_BLUETOOTH_TIMEOUT="${TEST_BLUETOOTH_TIMEOUT:-}" \
    TEST_NMCLI_STATE="${TEST_NMCLI_STATE:-}" \
    TEST_NMCLI_FAIL="${TEST_NMCLI_FAIL:-}" \
    TEST_NMCLI_TIMEOUT="${TEST_NMCLI_TIMEOUT:-}" \
    TEST_NMCLI_ACTIVATE_FAIL="${TEST_NMCLI_ACTIVATE_FAIL:-}" \
    TEST_NMCLI_ROLLBACK_FAIL="${TEST_NMCLI_ROLLBACK_FAIL:-}" \
    TEST_NMCLI_SPECIAL="${TEST_NMCLI_SPECIAL:-}" \
    TEST_NMCLI_SCAN_FAIL="${TEST_NMCLI_SCAN_FAIL:-}" \
    TEST_IW_WRONG_BAND="${TEST_IW_WRONG_BAND:-}" \
    TEST_IP_TIMEOUT="${TEST_IP_TIMEOUT:-}" \
    TEST_IP_FAIL="${TEST_IP_FAIL:-}" \
    TEST_IP_NO_ROUTE="${TEST_IP_NO_ROUTE:-}" \
    TEST_BATTERY_STATE="${TEST_BATTERY_STATE:-}" \
    TEST_UPOWER_FAIL="${TEST_UPOWER_FAIL:-}" \
    TEST_BRIGHTNESS_FAIL="${TEST_BRIGHTNESS_FAIL:-}" \
    OMARCHY_POWERPROFILES_STATE_DIR="${OMARCHY_POWERPROFILES_STATE_DIR:-}" \
    OMARCHY_PROC_MEMINFO="${OMARCHY_PROC_MEMINFO:-}" \
    OMARCHY_PROC_STAT_BEFORE="${OMARCHY_PROC_STAT_BEFORE:-}" \
    OMARCHY_PROC_STAT_AFTER="${OMARCHY_PROC_STAT_AFTER:-}" \
    OMARCHY_PROC_LOADAVG="${OMARCHY_PROC_LOADAVG:-}" \
    OMARCHY_CPU_SAMPLE_INTERVAL="${OMARCHY_CPU_SAMPLE_INTERVAL:-}" \
    HYPRCTL_LOG="${HYPRCTL_LOG:-}" \
    OMARCHY_POWER_SUPPLY_PATH="${OMARCHY_POWER_SUPPLY_PATH:-}" \
    TEST_GRIM_FAIL="${TEST_GRIM_FAIL:-}" \
    TEST_DESKTOP_DATABASE_FAIL="${TEST_DESKTOP_DATABASE_FAIL:-}" \
    TEST_DESKTOP_DATABASE_FAIL_ONCE="${TEST_DESKTOP_DATABASE_FAIL_ONCE:-}" \
    TEST_DESKTOP_DATABASE_STATE="${TEST_DESKTOP_DATABASE_STATE:-}" \
    TEST_HYPRCTL_FAIL_SECOND="${TEST_HYPRCTL_FAIL_SECOND:-}" \
    TEST_HYPRCTL_FAIL="${TEST_HYPRCTL_FAIL:-}" \
    TEST_HYPRCTL_NO_FOCUS="${TEST_HYPRCTL_NO_FOCUS:-}" \
    TEST_HYPRCTL_MALFORMED="${TEST_HYPRCTL_MALFORMED:-}" \
    TEST_SLURP_CANCEL="${TEST_SLURP_CANCEL:-}" \
    TEST_SLURP_TINY="${TEST_SLURP_TINY:-}" \
    TEST_HYPRPICKER_FAIL="${TEST_HYPRPICKER_FAIL:-}" \
    TEST_GRIM_GEOMETRY="${TEST_GRIM_GEOMETRY:-}" \
    TEST_GSETTINGS_FAIL="${TEST_GSETTINGS_FAIL:-}" \
    TEST_GSETTINGS_SET_FAIL="${TEST_GSETTINGS_SET_FAIL:-}" \
    TEST_GSETTINGS_LOG="${TEST_GSETTINGS_LOG:-}" \
    TEST_FOOT_RUNNING="${TEST_FOOT_RUNNING:-}" \
    TEST_PACTL_FAIL_MOVE="${TEST_PACTL_FAIL_MOVE:-}" \
    TEST_PACTL_FAIL_MOVE_ONCE="${TEST_PACTL_FAIL_MOVE_ONCE:-}" \
    TEST_PACTL_FAIL_SINK_INSPECTION="${TEST_PACTL_FAIL_SINK_INSPECTION:-}" \
    TEST_PW_DUMP_FAIL="${TEST_PW_DUMP_FAIL:-}" \
    TEST_PACTL_DSP="${TEST_PACTL_DSP:-}" \
    TEST_PACTL_LOG="${TEST_PACTL_LOG:-}" \
    COMPAT_ADAPTER_NAME="$command" \
  bash "$bin/$command" "$@"; then
    last_status=0
  else
    last_status=$?
  fi
  return "$last_status"
}

link_adapter() { [[ -e "$bin/$1" ]] || ln -s "$adapter" "$bin/$1"; }
if [[ -n "$runtime_bin" ]]; then
  runtime_copy="$test_root/runtime-bin"
  mkdir -p "$runtime_copy"
  for helper in $(jq -r '.helpers | keys[]' "$repo/upstream/compatibility-contracts.json"); do
    cp "$runtime_bin/$helper" "$runtime_copy/$helper"
    sed -i "s|^export PATH=.*$|export PATH=\"\${PATH}\"|" "$runtime_copy/$helper"
    chmod +x "$runtime_copy/$helper"
    ln -s "$runtime_copy/$helper" "$bin/$helper"
  done
else
  link_adapter omarchy-weather-location
fi
if [[ -z "$runtime_bin" ]]; then
  link_adapter omarchy-audio-output-set-default
  link_adapter omarchy-menu-emoji-insert
  link_adapter omarchy-notification-send
  link_adapter omarchy-clipboard-paste-text
  link_adapter omarchy-clipboard-paste-file
  link_adapter omarchy-clipboard-open
  link_adapter omarchy-capture-screenshot
  link_adapter omarchy-remove-launcher-entry
fi

HOME="$home" XDG_STATE_HOME="$home/.local/state" PATH="$bin:$PATH" \
  run_adapter omarchy-weather-location --set 'City & Name' '1.25,-2.5'
jq -e '.name == "City & Name" and .latitude == 1.25 and .longitude == -2.5' \
  "$state/settings/weather.json" >/dev/null
record_case omarchy-weather-location valid
record_case omarchy-weather-location stdout

weather_location_invalid_status=0
if HOME="$home" XDG_STATE_HOME="$home/.local/state" PATH="$bin:$PATH" \
  run_adapter omarchy-weather-location --set broken 'not-coordinates' 2>"$test_root/error"; then
  printf '%s\n' 'malformed weather coordinates unexpectedly succeeded' >&2
  exit 1
else
  weather_location_invalid_status=$?
fi
test "$weather_location_invalid_status" -eq 2
grep -q 'Invalid coordinates' "$test_root/error"
record_case omarchy-weather-location invalidArgs

printf '%s\n' 'audio' > "$log"
cat > "$bin/wpctl" <<EOF
#!/usr/bin/env bash
if [[ \$1 == inspect && \$2 == @DEFAULT_AUDIO_SINK@ ]]; then
  printf '%s\n' 'node.name = "alsa_output.pci-1"'
else
  printf 'wpctl %s\n' "\$*" >> "$log"
fi
EOF
cat > "$bin/pw-dump" <<'EOF'
#!/usr/bin/env bash
[[ ${TEST_PW_DUMP_FAIL:-} == 1 ]] && exit 1
cat <<'JSON'
[
  {"id":42,"type":"PipeWire:Interface:Node","info":{"props":{"media.class":"Audio/Sink","node.name":"alsa_output.pci-1"}}},
  {"id":43,"type":"PipeWire:Interface:Node","info":{"props":{"media.class":"Audio/Sink","node.name":"alsa_output.usb-1"}}},
  {"id":44,"type":"PipeWire:Interface:Node","info":{"props":{"media.class":"Audio/Source","node.name":"alsa_input.pci-1"}}},
  {"id":142,"type":"PipeWire:Interface:Port","info":{"props":{"port.node":42,"port.direction":"out","port.availability":"yes"}}},
  {"id":143,"type":"PipeWire:Interface:Port","info":{"props":{"port.node":43,"port.direction":"out","port.availability":"no"}}}
]
JSON
EOF
cat > "$bin/pactl" <<'EOF'
#!/usr/bin/env bash
case "$1 $2" in
  'get-default-sink ') [[ ${TEST_PACTL_DSP:-} == 1 ]] && printf '%s\n' easyeffects_sink || printf '%s\n' alsa_output.pci-1 ;;
  'get-default-source ') printf '%s\n' alsa_input.pci-1 ;;
  'list sink-inputs') [[ ${TEST_PACTL_FAIL_SINK_INSPECTION:-} != 1 ]] || exit 1
    if [[ ${TEST_PACTL_DSP:-} == 1 ]]; then cat <<'INPUTS'
Sink Input #31
  Sink: 42
  node.name = "easyeffects_sink"
  application.name = "EasyEffects"
INPUTS
    else cat <<'INPUTS'
Sink Input #11
  Sink: 42
  application.name = "Firefox"
Sink Input #12
  Sink: 42
  application.name = "EasyEffects"
Sink Input #13
  Sink: 42
  application.name = "Music"
Sink Input #14
  Sink: 42
INPUTS
    fi
    ;;
  'list source-outputs') cat <<'OUTPUTS'
Source Output #21
  Source: 44
  application.name = "Recorder"
OUTPUTS
    ;;
  'list sinks') printf '%s\n' '42 alsa_output.pci-1' '43 alsa_output.usb-1' '99 easyeffects_sink' ;;
  'set-default-sink '*|'set-default-source '* ) printf 'pactl %s\n' "$*" >> "$TEST_PACTL_LOG" ;;
  'move-sink-input '*|'move-source-output '* )
    printf 'pactl %s\n' "$*" >> "$TEST_PACTL_LOG"
    if [[ ${TEST_PACTL_FAIL_MOVE:-} == "$2" ]]; then exit 1; fi
    if [[ ${TEST_PACTL_FAIL_MOVE_ONCE:-} == "$2" && ! -e "$TEST_PACTL_LOG.fail-$2" ]]; then
      : > "$TEST_PACTL_LOG.fail-$2"
      exit 1
    fi
    ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$bin/wpctl" "$bin/pw-dump"
chmod +x "$bin/pactl"
sed -i "1c#!$(command -v bash)" "$bin/wpctl" "$bin/pw-dump" "$bin/pactl"
export TEST_PACTL_LOG="$log"
HOME="$home" PATH="$bin:$PATH" run_adapter omarchy-audio-output-set-default 42 alsa_output.pci-1
grep -q '^wpctl set-default 42$' "$log"
grep -q '^pactl set-default-sink alsa_output.pci-1$' "$log"
grep -q '^pactl move-sink-input 11 alsa_output.pci-1$' "$log"
if grep -q '^pactl move-sink-input 12 ' "$log"; then
  printf '%s\n' 'EasyEffects stream was migrated unexpectedly' >&2
  exit 1
fi
if grep -q '^pactl move-sink-input 14 ' "$log"; then
  printf '%s\n' 'DSP filter-chain stream was migrated unexpectedly' >&2
  exit 1
fi
record_case omarchy-audio-output-set-default valid
record_case omarchy-audio-output-set-default stdout
if HOME="$home" PATH="$bin:$PATH" run_adapter omarchy-audio-output-set-default 42 'sink with spaces' 2>"$test_root/error"; then
  printf '%s\n' 'mismatched PipeWire output unexpectedly succeeded' >&2
  exit 1
fi
grep -q 'does not match PipeWire metadata' "$test_root/error"

: > "$TEST_PACTL_LOG"
if TEST_PACTL_FAIL_MOVE_ONCE=13 HOME="$home" PATH="$bin:$PATH" \
  run_adapter omarchy-audio-output-set-default 43 alsa_output.usb-1 2>"$test_root/error"; then
  printf '%s\n' 'stream migration failure unexpectedly succeeded' >&2
  exit 1
fi
grep -q 'previous default and streams were restored' "$test_root/error"
grep -q '^pactl move-sink-input 11 alsa_output.usb-1$' "$TEST_PACTL_LOG"
grep -q '^pactl move-sink-input 13 alsa_output.usb-1$' "$TEST_PACTL_LOG"
grep -q '^pactl move-sink-input 11 42$' "$TEST_PACTL_LOG"
grep -q '^pactl move-sink-input 13 42$' "$TEST_PACTL_LOG"
grep -q '^pactl set-default-sink alsa_output.pci-1$' "$TEST_PACTL_LOG"
if TEST_PACTL_FAIL_MOVE=11 HOME="$home" PATH="$bin:$PATH" \
  run_adapter omarchy-audio-output-set-default 43 alsa_output.usb-1 2>"$test_root/error"; then
  printf '%s\n' 'audio rollback failure unexpectedly succeeded' >&2
  exit 1
fi
grep -q 'rollback was incomplete' "$test_root/error"
record_case omarchy-audio-output-set-default backendFailure

link_adapter omarchy-audio-sink-availability
HOME="$home" PATH="$bin:$PATH" run_adapter omarchy-audio-sink-availability > "$test_root/sinks"
grep -Fqx $'alsa_output.pci-1\t1' "$test_root/sinks"
grep -Fqx $'alsa_output.usb-1\t0' "$test_root/sinks"
record_case omarchy-audio-sink-availability valid
record_case omarchy-audio-sink-availability stdout
audio_availability_failure_status=0
if TEST_PW_DUMP_FAIL=1 HOME="$home" PATH="$bin:$PATH" \
  run_adapter omarchy-audio-sink-availability 2>"$test_root/error"; then
  printf '%s\n' 'PipeWire availability failure unexpectedly succeeded' >&2
  exit 1
else
  audio_availability_failure_status=$?
fi
test "$audio_availability_failure_status" -eq 4
record_case omarchy-audio-sink-availability backendFailure
link_adapter omarchy-audio-output-sink
HOME="$home" PATH="$bin:$PATH" run_adapter omarchy-audio-output-sink > "$test_root/default-sink"
grep -Fqx -- 'alsa_output.pci-1' "$test_root/default-sink"
record_case omarchy-audio-output-sink valid
record_case omarchy-audio-output-sink stdout
TEST_PACTL_DSP=1 HOME="$home" PATH="$bin:$PATH" \
  run_adapter omarchy-audio-output-sink > "$test_root/dsp-sink"
grep -Fqx -- 'alsa_output.pci-1' "$test_root/dsp-sink"
export TEST_PACTL_DSP=1 TEST_PACTL_FAIL_SINK_INSPECTION=1
if HOME="$home" PATH="$bin:$PATH" run_adapter omarchy-audio-output-sink 2>"$test_root/error"; then
  printf '%s\n' 'audio DSP inspection failure unexpectedly succeeded' >&2
  exit 1
fi
unset TEST_PACTL_DSP TEST_PACTL_FAIL_SINK_INSPECTION
grep -q 'DSP sink inspection failed' "$test_root/error"
record_case omarchy-audio-output-sink backendFailure
link_adapter omarchy-audio-input-set-default
HOME="$home" PATH="$bin:$PATH" run_adapter omarchy-audio-input-set-default 44 alsa_input.pci-1
grep -q '^wpctl set-default 44$' "$log"
record_case omarchy-audio-input-set-default valid
record_case omarchy-audio-input-set-default stdout
: > "$TEST_PACTL_LOG"
export TEST_PACTL_FAIL_MOVE=21
if HOME="$home" PATH="$bin:$PATH" \
  run_adapter omarchy-audio-input-set-default 44 alsa_input.pci-1 2>"$test_root/error"; then
  printf '%s\n' 'input stream migration failure unexpectedly succeeded' >&2
  exit 1
fi
unset TEST_PACTL_FAIL_MOVE
grep -q 'rollback was incomplete' "$test_root/error"
record_case omarchy-audio-input-set-default backendFailure
grep -q '^pactl move-source-output 21 alsa_input.pci-1$' "$TEST_PACTL_LOG"
grep -q '^pactl move-source-output 21 44$' "$TEST_PACTL_LOG"
grep -q '^pactl set-default-source alsa_input.pci-1$' "$TEST_PACTL_LOG"

audio_invalid_status=0
if HOME="$home" PATH="$bin:$PATH" run_adapter omarchy-audio-output-set-default 2>"$test_root/error"; then
  printf '%s\n' 'invalid audio arguments unexpectedly succeeded' >&2
  exit 1
else
  audio_invalid_status=$?
fi
test "$audio_invalid_status" -eq 2
grep -q 'Usage: omarchy-audio-output-set-default' "$test_root/error"
record_case omarchy-audio-output-set-default invalidArgs

cat > "$bin/wl-copy" <<'EOF'
#!/usr/bin/env bash
[[ ${TEST_WL_COPY_FAIL:-} == 1 ]] && exit 1
cat > "$TEST_CLIPBOARD"
if [[ ${TEST_WL_COPY_HOLD:-} == 1 ]]; then
  while :; do sleep 1; done
fi
EOF
cat > "$bin/wtype" <<'EOF'
#!/usr/bin/env bash
[[ ${TEST_WTYPE_FAIL:-} == 1 ]] && exit 1
printf '%s\n' "$*" >> "$TEST_WTYPE"
EOF
chmod +x "$bin/wl-copy" "$bin/wtype"
emoji=$'\U0001F642'
sed -i "1c#!$(command -v bash)" "$bin/wl-copy" "$bin/wtype"
TEST_CLIPBOARD="$test_root/clipboard" TEST_WTYPE="$test_root/wtype" \
  HOME="$home" PATH="$bin:$PATH" run_adapter omarchy-menu-emoji-insert "$emoji"
grep -Fqx -- "$emoji" "$test_root/clipboard"
record_case omarchy-menu-emoji-insert valid
record_case omarchy-menu-emoji-insert stdout
TEST_CLIPBOARD="$test_root/clipboard" TEST_WTYPE="$test_root/wtype" TEST_WL_COPY_HOLD=1 TEST_WTYPE_FAIL=1 \
  HOME="$home" PATH="$bin:$PATH" run_adapter omarchy-menu-emoji-insert "$emoji"
TEST_CLIPBOARD="$test_root/clipboard" TEST_WTYPE="$test_root/wtype" \
  HOME="$home" PATH="$bin:$PATH" run_adapter omarchy-menu-emoji-insert ''
if TEST_CLIPBOARD="$test_root/clipboard" TEST_WTYPE="$test_root/wtype" TEST_WL_COPY_FAIL=1 \
  HOME="$home" PATH="$bin:$PATH" run_adapter omarchy-menu-emoji-insert "$emoji" 2>"$test_root/error"; then
  printf '%s\n' 'emoji clipboard backend failure unexpectedly succeeded' >&2
  exit 1
fi
grep -q 'emoji clipboard copy failed' "$test_root/error"
record_case omarchy-menu-emoji-insert backendFailure

printf '%s\n' '[{"type":"text","text":"history text"}]' > "$state/clipboard-history.json"
TEST_CLIPBOARD="$test_root/clipboard" TEST_WTYPE="$test_root/wtype" \
  HOME="$home" PATH="$bin:$PATH" run_adapter omarchy-clipboard-paste-text --copy-only 'copied text'
grep -Fqx -- 'copied text' "$test_root/clipboard"
TEST_CLIPBOARD="$test_root/clipboard" TEST_WTYPE="$test_root/wtype" \
  HOME="$home" PATH="$bin:$PATH" run_adapter omarchy-clipboard-paste-text --copy-only --history-index 0
grep -Fqx -- 'history text' "$test_root/clipboard"
record_case omarchy-clipboard-paste-text valid
record_case omarchy-clipboard-paste-text stdout
paste_text_failure_status=0
if TEST_WL_COPY_FAIL=1 TEST_CLIPBOARD="$test_root/clipboard" HOME="$home" PATH="$bin:$PATH" \
  run_adapter omarchy-clipboard-paste-text --copy-only 'failure' 2>"$test_root/error"; then
  printf '%s\n' 'clipboard text backend failure unexpectedly succeeded' >&2
  exit 1
else
  paste_text_failure_status=$?
fi
test "$paste_text_failure_status" -eq 1
record_case omarchy-clipboard-paste-text backendFailure
if HOME="$home" PATH="$bin:$PATH" run_adapter omarchy-clipboard-paste-text --history-index 0 'ignored text' 2>"$test_root/error"; then
  printf '%s\n' 'conflicting clipboard history and text arguments unexpectedly succeeded' >&2
  exit 1
fi
grep -q 'cannot include text' "$test_root/error"
printf '%s\n' 'file payload' > "$test_root/payload.txt"
TEST_CLIPBOARD="$test_root/clipboard" TEST_WTYPE="$test_root/wtype" \
  HOME="$home" PATH="$bin:$PATH" run_adapter omarchy-clipboard-paste-file --copy-only text/plain "$test_root/payload.txt"
grep -Fqx -- 'file payload' "$test_root/clipboard"
record_case omarchy-clipboard-paste-file valid
record_case omarchy-clipboard-paste-file stdout
paste_file_failure_status=0
if TEST_WL_COPY_FAIL=1 TEST_CLIPBOARD="$test_root/clipboard" HOME="$home" PATH="$bin:$PATH" \
  run_adapter omarchy-clipboard-paste-file --copy-only text/plain "$test_root/payload.txt" 2>"$test_root/error"; then
  printf '%s\n' 'clipboard file backend failure unexpectedly succeeded' >&2
  exit 1
else
  paste_file_failure_status=$?
fi
test "$paste_file_failure_status" -eq 1
record_case omarchy-clipboard-paste-file backendFailure
cat > "$bin/xdg-open" <<EOF
#!/usr/bin/env bash
[[ \${TEST_XDG_OPEN_FAIL:-} == 1 ]] && exit 1
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
record_case omarchy-clipboard-open valid
record_case omarchy-clipboard-open stdout
if TEST_XDG_OPEN_FAIL=1 HOME="$home" PATH="$bin:$PATH" \
  run_adapter omarchy-clipboard-open --history-index 0 2>"$test_root/error"; then
  printf '%s\n' 'failed clipboard opener unexpectedly succeeded' >&2
  exit 1
fi
grep -q 'clipboard entry opener failed' "$test_root/error"
record_case omarchy-clipboard-open backendFailure
printf '%s\n' 'PNG history fixture' > "$test_root/history.png"
jq -n --arg path "$test_root/history.png" \
  '[{type:"text",text:"history text"},{type:"image",path:$path}]' > "$state/clipboard-history.json"
HOME="$home" PATH="$bin:$PATH" run_adapter omarchy-clipboard-open --history-index 1
grep -Fqx -- 'PNG history fixture' "$test_root/opened-entry"
if TEST_XDG_OPEN_FAIL=1 HOME="$home" PATH="$bin:$PATH" \
  run_adapter omarchy-clipboard-open --history-index 1 2>"$test_root/error"; then
  printf '%s\n' 'failed clipboard image opener unexpectedly succeeded' >&2
  exit 1
fi
grep -q 'clipboard image opener failed' "$test_root/error"

cat > "$bin/notify-send" <<'EOF'
#!/usr/bin/env bash
[[ ${TEST_NOTIFICATION_FAIL:-} == 1 ]] && exit 1
printf '%s\n' "$@" > "$TEST_NOTIFICATION"
for argument; do
  if [[ $argument == -p && ${TEST_NOTIFICATION_PRINT_ID:-} == 1 ]]; then
    printf '%s\n' 31415
  fi
done
EOF
chmod +x "$bin/notify-send"
sed -i "1c#!$(command -v bash)" "$bin/notify-send"
TEST_NOTIFICATION="$test_root/notification" TEST_NOTIFICATION_PRINT_ID=1 HOME="$home" PATH="$bin:$PATH" \
  run_adapter omarchy-notification-send 'Weather' 'Clear skies'
mapfile -t notification_args < "$test_root/notification"
[[ ${notification_args[*]} == '-a omarchy-action -u low Weather Clear skies' ]]
record_case omarchy-notification-send valid
record_case omarchy-notification-send stdout
TEST_NOTIFICATION="$test_root/notification" TEST_NOTIFICATION_PRINT_ID=1 HOME="$home" PATH="$bin:$PATH" \
  notification_id=$(run_adapter omarchy-notification-send 'Restart Foot' -r 42 -p)
[[ $notification_id == 31415 ]]
mapfile -t notification_args < "$test_root/notification"
[[ ${notification_args[*]} == '-r 42 -p -a omarchy-action -u low Restart Foot' ]]
TEST_NOTIFICATION="$test_root/notification" TEST_NOTIFICATION_PRINT_ID='' HOME="$home" PATH="$bin:$PATH" \
  run_adapter omarchy-notification-send --exec 'omarchy-shell shell ping' --app-name custom -g glyph -u critical --image /tmp/image.png 'Headline' 'Body' -p
mapfile -t notification_args < "$test_root/notification"
[[ ${notification_args[*]} == '-p -a custom -u critical --hint=string:omarchy-glyph:glyph --hint=string:image-path:/tmp/image.png --hint=string:omarchy-exec:omarchy-shell shell ping Headline Body' ]]
notification_invalid_status=0
if TEST_NOTIFICATION="$test_root/notification" HOME="$home" PATH="$bin:$PATH" \
  run_adapter omarchy-notification-send 'Restart Foot' -r invalid 2>"$test_root/error"; then
  printf '%s\n' 'invalid notification replacement id unexpectedly succeeded' >&2
  exit 1
else
  notification_invalid_status=$?
fi
test "$notification_invalid_status" -eq 2
grep -q 'Notification replacement id must be numeric' "$test_root/error"
record_case omarchy-notification-send invalidArgs
notification_failure_status=0
if TEST_NOTIFICATION_FAIL=1 TEST_NOTIFICATION="$test_root/notification" HOME="$home" PATH="$bin:$PATH" \
  run_adapter omarchy-notification-send 'Headline' 2>"$test_root/error"; then
  printf '%s\n' 'notification backend failure unexpectedly succeeded' >&2
  exit 1
else
  notification_failure_status=$?
fi
test "$notification_failure_status" -eq 1
record_case omarchy-notification-send backendFailure

cat > "$bin/curl" <<'EOF'
#!/usr/bin/env bash
[[ ${TEST_WEATHER_FAIL:-} == 1 ]] && exit 1
if [[ ${TEST_WEATHER_MALFORMED:-} == 1 ]]; then printf '%s\n' 'malformed'; else printf '%s\n' '12°C|5 km/h'; fi
EOF
chmod +x "$bin/curl"
sed -i "1c#!$(command -v bash)" "$bin/curl"
link_adapter omarchy-weather-status
HOME="$home" XDG_STATE_HOME="$home/.local/state" PATH="$bin:$PATH" \
  run_adapter omarchy-weather-status > "$test_root/weather"
grep -Fqx -- 'City & Name  ·  Temp 12°C  ·  Wind 5 km/h' "$test_root/weather"
record_case omarchy-weather-status valid
record_case omarchy-weather-status stdout
if TEST_WEATHER_MALFORMED=1 HOME="$home" XDG_STATE_HOME="$home/.local/state" PATH="$bin:$PATH" \
  run_adapter omarchy-weather-status 2>"$test_root/error"; then
  printf '%s\n' 'malformed weather response unexpectedly succeeded' >&2
  exit 1
fi
grep -q 'weather service returned malformed data' "$test_root/error"
if TEST_WEATHER_FAIL=1 HOME="$home" XDG_STATE_HOME="$home/.local/state" PATH="$bin:$PATH" \
  run_adapter omarchy-weather-status 2>"$test_root/error"; then
  printf '%s\n' 'weather backend failure unexpectedly succeeded' >&2
  exit 1
fi
grep -q 'weather service is unavailable' "$test_root/error"
record_case omarchy-weather-status backendFailure
rm -f "$state/settings/weather.json"
if TEST_WEATHER_FAIL=1 HOME="$home" XDG_STATE_HOME="$home/.local/state" PATH="$bin:$PATH" \
  run_adapter omarchy-weather-location 2>"$test_root/error"; then
  printf '%s\n' 'weather location backend failure unexpectedly succeeded' >&2
  exit 1
fi
grep -q 'weather location lookup failed' "$test_root/error"
record_case omarchy-weather-location backendFailure

cat > "$bin/grim" <<EOF
#!/usr/bin/env bash
[[ \${TEST_GRIM_FAIL:-} == 1 ]] && exit 1
output=\${@: -1}
[[ -n \${TEST_GRIM_GEOMETRY:-} ]] && printf '%s\n' "\$2" > "\${TEST_GRIM_GEOMETRY}"
if [[ \$output == - ]]; then printf 'PNG fixture'; else printf 'PNG fixture' > "\$output"; fi
EOF
cat > "$bin/slurp" <<'EOF'
#!/usr/bin/env bash
[[ ${TEST_SLURP_CANCEL:-} == 1 ]] && exit 1
cat >/dev/null
if [[ ${TEST_SLURP_TINY:-} == 1 ]]; then printf '%s\n' '0,0 2x2'; else printf '%s\n' '0,0 1920x1080'; fi
EOF
cat > "$bin/hyprpicker" <<'EOF'
#!/usr/bin/env bash
[[ ${TEST_HYPRPICKER_FAIL:-} == 1 ]] && exit 1
[[ -n ${TEST_FREEZE_PID:-} ]] && printf '%s\n' "$BASHPID" > "$TEST_FREEZE_PID"
while :; do sleep 1; done
EOF
cat > "$bin/hyprctl" <<'EOF'
#!/usr/bin/env bash
case "$*" in
  'getoption cursor:no_hardware_cursors -j') printf '%s\n' '{"int":1}' ;;
  'monitors -j') printf '%s\n' '[{"focused":true,"activeWorkspace":{"id":1},"x":0,"y":0,"width":1920,"height":1080,"scale":1}]' ;;
  'clients -j') printf '%s\n' '[]' ;;
  *) : ;;
esac
EOF
chmod +x "$bin/grim"
chmod +x "$bin/slurp" "$bin/hyprpicker" "$bin/hyprctl"
sed -i "1c#!$(command -v bash)" "$bin/grim" "$bin/slurp" "$bin/hyprpicker" "$bin/hyprctl"
XDG_PICTURES_DIR="$test_root/pictures" TEST_CLIPBOARD="$test_root/clipboard" TEST_FREEZE_PID="$test_root/freeze.pid" \
  HOME="$home" PATH="$bin:$PATH" run_adapter omarchy-capture-screenshot > "$test_root/screenshot"
test -f "$(<"$test_root/screenshot")"
grep -Fqx -- 'PNG fixture' "$test_root/clipboard"
if kill -0 "$(<"$test_root/freeze.pid")" 2>/dev/null; then
  printf '%s\n' 'screenshot freeze process leaked' >&2
  exit 1
fi
record_case omarchy-capture-screenshot valid
record_case omarchy-capture-screenshot stdout
if TEST_GRIM_FAIL=1 XDG_PICTURES_DIR="$test_root/pictures" HOME="$home" PATH="$bin:$PATH" \
  run_adapter omarchy-capture-screenshot >"$test_root/error-output" 2>"$test_root/error"; then
  printf '%s\n' 'failed screenshot capture unexpectedly succeeded' >&2
  exit 1
fi
test ! -s "$test_root/error-output"
grep -q 'screenshot backend failed' "$test_root/error"
if TEST_HYPRPICKER_FAIL=1 XDG_PICTURES_DIR="$test_root/pictures" HOME="$home" PATH="$bin:$PATH" \
  run_adapter omarchy-capture-screenshot >"$test_root/error-output" 2>"$test_root/error"; then
  printf '%s\n' 'failed screenshot freeze unexpectedly succeeded' >&2
  exit 1
fi
test ! -s "$test_root/error-output"
grep -q 'screenshot freeze backend failed' "$test_root/error"
record_case omarchy-capture-screenshot backendFailure
TEST_WL_COPY_FAIL=1 XDG_PICTURES_DIR="$test_root/pictures" HOME="$home" PATH="$bin:$PATH" \
  run_adapter omarchy-capture-screenshot >"$test_root/screenshot-no-clipboard" 2>"$test_root/error"
test -f "$(<"$test_root/screenshot-no-clipboard")"
grep -q 'clipboard copy failed' "$test_root/error"
TEST_GRIM_GEOMETRY="$test_root/smart-geometry" TEST_SLURP_TINY=1 \
  TEST_CLIPBOARD="$test_root/smart-clipboard" XDG_PICTURES_DIR="$test_root/pictures" \
  HOME="$home" PATH="$bin:$PATH" \
  run_adapter omarchy-capture-screenshot >/dev/null
grep -Fqx -- '0,0 1920x1080' "$test_root/smart-geometry"
if TEST_SLURP_CANCEL=1 XDG_PICTURES_DIR="$test_root/pictures" HOME="$home" PATH="$bin:$PATH" \
  run_adapter omarchy-capture-screenshot >"$test_root/screenshot-cancel"; then
  test ! -s "$test_root/screenshot-cancel"
else
  printf '%s\n' 'screenshot cancellation unexpectedly failed' >&2
  exit 1
fi
XDG_PICTURES_DIR="$test_root/pictures" TEST_CLIPBOARD="$test_root/clipboard" \
  HOME="$home" PATH="$bin:$PATH" first_screenshot=$(run_adapter omarchy-capture-screenshot)
XDG_PICTURES_DIR="$test_root/pictures" TEST_CLIPBOARD="$test_root/clipboard" \
  HOME="$home" PATH="$bin:$PATH" second_screenshot=$(run_adapter omarchy-capture-screenshot)
test "$first_screenshot" != "$second_screenshot"
test -f "$first_screenshot"
test -f "$second_screenshot"
XDG_PICTURES_DIR="$test_root/pictures" TEST_CLIPBOARD="$test_root/clipboard-copy" \
  HOME="$home" PATH="$bin:$PATH" run_adapter omarchy-capture-screenshot fullscreen copy
grep -Fqx -- 'PNG fixture' "$test_root/clipboard-copy"
saved_screenshot=$(XDG_PICTURES_DIR="$test_root/pictures" HOME="$home" PATH="$bin:$PATH" \
  run_adapter omarchy-capture-screenshot fullscreen save)
test -f "$saved_screenshot"
TEST_NOTIFICATION="$test_root/screenshot-notification" XDG_PICTURES_DIR="$test_root/pictures" \
  HOME="$home" PATH="$bin:$PATH" \
  run_adapter omarchy-capture-screenshot --editor=custom-editor region slurp >/dev/null
grep -Fq -- '--hint=string:omarchy-exec:custom-editor' "$test_root/screenshot-notification"
record_case omarchy-capture-screenshot editor
screenshot_invalid_status=0
if HOME="$home" PATH="$bin:$PATH" run_adapter omarchy-capture-screenshot invalid 2>"$test_root/error"; then
  printf '%s\n' 'invalid screenshot mode unexpectedly succeeded' >&2
  exit 1
else
  screenshot_invalid_status=$?
fi
test "$screenshot_invalid_status" -eq 2
grep -q 'Usage: omarchy-capture-screenshot' "$test_root/error"
record_case omarchy-capture-screenshot invalidArgs

mkdir -p "$home/.local/share/applications"
cat > "$bin/update-desktop-database" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$TEST_DESKTOP_DATABASE_STATE"
if [[ ${TEST_DESKTOP_DATABASE_FAIL:-} == 1 ]]; then
  exit 1
fi
if [[ ${TEST_DESKTOP_DATABASE_FAIL_ONCE:-} == 1 && ! -e ${TEST_DESKTOP_DATABASE_STATE}.failed ]]; then
  touch "${TEST_DESKTOP_DATABASE_STATE}.failed"
  exit 1
fi
EOF
chmod +x "$bin/update-desktop-database"
sed -i "1c#!$(command -v bash)" "$bin/update-desktop-database"
export TEST_DESKTOP_DATABASE_STATE="$test_root/desktop-database"
printf '%s\n' '[Desktop Entry]' > "$home/.local/share/applications/org.example.Remove.desktop"
XDG_DATA_HOME="$home/.local/share" HOME="$home" PATH="$bin:$PATH" \
  run_adapter omarchy-remove-launcher-entry org.example.Remove 'Remove me'
test ! -e "$home/.local/share/applications/org.example.Remove.desktop"
record_case omarchy-remove-launcher-entry valid
record_case omarchy-remove-launcher-entry stdout
printf '%s\n' '[Desktop Entry]' > "$home/.local/share/applications/org.example.Restore.desktop"
if TEST_DESKTOP_DATABASE_FAIL_ONCE=1 XDG_DATA_HOME="$home/.local/share" HOME="$home" PATH="$bin:$PATH" \
  run_adapter omarchy-remove-launcher-entry org.example.Restore 'Restore me' 2>"$test_root/error"; then
  printf '%s\n' 'launcher database failure unexpectedly succeeded' >&2
  exit 1
fi
test -f "$home/.local/share/applications/org.example.Restore.desktop"
grep -q 'launcher entry was restored' "$test_root/error"
record_case omarchy-remove-launcher-entry backendFailure
printf '%s\n' '[Desktop Entry]' > "$home/.local/share/applications/org.example.Rollback.desktop"
if TEST_DESKTOP_DATABASE_FAIL=1 XDG_DATA_HOME="$home/.local/share" HOME="$home" PATH="$bin:$PATH" \
  run_adapter omarchy-remove-launcher-entry org.example.Rollback 'Rollback me' 2>"$test_root/error"; then
  printf '%s\n' 'launcher rollback failure unexpectedly succeeded' >&2
  exit 1
fi
test -f "$home/.local/share/applications/org.example.Rollback.desktop"
grep -q 'rollback failed' "$test_root/error"
ln -s "$home/.local/share/applications/org.example.Restore.desktop" \
  "$home/.local/share/applications/org.example.Link.desktop"
if XDG_DATA_HOME="$home/.local/share" HOME="$home" PATH="$bin:$PATH" \
  run_adapter omarchy-remove-launcher-entry org.example.Link 'Link me' 2>"$test_root/error"; then
  printf '%s\n' 'symlink launcher entry unexpectedly succeeded' >&2
  exit 1
fi
grep -q 'launcher entry is a symlink' "$test_root/error"
if XDG_DATA_HOME="$home/.local/share" HOME="$home" PATH="$bin:$PATH" \
  run_adapter omarchy-remove-launcher-entry ../outside 'Invalid' 2>"$test_root/error"; then
  printf '%s\n' 'path traversal launcher ID unexpectedly succeeded' >&2
  exit 1
fi
grep -q 'Desktop ID is invalid' "$test_root/error"
outside_applications="$test_root/outside-applications"
mkdir -p "$outside_applications"
printf '%s\n' '[Desktop Entry]' > "$outside_applications/org.example.Outside.desktop"
mv "$home/.local/share/applications" "$home/.local/share/applications-real"
ln -s "$outside_applications" "$home/.local/share/applications"
if XDG_DATA_HOME="$home/.local/share" HOME="$home" PATH="$bin:$PATH" \
  run_adapter omarchy-remove-launcher-entry org.example.Outside 'Outside' 2>"$test_root/error"; then
  printf '%s\n' 'symlinked launcher directory unexpectedly succeeded' >&2
  exit 1
fi
grep -q 'user launcher directory is a symlink' "$test_root/error"
test -f "$outside_applications/org.example.Outside.desktop"
rm "$home/.local/share/applications"
mv "$home/.local/share/applications-real" "$home/.local/share/applications"
if XDG_DATA_HOME="$home/.local/share" HOME="$home" PATH="$bin:$PATH" \
  run_adapter omarchy-remove-launcher-entry org.example.System 'System app' 2>"$test_root/error"; then
  printf '%s\n' 'non-removable system launcher unexpectedly succeeded' >&2
  exit 1
fi
grep -q 'Could not find user launcher entry' "$test_root/error"

cat > "$bin/brightnessctl" <<EOF
#!/usr/bin/env bash
[[ \${TEST_BRIGHTNESS_FAIL:-} == 1 ]] && exit 1
if [[ \$1 == -m ]]; then
  printf 'backlight,sysfs/brightness,100,42%%,42%%\n'
else
  printf 'brightnessctl %s\n' "\$*" >> "$log"
fi
EOF
chmod +x "$bin/brightnessctl"
sed -i "1c#!$(command -v bash)" "$bin/brightnessctl"
link_adapter omarchy-brightness-display
HOME="$home" PATH="$bin:$PATH" run_adapter omarchy-brightness-display --no-osd --monitor eDP-1 50%
grep -q '^brightnessctl set 50%$' "$log"
record_case omarchy-brightness-display valid
record_case omarchy-brightness-display stdout
if HOME="$home" PATH="$bin:$PATH" run_adapter omarchy-brightness-display --monitor DP-1 50% 2>"$test_root/error"; then
  printf '%s\n' 'external brightness unexpectedly succeeded' >&2
  exit 1
fi
grep -q 'external-display brightness is unavailable' "$test_root/error"
if TEST_BRIGHTNESS_FAIL=1 HOME="$home" PATH="$bin:$PATH" \
  run_adapter omarchy-brightness-display --no-osd 50% 2>"$test_root/error"; then
  printf '%s\n' 'brightness backend failure unexpectedly succeeded' >&2
  exit 1
fi
grep -q 'brightness backend failed' "$test_root/error"
record_case omarchy-brightness-display backendFailure

cat > "$bin/nmcli" <<'EOF'
#!/usr/bin/env bash
[[ ${LC_ALL:-} == C ]] || exit 99
[[ ${TEST_NMCLI_FAIL:-} == all ]] && exit 1
state=${TEST_NMCLI_STATE:-}
[[ ${TEST_NMCLI_TIMEOUT:-} == 1 ]] && sleep 5
if [[ $* == *GENERAL.CON-UUID* ]]; then
  printf '%s\n' uuid-1
elif [[ $* == *802-11-wireless-security.key-mgmt* && $* != *802-11-wireless.ssid* ]]; then
  printf '%s\n' 'wpa-psk' 's e;cret' ''
elif [[ $1 == -t && $* == *'DEVICE,TYPE,STATE device status'* ]]; then
  printf '%s\n' 'fixture0:wifi:connected'
elif [[ $* == *'GENERAL.CONNECTION device show'* ]]; then
  printf '%s\n' fixture-profile
elif [[ $* == *'GENERAL.STATE device show'* ]]; then
  printf '%s\n' 'GENERAL.STATE:100 (connected)'
elif [[ $* == *'IN-USE,SIGNAL device wifi list'* ]]; then
  printf '%s\n' '*:75'
elif [[ $* == *'FREQ,SSID device wifi list'* ]]; then
  [[ ${TEST_NMCLI_SCAN_FAIL:-} == 1 ]] && exit 1
  printf '%s\n' '2412:My;Wi,Fi:Zone' '5180:My;Wi,Fi:Zone'
elif [[ $* == *'connection show --active'* ]]; then
  printf '%s\n' 'fixture:profile:802-11-wireless'
elif [[ $* == *'802-11-wireless.band connection show'* ]]; then
  sed -n '1p' "$state"
elif [[ $* == *'ipv4.ignore-auto-dns connection show'* ]]; then
  sed -n '2p' "$state"
elif [[ $* == *'ipv4.dns connection show'* ]]; then
  value=$(sed -n '3p' "$state")
  [[ $value == none ]] || printf '%s\n' "$value"
elif [[ $1 == connection && $2 == modify ]]; then
  [[ ${TEST_NMCLI_FAIL:-} != modify ]] || exit 1
  if [[ $4 == 802-11-wireless.band ]]; then
    [[ ${TEST_NMCLI_ROLLBACK_FAIL:-} != 1 || $5 != auto ]] || exit 1
    if [[ -n $5 ]]; then sed -i "1c$5" "$state"; else sed -i '1c\\' "$state"; fi
  else
    [[ ${TEST_NMCLI_ROLLBACK_FAIL:-} != 1 || $5 != no ]] || exit 1
    sed -i "2c$5" "$state"
    value=${7:-none}
    sed -i "3c\\$value" "$state"
  fi
elif [[ $1 == connection && $2 == up ]]; then
  count=$(sed -n '4p' "$state")
  count=$((count + 1))
  sed -i "4c$count" "$state"
  if [[ ${TEST_NMCLI_ACTIVATE_FAIL:-} == 1 && $count == 1 ]]; then exit 1; fi
else
  if [[ ${TEST_NMCLI_SPECIAL:-} == 1 ]]; then
    printf '%s\n' 'Quoted " Wi-Fi' 'wpa-psk' 'pass"word' 'no' ''
  else
    printf '%s\n' 'My;Wi,Fi:Zone' 'wpa-psk' 's e;cret' 'no' ''
  fi
fi
EOF
cat > "$bin/qrencode" <<'EOF'
#!/usr/bin/env bash
cat > "$TEST_QR_PAYLOAD"
printf '##\n  #\n'
EOF
chmod +x "$bin/nmcli" "$bin/qrencode"
sed -i "1c#!$(command -v bash)" "$bin/nmcli" "$bin/qrencode"
link_adapter omarchy-network-qr
TEST_QR_PAYLOAD="$test_root/qr-payload" HOME="$home" PATH="$bin:$PATH" \
  run_adapter omarchy-network-qr --meta wlan0 > "$test_root/qr"
grep -Fqx $'meta\twlan0\tWPA\tMy;Wi,Fi:Zone' "$test_root/qr"
grep -Fqx '1' "$test_root/qr"
grep -Fqx 'WIFI:T:WPA;S:My\;Wi\,Fi\:Zone;P:s e\;cret;;' "$test_root/qr-payload"
record_case omarchy-network-qr valid
record_case omarchy-network-qr stdout
TEST_NMCLI_SPECIAL=1 TEST_QR_PAYLOAD="$test_root/qr-special-payload" HOME="$home" PATH="$bin:$PATH" \
  run_adapter omarchy-network-qr --meta wlan0 >/dev/null
grep -Fqx 'WIFI:T:WPA;S:Quoted \" Wi-Fi;P:pass\"word;;' "$test_root/qr-special-payload"
link_adapter omarchy-network-password
HOME="$home" PATH="$bin:$PATH" run_adapter omarchy-network-password wlan0 > "$test_root/password"
grep -Fqx 's e;cret' "$test_root/password"
record_case omarchy-network-password valid
record_case omarchy-network-password stdout
if HOME="$home" PATH="$bin:$PATH" run_adapter omarchy-network-password 2>"$test_root/error"; then
  printf '%s\n' 'invalid network password arguments unexpectedly succeeded' >&2
  exit 1
fi
grep -q 'Usage: omarchy-network-password' "$test_root/error"

cat > "$bin/ip" <<'EOF'
#!/usr/bin/env bash
[[ ${TEST_IP_FAIL:-} == 1 ]] && exit 1
[[ ${TEST_IP_TIMEOUT:-} == 1 ]] && sleep 5
[[ ${TEST_IP_NO_ROUTE:-} == 1 ]] && exit 2
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
link_adapter omarchy-network-status
HOME="$home" PATH="$bin:$PATH" run_adapter omarchy-network-status --verbose > "$test_root/network"
grep -Fqx -- $'iface\tfixture0' "$test_root/network"
grep -Fqx -- $'type\tethernet' "$test_root/network"
record_case omarchy-network-status valid
record_case omarchy-network-status stdout
if TEST_IP_TIMEOUT=1 HOME="$home" PATH="$bin:$PATH" run_adapter omarchy-network-status 2>"$test_root/error"; then
  printf '%s\n' 'timed-out network route lookup unexpectedly succeeded' >&2
  exit 1
fi
grep -q 'route lookup timed out' "$test_root/error"
TEST_IP_NO_ROUTE=1 HOME="$home" PATH="$bin:$PATH" run_adapter omarchy-network-status >"$test_root/disconnected"
grep -Fqx -- $'disconnected\t\t\t' "$test_root/disconnected"
link_adapter omarchy-network-band
if HOME="$home" PATH="$bin:$PATH" run_adapter omarchy-network-band invalid extra 2>"$test_root/error"; then
  printf '%s\n' 'invalid network band arguments unexpectedly succeeded' >&2
  exit 1
fi
grep -q 'Usage: omarchy-network-band' "$test_root/error"
link_adapter omarchy-dns
if HOME="$home" PATH="$bin:$PATH" run_adapter omarchy-dns Invalid extra 2>"$test_root/error"; then
  printf '%s\n' 'invalid DNS arguments unexpectedly succeeded' >&2
  exit 1
fi
grep -q 'Usage: omarchy-dns' "$test_root/error"

cat > "$bin/iw" <<'EOF'
#!/usr/bin/env bash
if [[ $* == 'dev fixture0 link' ]]; then
  frequency=5180
  [[ ${TEST_IW_WRONG_BAND:-} == 1 ]] && frequency=2412
  printf '%s\n' 'SSID: My;Wi,Fi:Zone' "freq: $frequency"
fi
EOF
chmod +x "$bin/iw"
sed -i "1c#!$(command -v bash)" "$bin/iw"
printf '%s\n' auto no none 0 > "$test_root/nmcli-state"
TEST_NMCLI_STATE="$test_root/nmcli-state" HOME="$home" PATH="$bin:$PATH" \
  run_adapter omarchy-network-band > "$test_root/band"
grep -Fqx $'band\t5' "$test_root/band"
grep -Fqx $'available\t2.4 5' "$test_root/band"
record_case omarchy-network-band valid
record_case omarchy-network-band stdout
mv "$bin/iw" "$bin/iw.disabled"
printf '%s\n' a no none 0 > "$test_root/nmcli-state"
TEST_NMCLI_STATE="$test_root/nmcli-state" HOME="$home" PATH="$bin:$PATH" \
run_adapter omarchy-network-band auto
test -z "$(sed -n '1p' "$test_root/nmcli-state")"
mv "$bin/iw.disabled" "$bin/iw"
TEST_NMCLI_STATE="$test_root/nmcli-state" HOME="$home" PATH="$bin:$PATH" \
run_adapter omarchy-network-band 5
grep -Fqx a "$test_root/nmcli-state"
printf '%s\n' auto no none 0 > "$test_root/nmcli-state"
if TEST_NMCLI_STATE="$test_root/nmcli-state" TEST_IW_WRONG_BAND=1 HOME="$home" PATH="$bin:$PATH" \
  run_adapter omarchy-network-band 5 2>"$test_root/error"; then
  printf '%s\n' 'wrong active Wi-Fi band unexpectedly succeeded' >&2
  exit 1
fi
grep -Fqx auto "$test_root/nmcli-state"
grep -q 'reached 2.4 instead of 5' "$test_root/error"
if TEST_NMCLI_STATE="$test_root/nmcli-state" HOME="$home" PATH="$bin:$PATH" \
  run_adapter omarchy-network-band 6 2>"$test_root/error"; then
  printf '%s\n' 'unavailable network band unexpectedly succeeded' >&2
  exit 1
fi
grep -Fqx auto "$test_root/nmcli-state"
printf '%s\n' auto no none 0 > "$test_root/nmcli-state"
if TEST_NMCLI_STATE="$test_root/nmcli-state" TEST_NMCLI_ACTIVATE_FAIL=1 \
  HOME="$home" PATH="$bin:$PATH" run_adapter omarchy-network-band 5 2>"$test_root/error"; then
  printf '%s\n' 'network band activation failure unexpectedly succeeded' >&2
  exit 1
fi
grep -Fqx auto "$test_root/nmcli-state"
grep -q 'previous band was restored' "$test_root/error"
printf '%s\n' auto no none 0 > "$test_root/nmcli-state"
if TEST_NMCLI_STATE="$test_root/nmcli-state" TEST_NMCLI_ACTIVATE_FAIL=1 TEST_NMCLI_ROLLBACK_FAIL=1 \
  HOME="$home" PATH="$bin:$PATH" run_adapter omarchy-network-band 5 2>"$test_root/error"; then
  printf '%s\n' 'network band rollback failure unexpectedly succeeded' >&2
  exit 1
fi
grep -Fqx a "$test_root/nmcli-state"
grep -q 'rollback failed' "$test_root/error"
printf '%s\n' auto no none 0 > "$test_root/nmcli-state"
if TEST_NMCLI_STATE="$test_root/nmcli-state" TEST_NMCLI_SCAN_FAIL=1 \
  HOME="$home" PATH="$bin:$PATH" run_adapter omarchy-network-band 5 2>"$test_root/error"; then
  printf '%s\n' 'NetworkManager scan failure unexpectedly succeeded' >&2
  exit 1
fi
grep -q 'available Wi-Fi bands could not be determined' "$test_root/error"
printf '%s\n' auto no none 0 > "$test_root/nmcli-state"
if TEST_NMCLI_STATE="$test_root/nmcli-state" TEST_NMCLI_FAIL=modify \
  HOME="$home" PATH="$bin:$PATH" run_adapter omarchy-network-band 5 2>"$test_root/error"; then
  printf '%s\n' 'NetworkManager band mutation failure unexpectedly succeeded' >&2
  exit 1
fi
grep -Fqx auto "$test_root/nmcli-state"
grep -q 'profile was not changed' "$test_root/error"
TEST_NMCLI_STATE="$test_root/nmcli-state" HOME="$home" PATH="$bin:$PATH" \
  run_adapter omarchy-dns > "$test_root/dns"
grep -Fqx DHCP "$test_root/dns"
record_case omarchy-dns valid
record_case omarchy-dns stdout
network_status_failure_status=0
if TEST_IP_FAIL=1 HOME="$home" PATH="$bin:$PATH" run_adapter omarchy-network-status 2>"$test_root/error"; then
  printf '%s\n' 'network status backend failure unexpectedly succeeded' >&2
  exit 1
else
  network_status_failure_status=$?
fi
test "$network_status_failure_status" -eq 1
record_case omarchy-network-status backendFailure
if TEST_NMCLI_FAIL=all HOME="$home" PATH="$bin:$PATH" run_adapter omarchy-network-password wlan0 2>"$test_root/error"; then
  printf '%s\n' 'network password backend failure unexpectedly succeeded' >&2
  exit 1
fi
grep -q 'connection lookup failed' "$test_root/error"
record_case omarchy-network-password backendFailure
if TEST_NMCLI_FAIL=all HOME="$home" PATH="$bin:$PATH" run_adapter omarchy-network-qr wlan0 2>"$test_root/error"; then
  printf '%s\n' 'network QR backend failure unexpectedly succeeded' >&2
  exit 1
fi
grep -q 'connection lookup failed' "$test_root/error"
record_case omarchy-network-qr backendFailure
if TEST_NMCLI_FAIL=all TEST_NMCLI_STATE="$test_root/nmcli-state" HOME="$home" PATH="$bin:$PATH" \
  run_adapter omarchy-network-band 5 2>"$test_root/error"; then
  printf '%s\n' 'network band backend failure unexpectedly succeeded' >&2
  exit 1
fi
grep -q 'device lookup failed' "$test_root/error"
record_case omarchy-network-band backendFailure
if TEST_NMCLI_FAIL=all TEST_NMCLI_STATE="$test_root/nmcli-state" HOME="$home" PATH="$bin:$PATH" \
  run_adapter omarchy-dns Google 2>"$test_root/error"; then
  printf '%s\n' 'DNS backend failure unexpectedly succeeded' >&2
  exit 1
fi
grep -q 'active NetworkManager connection lookup failed' "$test_root/error"
record_case omarchy-dns backendFailure
TEST_NMCLI_STATE="$test_root/nmcli-state" HOME="$home" PATH="$bin:$PATH" \
  run_adapter omarchy-dns Cloudflare
grep -Fqx yes "$test_root/nmcli-state" && grep -Fqx '1.1.1.1,1.0.0.1' <(sed -n '3p' "$test_root/nmcli-state")
printf '%s\n' auto no none 0 > "$test_root/nmcli-state"
if TEST_NMCLI_STATE="$test_root/nmcli-state" TEST_NMCLI_ACTIVATE_FAIL=1 \
  HOME="$home" PATH="$bin:$PATH" run_adapter omarchy-dns Google 2>"$test_root/error"; then
  printf '%s\n' 'DNS activation failure unexpectedly succeeded' >&2
  exit 1
fi
grep -Fqx no <(sed -n '2p' "$test_root/nmcli-state")
grep -q 'previous settings were restored' "$test_root/error"
printf '%s\n' auto no '' 0 > "$test_root/nmcli-state"
if TEST_NMCLI_STATE="$test_root/nmcli-state" TEST_NMCLI_ACTIVATE_FAIL=1 TEST_NMCLI_ROLLBACK_FAIL=1 \
  HOME="$home" PATH="$bin:$PATH" run_adapter omarchy-dns Google 2>"$test_root/error"; then
  printf '%s\n' 'DNS rollback failure unexpectedly succeeded' >&2
  exit 1
fi
grep -Fqx yes <(sed -n '2p' "$test_root/nmcli-state")
grep -q 'rollback failed' "$test_root/error"
printf '%s\n' auto no none 0 > "$test_root/nmcli-state"
if TEST_NMCLI_STATE="$test_root/nmcli-state" TEST_NMCLI_FAIL=modify \
  HOME="$home" PATH="$bin:$PATH" run_adapter omarchy-dns Google 2>"$test_root/error"; then
  printf '%s\n' 'NetworkManager DNS mutation failure unexpectedly succeeded' >&2
  exit 1
fi
grep -Fqx no <(sed -n '2p' "$test_root/nmcli-state")
grep -q 'profile was not changed' "$test_root/error"

cat > "$bin/bluetoothctl" <<EOF
#!/usr/bin/env bash
[[ \${TEST_BLUETOOTH_TIMEOUT:-} == 1 ]] && sleep 5
[[ \${TEST_BLUETOOTH_FAIL:-} == "\$1" ]] && exit 1
if [[ \$1 == list ]]; then
  printf '%s\n' 'Controller 00:11:22:33:44:55 fixture'
elif [[ \$1 == show ]]; then
  printf '%s\n' 'Powered: yes'
fi
printf '%s\n' "\$*" >> "$log"
EOF
cat > "$bin/rfkill" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$TEST_RFKILL"
EOF
chmod +x "$bin/bluetoothctl" "$bin/rfkill"
sed -i "1c#!$(command -v bash)" "$bin/bluetoothctl" "$bin/rfkill"
link_adapter omarchy-bluetooth-device
link_adapter omarchy-bluetooth-power
if HOME="$home" PATH="$bin:$PATH" run_adapter omarchy-bluetooth-device disconnect not-a-mac 2>"$test_root/error"; then
  printf '%s\n' 'malformed Bluetooth address unexpectedly succeeded' >&2
  exit 1
fi
grep -q 'Bluetooth address is invalid' "$test_root/error"
HOME="$home" PATH="$bin:$PATH" run_adapter omarchy-bluetooth-device disconnect 00:11:22:33:44:55
TEST_RFKILL="$test_root/rfkill" HOME="$home" PATH="$bin:$PATH" \
  run_adapter omarchy-bluetooth-power off
HOME="$home" PATH="$bin:$PATH" run_adapter omarchy-bluetooth-power is-on
grep -q '^disconnect 00:11:22:33:44:55$' "$log"
record_case omarchy-bluetooth-device valid
record_case omarchy-bluetooth-device stdout
grep -Fqx 'block bluetooth' "$test_root/rfkill"
record_case omarchy-bluetooth-power valid
record_case omarchy-bluetooth-power stdout
if TEST_BLUETOOTH_FAIL=pair TEST_RFKILL="$test_root/rfkill" HOME="$home" PATH="$bin:$PATH" \
  run_adapter omarchy-bluetooth-device pair 00:11:22:33:44:55 2>"$test_root/error"; then
  printf '%s\n' 'failed Bluetooth pairing unexpectedly succeeded' >&2
  exit 1
fi
if ! grep -q 'Bluetooth operation failed' "$test_root/error"; then
  cat "$test_root/error" >&2
  exit 1
fi
record_case omarchy-bluetooth-device backendFailure
if TEST_BLUETOOTH_TIMEOUT=1 HOME="$home" PATH="$bin:$PATH" \
  run_adapter omarchy-bluetooth-power is-on 2>"$test_root/error"; then
  printf '%s\n' 'timed-out Bluetooth lookup unexpectedly succeeded' >&2
  exit 1
fi
grep -q 'Bluetooth controller lookup timed out' "$test_root/error"
record_case omarchy-bluetooth-power backendFailure

link_adapter omarchy-system-stats
printf '%s\n' 'MemTotal:       8388608 kB' 'MemAvailable:   4194304 kB' > "$test_root/meminfo"
printf '%s\n' 'cpu 100 0 0 100 0 0 0 0 0 0' > "$test_root/stat-before"
printf '%s\n' 'cpu 150 0 0 150 0 0 0 0 0 0' > "$test_root/stat-after"
printf '%s\n' '0.42 0.50 0.75 1/100 12345' > "$test_root/loadavg"
OMARCHY_PROC_MEMINFO="$test_root/meminfo" \
  OMARCHY_PROC_STAT_BEFORE="$test_root/stat-before" \
  OMARCHY_PROC_STAT_AFTER="$test_root/stat-after" \
  OMARCHY_PROC_LOADAVG="$test_root/loadavg" \
  HOME="$home" PATH="$bin:$PATH" run_adapter omarchy-system-stats > "$test_root/system-stats"
grep -Fqx $'cpu\t50%' "$test_root/system-stats"
grep -Fqx $'memory\t4.0GiB / 8GiB' "$test_root/system-stats"
grep -Fqx $'load\t0.42' "$test_root/system-stats"
record_case omarchy-system-stats valid
record_case omarchy-system-stats stdout
if OMARCHY_PROC_MEMINFO="$test_root/meminfo" \
  OMARCHY_PROC_STAT_BEFORE="$test_root/stat-before" \
  OMARCHY_PROC_LOADAVG="$test_root/loadavg" \
  OMARCHY_CPU_SAMPLE_INTERVAL=0 HOME="$home" PATH="$bin:$PATH" \
  run_adapter omarchy-system-stats > "$test_root/live-sampled-stats" 2>"$test_root/error"; then
  printf '%s\n' 'live CPU sampling fabricated a result from a fixture baseline' >&2
  cat "$test_root/live-sampled-stats" >&2
  exit 1
fi
grep -Fq 'CPU statistics are invalid' "$test_root/error"
record_case omarchy-system-stats backendFailure
if OMARCHY_PROC_MEMINFO="$test_root/meminfo" \
  OMARCHY_PROC_STAT_BEFORE="$test_root/stat-before" \
  OMARCHY_PROC_LOADAVG="$test_root/loadavg" \
  OMARCHY_CPU_SAMPLE_INTERVAL=invalid HOME="$home" PATH="$bin:$PATH" \
  run_adapter omarchy-system-stats 2>"$test_root/error"; then
  printf '%s\n' 'invalid CPU sample interval unexpectedly succeeded' >&2
  exit 1
fi
grep -q 'CPU sample interval must be a number' "$test_root/error"
cat > "$bin/gsettings" <<'EOF'
#!/usr/bin/env bash
[[ ${TEST_GSETTINGS_FAIL:-} == 1 ]] && exit 1
case "$1 $2 $3" in
  'get org.gnome.desktop.interface text-scaling-factor') printf '%s\n' '1.0' ;;
  'get org.gnome.desktop.interface font-name') printf '%s\n' "'Cantarell 11'" ;;
  'set org.gnome.desktop.interface text-scaling-factor') [[ ${TEST_GSETTINGS_SET_FAIL:-} != 1 ]] && printf '%s\n' "$*" >> "$TEST_GSETTINGS_LOG" || exit 1 ;;
  'reset org.gnome.desktop.interface text-scaling-factor') [[ ${TEST_GSETTINGS_SET_FAIL:-} != 1 ]] && printf '%s\n' "$*" >> "$TEST_GSETTINGS_LOG" || exit 1 ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$bin/gsettings"
sed -i "1c#!$(command -v bash)" "$bin/gsettings"
export TEST_GSETTINGS_LOG="$test_root/gsettings"
link_adapter omarchy-display-text-size
HOME="$home" PATH="$bin:$PATH" run_adapter omarchy-display-text-size --help | grep -Fqx -- 'Usage: omarchy-display-text-size [size|reset]'
PATH="$bin:$bash_dir" HOME="$home" run_adapter omarchy-display-text-size --help | grep -Fqx -- 'Usage: omarchy-display-text-size [size|reset]'
text_size_invalid_status=0
if HOME="$home" PATH="$bin:$PATH" run_adapter omarchy-display-text-size 8 2>"$test_root/error"; then
  printf '%s\n' 'invalid text size unexpectedly succeeded' >&2
  exit 1
else
  text_size_invalid_status=$?
fi
test "$text_size_invalid_status" -eq 2
grep -Fq 'Text size must be an integer between 9 and 20' "$test_root/error"
record_case omarchy-display-text-size invalidArgs
HOME="$home" PATH="$bin:$PATH" run_adapter omarchy-display-text-size 14
grep -Fqx -- 'base-size = 14' "$home/.config/omarchy/shell.toml"
record_case omarchy-display-text-size valid
record_case omarchy-display-text-size stdout
mkdir -p "$home/.config/ghostty"
printf '%s\n' 'font-size = 9' > "$home/.config/ghostty/config"
mkdir -p "$home/.config/alacritty" "$home/.config/kitty"
printf '%s\n' 'size = 9' > "$home/.config/alacritty/alacritty.toml"
printf '%s\n' 'font_size 9.0' > "$home/.config/kitty/kitty.conf"
cat > "$home/.config/omarchy/shell.toml" <<'EOF'
[font] # preserve this comment
base-size = 11
[bar]
background = "background"
EOF
HOME="$home" PATH="$bin:$PATH" run_adapter omarchy-display-text-size 15
grep -Fqx -- '[font] # preserve this comment' "$home/.config/omarchy/shell.toml"
grep -Fqx -- 'base-size = 15' "$home/.config/omarchy/shell.toml"
grep -Fqx -- 'background = "background"' "$home/.config/omarchy/shell.toml"
grep -Fqx -- 'font-size = 11' "$home/.config/ghostty/config"
grep -Fqx -- 'size = 11' "$home/.config/alacritty/alacritty.toml"
grep -Fqx -- 'font_size 11.0' "$home/.config/kitty/kitty.conf"
grep -Fq -- 'set org.gnome.desktop.interface text-scaling-factor 1.2727' "$TEST_GSETTINGS_LOG"
HOME="$home" PATH="$bin:$PATH" run_adapter omarchy-display-text-size 12
grep -Fqx -- 'base-size = 12' "$home/.config/omarchy/shell.toml"
grep -Fqx -- 'font-size = 9' "$home/.config/ghostty/config"
grep -Fqx -- 'size = 9' "$home/.config/alacritty/alacritty.toml"
grep -Fqx -- 'font_size 9.0' "$home/.config/kitty/kitty.conf"
grep -Fq -- 'set org.gnome.desktop.interface text-scaling-factor 1.0000' "$TEST_GSETTINGS_LOG"
mkdir -p "$home/.config/foot"
printf '%s\n' ':size=9' > "$home/.config/foot/foot.ini"
cat > "$bin/pgrep" <<'EOF'
#!/usr/bin/env bash
[[ ${TEST_FOOT_RUNNING:-} == 1 && $1 == -x && $2 == foot ]]
EOF
chmod +x "$bin/pgrep"
sed -i "1c#!$(command -v bash)" "$bin/pgrep"
TEST_FOOT_RUNNING=1 HOME="$home" PATH="$bin:$PATH" run_adapter omarchy-display-text-size 14 >/dev/null
grep -Fqx -- ':size=11' "$home/.config/foot/foot.ini"
grep -Fq -- 'Restart Foot to apply the new terminal font size' "$test_root/notification"
HOME="$home" PATH="$bin:$PATH" run_adapter omarchy-display-text-size > "$test_root/text-size"
grep -Fqx -- 'text size: 14 px' "$test_root/text-size"
HOME="$home" PATH="$bin:$PATH" run_adapter omarchy-display-text-size reset
if grep -q '^base-size' "$home/.config/omarchy/shell.toml"; then
  printf '%s\n' 'text-size reset left shell override' >&2
  exit 1
fi
grep -Fqx -- 'font-size = 9' "$home/.config/ghostty/config"
grep -Fq -- 'reset org.gnome.desktop.interface text-scaling-factor' "$TEST_GSETTINGS_LOG"
HOME="$home" PATH="$bin:$PATH" run_adapter omarchy-display-text-size 15
HOME="$home" PATH="$bin:$PATH" run_adapter omarchy-display-text-size default
if grep -q '^base-size' "$home/.config/omarchy/shell.toml"; then
  printf '%s\n' 'text-size default left shell override' >&2
  exit 1
fi
grep -Fq -- 'reset org.gnome.desktop.interface text-scaling-factor' "$TEST_GSETTINGS_LOG"
printf '%s\n' 'not valid toml' > "$home/.config/omarchy/shell.toml"
cp "$home/.config/omarchy/shell.toml" "$test_root/malformed-shell.toml"
if HOME="$home" PATH="$bin:$PATH" run_adapter omarchy-display-text-size 16 2>"$test_root/error"; then
  printf '%s\n' 'malformed shell.toml unexpectedly succeeded' >&2
  exit 1
fi
cmp "$test_root/malformed-shell.toml" "$home/.config/omarchy/shell.toml"
grep -q 'shell.toml has malformed' "$test_root/error"
mv "$home/.config/omarchy/shell.toml" "$test_root/shell-target.toml"
ln -s "$test_root/shell-target.toml" "$home/.config/omarchy/shell.toml"
if HOME="$home" PATH="$bin:$PATH" run_adapter omarchy-display-text-size 16 2>"$test_root/error"; then
  printf '%s\n' 'symlinked shell.toml unexpectedly succeeded' >&2
  exit 1
fi
grep -q 'shell.toml is not a regular file or is a symlink' "$test_root/error"
rm "$home/.config/omarchy/shell.toml"
mv "$test_root/shell-target.toml" "$home/.config/omarchy/shell.toml"
printf '%s\n' '[font]' 'base-size = 15' > "$home/.config/omarchy/shell.toml"
if TEST_GSETTINGS_FAIL=1 HOME="$home" PATH="$bin:$PATH" run_adapter omarchy-display-text-size 16 2>"$test_root/error"; then
  printf '%s\n' 'GTK failure unexpectedly succeeded' >&2
  exit 1
fi
grep -q 'GTK text-size lookup failed' "$test_root/error"
grep -Fqx -- 'base-size = 15' "$home/.config/omarchy/shell.toml"
record_case omarchy-display-text-size backendFailure
if TEST_GSETTINGS_SET_FAIL=1 HOME="$home" PATH="$bin:$PATH" run_adapter omarchy-display-text-size 16 2>"$test_root/error"; then
  printf '%s\n' 'GTK update failure unexpectedly succeeded' >&2
  exit 1
fi
grep -q 'GTK text-size update failed' "$test_root/error"
grep -Fqx -- 'base-size = 15' "$home/.config/omarchy/shell.toml"

cat > "$bin/hyprctl" <<'EOF'
#!/usr/bin/env bash
[[ ${TEST_HYPRCTL_FAIL:-} == 1 ]] && exit 1
if [[ $* == 'monitors all -j' || $* == 'monitors -j' ]]; then
  if [[ ${TEST_HYPRCTL_NO_FOCUS:-} == 1 ]]; then
    printf '%s\n' '[{"name":"eDP-1","focused":false,"disabled":false,"width":1920,"height":1080,"refreshRate":59.94,"scale":1.25,"mirrorOf":"none"}]'
  elif [[ ${TEST_HYPRCTL_MALFORMED:-} == 1 ]]; then
    printf '%s\n' '[{"name":"eDP-1","focused":true,"disabled":false,"width":1920,"height":1080,"scale":1.25,"mirrorOf":"none"}]'
  else
    printf '%s\n' '[{"name":"eDP-1","focused":true,"disabled":false,"width":1920,"height":1080,"refreshRate":59.94,"scale":1.25,"mirrorOf":"none"}]'
  fi
else
  if [[ $1 == getoption ]]; then
    printf '%s\n' '{"int":1}'
    exit 0
  fi
  if [[ ${TEST_HYPRCTL_FAIL_FIRST:-} == 1 && $1 == eval && ! -e ${HYPRCTL_LOG}.first-failed ]]; then
    : > "${HYPRCTL_LOG}.first-failed"
    exit 1
  fi
  if [[ ${TEST_HYPRCTL_FAIL_SECOND:-} == 1 && -s $HYPRCTL_LOG && $1 == eval ]]; then
    exit 1
  fi
  printf '%s\n' "$*" >> "$HYPRCTL_LOG"
fi
EOF
chmod +x "$bin/hyprctl"
sed -i "1c#!$(command -v bash)" "$bin/hyprctl"
HYPRCTL_LOG="$test_root/hyprctl" HOME="$home" PATH="$bin:$PATH" \
  run_adapter omarchy-brightness-display off
HYPRCTL_LOG="$test_root/hyprctl" HOME="$home" PATH="$bin:$PATH" \
  run_adapter omarchy-brightness-display on
grep -Fqx -- 'dispatch hl.dsp.dpms({ action = "disable" })' "$test_root/hyprctl"
grep -Fqx -- 'dispatch hl.dsp.dpms({ action = "enable" })' "$test_root/hyprctl"
link_adapter omarchy-monitor-state
link_adapter omarchy-hyprland-monitor-scaling
HYPRCTL_LOG="$test_root/hyprctl" HOME="$home" PATH="$bin:$PATH" \
  run_adapter omarchy-monitor-state > "$test_root/monitor"
head -n 1 "$test_root/monitor" | grep -Fqx -- '42'
record_case omarchy-monitor-state valid
record_case omarchy-monitor-state stdout
HYPRCTL_LOG="$test_root/hyprctl" HOME="$home" PATH="$bin:$PATH" \
  run_adapter omarchy-hyprland-monitor-scaling > "$test_root/scaling"
grep -Fqx -- '1.25' "$test_root/scaling"
record_case omarchy-hyprland-monitor-scaling valid
record_case omarchy-hyprland-monitor-scaling stdout
HYPRCTL_LOG="$test_root/hyprctl" HOME="$home" PATH="$bin:$PATH" \
  run_adapter omarchy-hyprland-monitor-scaling up
grep -Fqx -- 'eval hl.monitor({ output = "eDP-1", mode = "1920x1080@59.94", position = "auto", scale = 1.6 })' "$test_root/hyprctl"
HYPRCTL_LOG="$test_root/hyprctl" HOME="$home" PATH="$bin:$PATH" \
  run_adapter omarchy-hyprland-monitor-scaling 1.3
grep -Fqx -- 'eval hl.monitor({ output = "eDP-1", mode = "1920x1080@59.94", position = "auto", scale = 1.33333 })' "$test_root/hyprctl"
mkdir -p "$home/.config/hypr"
cat > "$home/.config/hypr/monitors.lua" <<'EOF'
local omarchy_monitor_scale = 1.25
local omarchy_gdk_scale = 1
local unrelated = "preserve me"
EOF
HYPRCTL_LOG="$test_root/hyprctl" HOME="$home" PATH="$bin:$PATH" \
  run_adapter omarchy-hyprland-monitor-scaling 2
grep -Fqx -- 'local omarchy_monitor_scale = 2' "$home/.config/hypr/monitors.lua"
grep -Fqx -- 'local omarchy_gdk_scale = 2' "$home/.config/hypr/monitors.lua"
grep -Fqx -- 'local unrelated = "preserve me"' "$home/.config/hypr/monitors.lua"
sed -n '8p' "$test_root/monitor" > "$test_root/monitor-entry"
jq -e 'type == "array" and .[0].name == "eDP-1"' "$test_root/monitor-entry" >/dev/null
chmod 500 "$home/.config/hypr"
if HYPRCTL_LOG="$test_root/hyprctl" HOME="$home" PATH="$bin:$PATH" \
  run_adapter omarchy-hyprland-monitor-scaling 2 2>"$test_root/error"; then
  printf '%s\n' 'monitor configuration failure unexpectedly succeeded' >&2
  exit 1
fi
chmod 700 "$home/.config/hypr"
grep -q 'previous live scale was restored' "$test_root/error"
grep -Fqx -- 'eval hl.monitor({ output = "eDP-1", mode = "1920x1080@59.94", position = "auto", scale = 1.25 })' "$test_root/hyprctl"
if TEST_HYPRCTL_FAIL_FIRST=1 HYPRCTL_LOG="$test_root/hyprctl-update-failure" HOME="$home" PATH="$bin:$PATH" \
  run_adapter omarchy-hyprland-monitor-scaling 2 2>"$test_root/error"; then
  printf '%s\n' 'monitor update failure unexpectedly succeeded' >&2
  exit 1
fi
grep -q 'previous live scale was restored' "$test_root/error"
grep -Fqx -- 'eval hl.monitor({ output = "eDP-1", mode = "1920x1080@59.94", position = "auto", scale = 1.25 })' \
  "$test_root/hyprctl-update-failure"
chmod 500 "$home/.config/hypr"
if TEST_HYPRCTL_FAIL_SECOND=1 HYPRCTL_LOG="$test_root/hyprctl-rollback" HOME="$home" PATH="$bin:$PATH" \
  run_adapter omarchy-hyprland-monitor-scaling 2 2>"$test_root/error"; then
  printf '%s\n' 'monitor rollback failure unexpectedly succeeded' >&2
  exit 1
fi
chmod 700 "$home/.config/hypr"
grep -q 'live-scale rollback failed' "$test_root/error"
if TEST_HYPRCTL_NO_FOCUS=1 HYPRCTL_LOG="$test_root/hyprctl-no-focus" HOME="$home" PATH="$bin:$PATH" \
  run_adapter omarchy-hyprland-monitor-scaling 2 2>"$test_root/error"; then
  printf '%s\n' 'missing focused monitor unexpectedly succeeded' >&2
  exit 1
fi
grep -q 'focused monitor is unavailable' "$test_root/error"
if TEST_HYPRCTL_MALFORMED=1 HYPRCTL_LOG="$test_root/hyprctl-malformed" HOME="$home" PATH="$bin:$PATH" \
  run_adapter omarchy-hyprland-monitor-scaling 2 2>"$test_root/error"; then
  printf '%s\n' 'malformed monitor state unexpectedly succeeded' >&2
  exit 1
fi
grep -q 'refresh rate is unavailable' "$test_root/error"
record_case omarchy-hyprland-monitor-scaling backendFailure
if TEST_HYPRCTL_FAIL=1 HYPRCTL_LOG="$test_root/hyprctl-monitor-failure" HOME="$home" PATH="$bin:$PATH" \
  run_adapter omarchy-monitor-state 2>"$test_root/error"; then
  printf '%s\n' 'monitor-state backend failure unexpectedly succeeded' >&2
  exit 1
fi
grep -q 'monitor state is unavailable' "$test_root/error"
record_case omarchy-monitor-state backendFailure

cat > "$bin/upower" <<'EOF'
#!/usr/bin/env bash
[[ ${TEST_UPOWER_FAIL:-} == 1 ]] && exit 1
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
link_adapter omarchy-battery-status
OMARCHY_POWER_SUPPLY_PATH="$test_root/power" HOME="$home" PATH="$bin:$PATH" \
  run_adapter omarchy-battery-status --shell > "$test_root/battery"
grep -Fqx $'percentage\t57%' "$test_root/battery"
grep -Fqx $'state\tcharging' "$test_root/battery"
grep -Fqx $'rate\t10W' "$test_root/battery"
grep -Fqx $'size\t48Wh' "$test_root/battery"
grep -Fqx $'time\t2h 30m' "$test_root/battery"
grep -Fqx $'cycles\t112' "$test_root/battery"
record_case omarchy-battery-status valid
record_case omarchy-battery-status stdout
if TEST_UPOWER_FAIL=1 OMARCHY_POWER_SUPPLY_PATH="$test_root/power" HOME="$home" PATH="$bin:$PATH" \
  run_adapter omarchy-battery-status --shell 2>"$test_root/error"; then
  printf '%s\n' 'UPower backend failure unexpectedly succeeded' >&2
  exit 1
fi
grep -q 'battery information is unavailable' "$test_root/error"
record_case omarchy-battery-status backendFailure
cat > "$bin/upower" <<'EOF'
#!/usr/bin/env bash
if [[ $1 == -e ]]; then
  printf '%s\n' '/org/freedesktop/UPower/devices/battery_BAT0'
else
  cat <<'BATTERY'
  native-path:          BAT0
  state:                discharging
  percentage:           57%
  energy-full:         48 Wh
  energy-rate:         12.3 W
  time to empty:        30 seconds
BATTERY
fi
EOF
chmod +x "$bin/upower"
sed -i "1c#!$(command -v bash)" "$bin/upower"
OMARCHY_POWER_SUPPLY_PATH="$test_root/power" HOME="$home" PATH="$bin:$PATH" \
  run_adapter omarchy-battery-status --shell > "$test_root/battery-seconds"
grep -Fqx $'time\tunknown' "$test_root/battery-seconds"
cat > "$bin/upower" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' '/org/freedesktop/UPower/devices/line_power_AC'
EOF
chmod +x "$bin/upower"
sed -i "1c#!$(command -v bash)" "$bin/upower"
HOME="$home" PATH="$bin:$PATH" run_adapter omarchy-battery-status --shell > "$test_root/no-battery"
test ! -s "$test_root/no-battery"
cat > "$bin/upower" <<'EOF'
#!/usr/bin/env bash
if [[ $1 == -e ]]; then
  printf '%s\n' '/org/freedesktop/UPower/devices/battery_BAT0'
else
  printf '%s\n' '  percentage: malformed'
fi
EOF
chmod +x "$bin/upower"
sed -i "1c#!$(command -v bash)" "$bin/upower"
if HOME="$home" PATH="$bin:$PATH" run_adapter omarchy-battery-status --shell 2>"$test_root/error"; then
  printf '%s\n' 'malformed battery data unexpectedly succeeded' >&2
  exit 1
fi
grep -q 'battery percentage is malformed' "$test_root/error"
record_case omarchy-battery-status backendFailure
cat > "$bin/upower" <<'EOF'
#!/usr/bin/env bash
if [[ $1 == -e ]]; then
  printf '%s\n' '/org/freedesktop/UPower/devices/battery_BAT0'
else
  printf '%s\n' '  native-path: BAT0' '  state: impossible' '  percentage: 57%' '  energy-full: 48 Wh'
fi
EOF
chmod +x "$bin/upower"
sed -i "1c#!$(command -v bash)" "$bin/upower"
if HOME="$home" PATH="$bin:$PATH" run_adapter omarchy-battery-status --shell 2>"$test_root/error"; then
  printf '%s\n' 'malformed battery state unexpectedly succeeded' >&2
  exit 1
fi
grep -q 'battery state is malformed' "$test_root/error"

cat > "$bin/powerprofilesctl" <<'EOF'
#!/usr/bin/env bash
if [[ $1 == list ]]; then
  [[ ${TEST_PROFILE_TIMEOUT:-} == 1 ]] && sleep 5
  cat <<'PROFILES'
  performance:
* balanced:
  power-saver:
PROFILES
elif [[ $1 == set ]]; then
  [[ ${TEST_PROFILE_FAIL:-} == 1 ]] && exit 1
  printf '%s\n' "$2" > "$TEST_PROFILE"
else
  exit 2
fi
EOF
chmod +x "$bin/powerprofilesctl"
sed -i "1c#!$(command -v bash)" "$bin/powerprofilesctl"
cat > "$bin/busctl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "${TEST_BATTERY_STATE:-b true}"
EOF
chmod +x "$bin/busctl"
sed -i "1c#!$(command -v bash)" "$bin/busctl"
link_adapter omarchy-powerprofiles-list
link_adapter omarchy-powerprofiles-set
HOME="$home" XDG_STATE_HOME="$home/.local/state" PATH="$bin:$PATH" \
  run_adapter omarchy-powerprofiles-list --active-state > "$test_root/profiles"
grep -Fqx $'performance\t0' "$test_root/profiles"
grep -Fqx $'balanced\t1' "$test_root/profiles"
grep -Fqx $'power-saver\t0' "$test_root/profiles"
record_case omarchy-powerprofiles-list valid
record_case omarchy-powerprofiles-list stdout
TEST_PROFILE="$test_root/profile" HOME="$home" XDG_STATE_HOME="$home/.local/state" PATH="$bin:$PATH" \
  run_adapter omarchy-powerprofiles-set ac performance
grep -Fqx performance "$test_root/profile"
grep -Fqx performance "$state/powerprofiles/ac"
record_case omarchy-powerprofiles-set valid
record_case omarchy-powerprofiles-set stdout
TEST_PROFILE="$test_root/profile" OMARCHY_POWERPROFILES_STATE_DIR="$test_root/profile-state" \
  HOME="$home" XDG_STATE_HOME="$home/.local/state" PATH="$bin:$PATH" \
  run_adapter omarchy-powerprofiles-set autodetect power-saver
grep -Fqx power-saver "$test_root/profile"
grep -Fqx power-saver "$test_root/profile-state/battery"
if TEST_BATTERY_STATE=malformed TEST_PROFILE="$test_root/profile" HOME="$home" XDG_STATE_HOME="$home/.local/state" PATH="$bin:$PATH" \
  run_adapter omarchy-powerprofiles-set autodetect 2>"$test_root/error"; then
  printf '%s\n' 'malformed battery state unexpectedly succeeded' >&2
  exit 1
fi
grep -q 'battery state backend returned malformed data' "$test_root/error"
if TEST_PROFILE="$test_root/profile" TEST_PROFILE_FAIL=1 HOME="$home" XDG_STATE_HOME="$home/.local/state" PATH="$bin:$PATH" \
  run_adapter omarchy-powerprofiles-set ac performance 2>"$test_root/error"; then
  printf '%s\n' 'power-profile backend failure unexpectedly succeeded' >&2
  exit 1
fi
grep -Fqx performance "$state/powerprofiles/ac"
record_case omarchy-powerprofiles-set backendFailure
printf '%s\n' blocked > "$test_root/blocked-state"
if TEST_PROFILE="$test_root/profile" OMARCHY_POWERPROFILES_STATE_DIR="$test_root/blocked-state" \
  HOME="$home" XDG_STATE_HOME="$home/.local/state" PATH="$bin:$PATH" \
  run_adapter omarchy-powerprofiles-set ac performance 2>"$test_root/error"; then
  printf '%s\n' 'power-profile state write failure unexpectedly succeeded' >&2
  exit 1
fi
grep -Fqx balanced "$test_root/profile"
grep -q 'previous profile was restored' "$test_root/error"
if TEST_PROFILE_TIMEOUT=1 HOME="$home" XDG_STATE_HOME="$home/.local/state" PATH="$bin:$PATH" \
  run_adapter omarchy-powerprofiles-list 2>"$test_root/error"; then
  printf '%s\n' 'power-profile timeout unexpectedly succeeded' >&2
  exit 1
fi
grep -q 'timed out' "$test_root/error"
record_case omarchy-powerprofiles-list backendFailure
printf '%s\n' auto no none 0 > "$test_root/nmcli-state"
if TEST_NMCLI_STATE="$test_root/nmcli-state" TEST_NMCLI_TIMEOUT=1 HOME="$home" PATH="$bin:$PATH" \
  run_adapter omarchy-network-band 2>"$test_root/error"; then
  printf '%s\n' 'NetworkManager timeout unexpectedly succeeded' >&2
  exit 1
fi
grep -q 'timed out' "$test_root/error"

missing_bin="$test_root/missing-bin"
mkdir -p "$missing_bin"
for utility in bash env timeout awk sed grep head sort tr jq mktemp cp rm mv chmod mkdir tac dirname; do
  ln -s "$(command -v "$utility")" "$missing_bin/$utility"
done
run_missing_backend() {
  local helper=$1 backend=$2 status=0
  shift 2
  if PATH="$missing_bin" HOME="$home" XDG_STATE_HOME="$home/.local/state" \
    XDG_CONFIG_HOME="$home/.config" XDG_DATA_HOME="$home/.local/share" \
    run_adapter "$helper" "$@" 2>"$test_root/error"; then
    printf '%s\n' "$helper succeeded without $backend" >&2
    exit 1
  else
    status=$?
  fi
  test "$status" -eq 127
  grep -Fq "required backend is unavailable: $backend" "$test_root/error"
  record_case "$helper" missingBackend
}

run_missing_backend omarchy-weather-status curl
run_missing_backend omarchy-audio-output-set-default wpctl 42 alsa_output.pci-1
run_missing_backend omarchy-audio-input-set-default wpctl 44 alsa_input.pci-1
run_missing_backend omarchy-audio-output-sink pactl
run_missing_backend omarchy-audio-sink-availability pw-dump
run_missing_backend omarchy-battery-status upower --shell
run_missing_backend omarchy-bluetooth-device bluetoothctl disconnect 00:11:22:33:44:55
run_missing_backend omarchy-bluetooth-power bluetoothctl is-on
run_missing_backend omarchy-brightness-display brightnessctl
run_missing_backend omarchy-capture-screenshot grim
run_missing_backend omarchy-clipboard-open xdg-open --history-index 0
run_missing_backend omarchy-clipboard-paste-file wl-copy --copy-only text/plain "$test_root/payload.txt"
run_missing_backend omarchy-clipboard-paste-text wl-copy --copy-only text
run_missing_backend omarchy-display-text-size gsettings 14
run_missing_backend omarchy-dns nmcli
run_missing_backend omarchy-hyprland-monitor-scaling hyprctl
run_missing_backend omarchy-menu-emoji-insert wl-copy "$emoji"
run_missing_backend omarchy-monitor-state hyprctl
run_missing_backend omarchy-network-band nmcli
run_missing_backend omarchy-network-password nmcli wlan0
run_missing_backend omarchy-network-qr nmcli --meta wlan0
run_missing_backend omarchy-network-status ip
run_missing_backend omarchy-notification-send notify-send Headline
run_missing_backend omarchy-powerprofiles-list powerprofilesctl
run_missing_backend omarchy-powerprofiles-set powerprofilesctl ac performance

weather_location_missing_status=0
if XDG_STATE_HOME="$test_root/no-weather-state" PATH="$missing_bin" HOME="$home" \
  XDG_CONFIG_HOME="$home/.config" XDG_DATA_HOME="$home/.local/share" \
  run_adapter omarchy-weather-location 2>"$test_root/error"; then
  printf '%s\n' 'omarchy-weather-location succeeded without curl' >&2
  exit 1
else
  weather_location_missing_status=$?
fi
test "$weather_location_missing_status" -eq 127
grep -Fq 'required backend is unavailable: curl' "$test_root/error"
record_case omarchy-weather-location missingBackend

printf '%s\n' '[Desktop Entry]' > "$home/.local/share/applications/org.example.MissingBackend.desktop"
run_missing_backend omarchy-remove-launcher-entry update-desktop-database org.example.MissingBackend Missing

run_invalid_args_status() {
  local helper=$1
  shift
  local status=0
  if HOME="$home" PATH="$bin:$PATH" run_adapter "$helper" "$@" 2>"$test_root/error"; then
    printf '%s\n' "$helper accepted invalid arguments" >&2
    exit 1
  else
    status=$?
  fi
  test "$status" -eq 2
  record_case "$helper" invalidArgs
  record_case "$helper" exitStatus
}

run_invalid_args_status omarchy-audio-input-set-default
run_invalid_args_status omarchy-audio-output-set-default --unexpected
run_invalid_args_status omarchy-audio-output-sink one two
run_invalid_args_status omarchy-audio-sink-availability unexpected
run_invalid_args_status omarchy-battery-status
run_invalid_args_status omarchy-bluetooth-device
run_invalid_args_status omarchy-bluetooth-power
run_invalid_args_status omarchy-brightness-display --monitor
run_invalid_args_status omarchy-capture-screenshot unsupported
run_invalid_args_status omarchy-clipboard-open unexpected
run_invalid_args_status omarchy-clipboard-paste-file unexpected
run_invalid_args_status omarchy-clipboard-paste-text one two
run_invalid_args_status omarchy-display-text-size 8
run_invalid_args_status omarchy-notification-send --urgency invalid Headline
run_invalid_args_status omarchy-dns one two
run_invalid_args_status omarchy-hyprland-monitor-scaling one two
run_invalid_args_status omarchy-menu-emoji-insert one two
run_invalid_args_status omarchy-monitor-state unexpected
run_invalid_args_status omarchy-network-band one two
run_invalid_args_status omarchy-network-password
run_invalid_args_status omarchy-network-qr one two three
run_invalid_args_status omarchy-network-status one two
run_invalid_args_status omarchy-powerprofiles-list one two
run_invalid_args_status omarchy-powerprofiles-set one two three
run_invalid_args_status omarchy-remove-launcher-entry one
run_invalid_args_status omarchy-system-stats unexpected
run_invalid_args_status omarchy-weather-location --unexpected
run_invalid_args_status omarchy-weather-status unexpected

sort -u "$case_log"

printf '%s\n' 'compat adapter tests passed'
