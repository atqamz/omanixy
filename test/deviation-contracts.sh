#!/usr/bin/env bash
set -euo pipefail

pinned_source=${1:?pinned source path required}
repo=${2:?repository path required}

audio="$pinned_source/bin/omarchy-audio-output-set-default"
text_size="$pinned_source/bin/omarchy-display-text-size"
adapter_audio="$repo/packages/omanixy-shell/adapters/audio.bash"
adapter_display="$repo/packages/omanixy-shell/adapters/display.bash"

grep -Fq "timeout 2 wpctl set-default \"\$node_id\" 2>/dev/null || true" "$audio"
grep -Fq "timeout 2 pactl set-default-sink \"\$sink_name\" 2>/dev/null || true" "$audio"
grep -Fq "gsettings set \"\$GKEY_SCHEMA\" \"\$GKEY_NAME\" \"\$1\" 2>/dev/null || true" "$text_size"
grep -Fq "gsettings reset \"\$GKEY_SCHEMA\" \"\$GKEY_NAME\" 2>/dev/null || true" "$text_size"
grep -Fq 'exit 1' "$audio"
grep -Fq 'exit 1' "$text_size"
grep -Fq 'previous default and streams were restored' "$adapter_audio"
grep -Fq 'GTK text-size update failed' "$adapter_display"
grep -Fq 'GTK text-size rollback' "$adapter_display"

printf '%s\n' 'pinned best-effort and Omanixy hardened deviation evidence passed'
