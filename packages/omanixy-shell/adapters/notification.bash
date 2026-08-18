# shellcheck disable=SC2154 # shared adapter state is initialized by common.bash.
weather_status() {
  (($# == 0)) || fail 'Usage: omarchy-weather-status' 2
  local place weather encoded_place
  place=$(COMPAT_ADAPTER_NAME=omarchy-weather-location weather_location)
  [[ -n $place ]] || fail "$name: weather location is unavailable"
  need curl
  encoded_place=$(jq -rn --arg place "$place" '$place|@uri')
  weather=$(timed 5 'weather lookup' curl -fsS --max-time 4 "https://wttr.in/$encoded_place?format=%t|%w" | tr -d '\n') ||
    fail "$name: weather service is unavailable"
  [[ $weather == *'|'* && ${weather%%|*} != "" && ${weather#*|} != "" ]] ||
    fail "$name: weather service returned malformed data"
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
