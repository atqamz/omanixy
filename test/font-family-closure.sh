#!/usr/bin/env bash
set -euo pipefail

compatibility_root=${1:?compatibility root path required}
fontconfig_file=${2:?fontconfig file required}
icon_font_package=${3:?icon font package required}
icon_font_package_provisioned=${4:?icon font package provisioning result required}
fc_match=${5:?fc-match executable required}

test_root=$(mktemp -d)
trap 'chmod -R u+w "$test_root" 2>/dev/null || true; rm -rf "$test_root"' EXIT
mkdir -p "$test_root/cache"
test "$icon_font_package_provisioned" = true
test -d "$icon_font_package/share/fonts"

mapfile -t families < <(
  grep -RhoE 'fontFamily[[:space:]]*:[[:space:]]*"[^"]+"' "$compatibility_root/shell" --include='*.qml' \
    | sed -E 's/.*fontFamily[[:space:]]*:[[:space:]]*"([^"]+)"/\1/' \
    | sort -u
)
test "${#families[@]}" -gt 0

for family in "${families[@]}"; do
  resolved=$(
    FONTCONFIG_FILE="$fontconfig_file" XDG_CACHE_HOME="$test_root/cache" \
      "$fc_match" "$family" -f '%{family}\n' | head -n 1 | tr ',' '\n'
  )
  case "$family" in
    cursive|emoji|fantasy|fangsong|math|monospace|sans-serif|serif|system-ui)
      test -n "$resolved"
      ;;
    *)
      if ! grep -Fqx "$family" <<<"$resolved"; then
        printf 'unresolvable QML font family=%s resolved=%s\n' "$family" "${resolved:-<none>}" >&2
        exit 1
      fi
      ;;
  esac
done

printf '%s\n' 'font family resolution checks passed'
