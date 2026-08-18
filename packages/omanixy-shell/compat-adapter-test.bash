#!/usr/bin/env bash
# shellcheck disable=SC1091 # the test harness resolves all adapter modules at runtime.
set -euo pipefail

adapter_dir=${OMANIXY_ADAPTER_DIR:-${BASH_SOURCE[0]%/*}}
source "$adapter_dir/adapters/common.bash"
source "$adapter_dir/adapters/weather.bash"
source "$adapter_dir/adapters/audio.bash"
source "$adapter_dir/adapters/network.bash"
source "$adapter_dir/adapters/power.bash"
source "$adapter_dir/adapters/display.bash"
source "$adapter_dir/adapters/notification.bash"
source "$adapter_dir/adapters/clipboard.bash"
source "$adapter_dir/compat-adapter.bash"
