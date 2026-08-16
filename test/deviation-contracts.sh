#!/usr/bin/env bash
set -euo pipefail

repo=${2:?repository path required}
compatibility_root=${3:?compatibility root path required}

bash "$repo/test/compat-adapters.sh" "$repo" "$compatibility_root"

printf '%s\n' 'hardened deviation behavior passed'
