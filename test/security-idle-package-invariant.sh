#!/usr/bin/env bash
set -euo pipefail

idle_without_lock_ok=${1:?idle-without-lock direct package eval result required}
idle_with_lock_ok=${2:?idle-with-lock direct package eval result required}

# Section 15/30-31: packages/omanixy-shell/default.nix's own
# idleRequiresLockValid assertion must fire for a caller that constructs
# the security attrset directly - bypassing programs.omanixy.security.idle
# and the Home Manager assertion matrix entirely - not just for a caller
# that goes through Home Manager. Both fixtures force real evaluation
# (.drvPath) rather than merely constructing an unevaluated attrset.

# idle=true, lock=false, forced directly against the package: must fail.
test "$idle_without_lock_ok" = false

# idle=true, lock=true, forced directly against the package: must pass.
test "$idle_with_lock_ok" = true

printf '%s\n' 'security idle package-level invariant checks passed'
