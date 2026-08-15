# shellcheck disable=SC2154 # shared adapter state is initialized by common.bash.
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

pipewire_node_id_by_name() {
  local node_name=$1 media_class=$2
  pipewire_dump | jq -er --arg node_name "$node_name" --arg media_class "$media_class" '
    .[] |
    select(.type == "PipeWire:Interface:Node" and .info.props["node.name"] == $node_name and .info.props["media.class"] == $media_class) |
    .id
  '
}

pulse_streams() {
  local kind=$1
  timed 2 'PulseAudio stream listing' pactl list "$kind" | awk -v kind="$kind" '
    function emit() {
      if (id != "" && sink != "" && (kind != "sink-inputs" || (app != "" && app != "EasyEffects"))) print id "\t" sink
    }
    /^Sink Input #[0-9]+/ || /^Source Output #[0-9]+/ {
      emit()
      id=$0
      sub(/^[^#]*#/, "", id)
      sink=""
      app=""
    }
    /^[[:space:]]*Sink:[[:space:]]*[0-9]+/ || /^[[:space:]]*Source:[[:space:]]*[0-9]+/ {
      sink=$0
      sub(/^[^:]*:[[:space:]]*/, "", sink)
      sub(/[[:space:]].*$/, "", sink)
    }
    /application.name =/ {
      app=$0
      sub(/^.*application.name = "/, "", app)
      sub(/".*$/, "", app)
    }
    END { emit() }
  '
}

audio_restore_default() {
  local direction=$1 old_id=$2 old_name=$3
  local command
  if [[ $direction == output ]]; then
    command=(pactl set-default-sink "$old_name")
  else
    command=(pactl set-default-source "$old_name")
  fi
  local pulse_status=0
  timed 2 'PulseAudio default rollback' "${command[@]}" >/dev/null 2>&1 || pulse_status=1
  if [[ -n $old_id ]]; then
    timed 2 'PipeWire default rollback' wpctl set-default "$old_id" >/dev/null 2>&1 || pulse_status=1
  fi
  return "$pulse_status"
}

audio_restore_stream() {
  local direction=$1 stream_id=$2 stream_target=$3
  if [[ $direction == output ]]; then
    timed 2 'PulseAudio output-stream rollback' pactl move-sink-input "$stream_id" "$stream_target" >/dev/null 2>&1
  else
    timed 2 'PulseAudio input-stream rollback' pactl move-source-output "$stream_id" "$stream_target" >/dev/null 2>&1
  fi
}

audio_set_default() {
  local direction=$1 node_id=$2 node_name=$3
  local media_class pulse_kind default_command old_name old_id streams stream_id stream_sink moved=0 rollback_status
  if [[ $direction == output ]]; then
    media_class=Audio/Sink
    pulse_kind=sink-inputs
  else
    media_class=Audio/Source
    pulse_kind=source-outputs
  fi
  need wpctl
  need pw-dump
  need pactl
  [[ $node_id =~ ^[0-9]+$ && -n $node_name ]] || fail "Usage: omarchy-audio-${direction}-set-default <node-id> <node-name>" 2
  local resolved_name
  resolved_name=$(pipewire_node_name "$node_id" "$media_class") || fail "$name: ${direction} node is unavailable"
  [[ $resolved_name == "$node_name" ]] || fail "$name: ${direction} node name does not match PipeWire metadata"
  if [[ $direction == output ]]; then default_command=get-default-sink; else default_command=get-default-source; fi
  old_name=$(timed 2 'PulseAudio default inspection' pactl "$default_command" 2>/dev/null) ||
    fail "$name: current ${direction} is unavailable"
  old_id=$(pipewire_node_id_by_name "$old_name" "$media_class" 2>/dev/null || true)
  streams=$(pulse_streams "$pulse_kind") || fail "$name: active ${direction} streams are unavailable"
  [[ -n $old_id ]] || fail "$name: current ${direction} has no PipeWire identity for rollback"
  if [[ $direction == output ]]; then
    if ! timed 2 'PipeWire output selection' wpctl set-default "$node_id" ||
      ! timed 2 'PulseAudio output selection' pactl set-default-sink "$node_name"; then
      audio_restore_default "$direction" "$old_id" "$old_name" ||
        fail "$name: output selection failed and default rollback failed"
      fail "$name: output selection failed; previous default was restored"
    fi
  elif ! timed 2 'PipeWire input selection' wpctl set-default "$node_id" ||
    ! timed 2 'PulseAudio input selection' pactl set-default-source "$node_name"; then
    audio_restore_default "$direction" "$old_id" "$old_name" ||
      fail "$name: input selection failed and default rollback failed"
    fail "$name: input selection failed; previous default was restored"
  fi
  while IFS=$'\t' read -r stream_id stream_sink; do
    [[ -n $stream_id ]] || continue
    if [[ $direction == output ]]; then
      if ! timed 2 'application output migration' pactl move-sink-input "$stream_id" "$node_name"; then
        rollback_status=0
        audio_restore_stream output "$stream_id" "$stream_sink" || rollback_status=1
        ((moved == 0)) || while IFS=$'\t' read -r moved_id moved_sink; do
          [[ -n $moved_id ]] || continue
          audio_restore_stream output "$moved_id" "$moved_sink" || rollback_status=1
        done < <(printf '%s\n' "$streams" | head -n "$moved")
      else
        moved=$((moved + 1))
        continue
      fi
    else
      if ! timed 2 'application input migration' pactl move-source-output "$stream_id" "$node_name"; then
        rollback_status=0
        audio_restore_stream input "$stream_id" "$stream_sink" || rollback_status=1
      else
        moved=$((moved + 1))
        continue
      fi
    fi
    audio_restore_default "$direction" "$old_id" "$old_name" || rollback_status=1
    if [[ $direction == input ]]; then
      while IFS=$'\t' read -r moved_id moved_sink; do
        [[ -n $moved_id ]] || continue
        audio_restore_stream input "$moved_id" "$moved_sink" || rollback_status=1
      done < <(printf '%s\n' "$streams" | head -n "$moved")
    fi
    ((rollback_status == 0)) && fail "$name: stream migration failed; previous default and streams were restored"
    fail "$name: stream migration failed and rollback was incomplete"
  done <<<"$streams"
}

audio_output_set_default() {
  (($# == 2)) || fail 'Usage: omarchy-audio-output-set-default <node-id> <sink-name>' 2
  audio_set_default output "$1" "$2"
}

audio_input_set_default() {
  (($# == 2)) || fail 'Usage: omarchy-audio-input-set-default <node-id> <source-name>' 2
  audio_set_default input "$1" "$2"
}

audio_output_sink() {
  (($# <= 1)) || fail 'Usage: omarchy-audio-output-sink [sink-name]' 2
  need pactl
  local default_name=${1:-}
  [[ -n $default_name ]] || default_name=$(timed 2 'PulseAudio default output inspection' pactl get-default-sink) ||
    fail "$name: default output inspection failed"
  [[ -n $default_name ]] || fail "$name: default output is unavailable"
  if [[ $default_name == alsa_output.* ]]; then
    printf '%s\n' "$default_name"
    return
  fi
  local downstream physical_name
  downstream=$(timed 2 'PulseAudio sink inspection' pactl list sink-inputs 2>/dev/null | awk -v virt="$default_name" '
    /^Sink Input #/ { target = "" }
    /^[[:space:]]*Sink:/ { target = $2 }
    /node\.name = / {
      node = $0
      sub(/.*node\.name = "/, "", node)
      sub(/".*$/, "", node)
      if (index(node, virt) == 1 && target != "") { print target; exit }
    }
    /application\.name = "EasyEffects"/ && virt == "easyeffects_sink" && target != "" { print target; exit }
  ') || fail "$name: DSP sink inspection failed"
  if [[ -z $downstream ]]; then
    printf '%s\n' "$default_name"
    return
  fi
  physical_name=$(timed 2 'PulseAudio physical sink inspection' pactl list sinks short 2>/dev/null |
    awk -v wanted="$downstream" '$1 == wanted { print $2; exit }') ||
    fail "$name: physical sink inspection failed"
  if [[ -n $physical_name ]]; then
    printf '%s\n' "$physical_name"
  else
    fail "$name: physical sink could not be resolved"
  fi
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
