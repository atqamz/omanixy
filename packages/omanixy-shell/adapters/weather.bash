# shellcheck disable=SC2154 # shared adapter state is initialized by common.bash.
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
