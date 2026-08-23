#!/usr/bin/env bash
set -euo pipefail

# Scans the given directories for imperative writes to a pam.d path.
#
# This is a line-level heuristic, not a shell parser: it flags any line that
# mentions a pam.d path alongside a known writer command (tee, cp, install,
# mv) or a shell redirection operator (> or >>) - the concrete forms
# (tee/cp/install/mv, or cat/printf/echo/anything else redirected) that
# could produce /etc/pam.d content outside security.pam.services.<name>.text.
# It does not understand quoting, heredocs, string concatenation, or
# multi-line commands, and it is not a substitute for review.

if [ "$#" -eq 0 ]; then
  echo "usage: $0 <dir>..." >&2
  exit 2
fi

matches=$(rg -n --no-messages -e 'pam\.d' "$@" 2>/dev/null \
  | rg -e '\b(tee|cp|install|mv)\b' -e '>{1,2}' || true)

if [ -n "$matches" ]; then
  printf '%s\n' "$matches"
  exit 1
fi
exit 0
