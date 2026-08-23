#!/usr/bin/env bash
set -euo pipefail

if [[ -n ${OMANIXY_PROBE_BACKEND_PATH:-} ]]; then
  PATH="$OMANIXY_PROBE_BACKEND_PATH:$PATH"
  export PATH
fi

compatibility_command=${COMPAT_ADAPTER_NAME:-${0##*/}}
if [[ -n ${OMANIXY_CONSUMER_MARKER:-} ]]; then
  compatibility_marker="$OMANIXY_CONSUMER_MARKER.$compatibility_command"
  # shellcheck disable=SC2154 # the EXIT trap assigns status before use.
  trap 'status=$?; if [[ $status == 0 ]]; then printf "%s\n" "$compatibility_command" > "$compatibility_marker"; fi; exit "$status"' EXIT
fi

case "$compatibility_command" in
  omarchy-shell) @IPC@ "$@" ;;
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
  omarchy-hyprland-session-locked) hyprland_session_locked "$@" ;;
  omarchy-lock-fingerprint-ready) lock_fingerprint_ready "$@" ;;
  omanixy-idle-state) idle_state "$@" ;;
  omanixy-notification-state) notification_state "$@" ;;
  *) fail "$compatibility_command: unsupported compatibility command" 127 ;;
esac
