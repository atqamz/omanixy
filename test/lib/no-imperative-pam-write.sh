#!/usr/bin/env bash
set -euo pipefail


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
