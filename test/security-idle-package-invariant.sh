#!/usr/bin/env bash
set -euo pipefail

idle_without_lock_ok=${1:?idle-without-lock direct package eval result required}
idle_with_lock_ok=${2:?idle-with-lock direct package eval result required}


test "$idle_without_lock_ok" = false

test "$idle_with_lock_ok" = true

printf '%s\n' 'security idle package-level invariant checks passed'
