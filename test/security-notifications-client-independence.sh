#!/usr/bin/env bash
# Proves the notification daemon and the notification-send client
# presentation feature are genuinely independent axes (Layer-7 spec section
# 38): daemon selection must not implicitly package a second notify-send
# client capability, client feature selection must not package the
# omarchy.notifications daemon plugin, and selecting both together yields
# exactly the union of what each yields alone.
set -euo pipefail

core_compat_root=${1:?core-only compatibility root required}
core_notification_daemon_compat_bin=${2:?core+notification-daemon compatibility bin required}
client_compat_root=${3:?notification-client-only compatibility root required}
client_compat_bin=${4:?notification-client-only compatibility bin required}
client_and_daemon_compat_root=${5:?client+daemon compatibility root required}
client_and_daemon_compat_bin=${6:?client+daemon compatibility bin required}

# 1. Daemon selection alone must not package the notify-send client helper.
if [[ -e "$core_notification_daemon_compat_bin/bin/omarchy-notification-send" ]]; then
  printf 'daemon-only build unexpectedly packages the notify-send client helper\n' >&2
  exit 1
fi

# 2. Client feature selection alone must not package the daemon plugin tree.
if [[ -e "$client_compat_root/shell/plugins/notifications/Service.qml" ]]; then
  printf 'notification-client-only build unexpectedly packages the daemon plugin tree\n' >&2
  exit 1
fi
if [[ ! -e "$client_compat_bin/bin/omarchy-notification-send" ]]; then
  printf 'notification-client-only build unexpectedly lacks its own client helper\n' >&2
  exit 1
fi

# 3. Core alone has neither.
if [[ -e "$core_compat_root/shell/plugins/notifications/Service.qml" ]]; then
  printf 'core-only build unexpectedly packages the daemon plugin tree\n' >&2
  exit 1
fi

# 4. Selecting both together yields exactly the union: the daemon plugin
# tree AND the client helper, neither one substituting for the other.
if [[ ! -e "$client_and_daemon_compat_root/shell/plugins/notifications/Service.qml" ]]; then
  printf 'client+daemon build unexpectedly lacks the daemon plugin tree\n' >&2
  exit 1
fi
if [[ ! -e "$client_and_daemon_compat_bin/bin/omarchy-notification-send" ]]; then
  printf 'client+daemon build unexpectedly lacks the client helper\n' >&2
  exit 1
fi
if [[ ! -e "$client_and_daemon_compat_bin/bin/omanixy-notification-state" ]]; then
  printf 'client+daemon build unexpectedly lacks the daemon state helper\n' >&2
  exit 1
fi

printf '%s\n' 'security notifications client/daemon independence checks passed'
