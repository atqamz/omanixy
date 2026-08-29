#!/usr/bin/env bash
set -euo pipefail

activation=${1:?launcher activation script required}
runtime=${2:?launcher runtime path required}
terminal_package=${3:?terminal package path required}
terminal_desktop=${4:?terminal desktop entry required}
custom_activation=${5:?custom launcher activation script required}
custom_runtime=${6:?custom launcher runtime path required}
custom_terminal_package=${7:?custom terminal package path required}
custom_terminal_desktop=${8:?custom terminal desktop entry required}
xvfb_run=${9:?xvfb-run path required}

runtime_path=$(sed -n 's/^export PATH="\(.*\)"$/\1/p' "$runtime/bin/omanixy-shell-runtime")
test -n "$runtime_path"
PATH="$runtime_path" command -v xdg-terminal-exec >/dev/null
PATH="$runtime_path" command -v gtk-launch >/dev/null
test -f "$terminal_package/share/applications/$terminal_desktop"

test_root=$(mktemp -d)
trap 'rm -rf "$test_root"' EXIT

activate() {
  local home=$1
  local activation_script=${2:-$activation}
  local config_dirs=${3:-}
  mkdir -p "$home"
  HOME="$home" USER=omanixy-test XDG_CONFIG_HOME="$home/.config" XDG_CONFIG_DIRS="$config_dirs" XDG_RUNTIME_DIR="$home/runtime" \
    bash -c 'run() { "$@"; }; source "$1"' bash "$activation_script"
}

fresh_home="$test_root/fresh"
activate "$fresh_home"
grep -Fxq "$terminal_desktop" "$fresh_home/.config/xdg-terminals.list"

existing_home="$test_root/existing"
mkdir -p "$existing_home/.config"
printf '%s\n' custom-terminal.desktop > "$existing_home/.config/xdg-terminals.list"
activate "$existing_home"
grep -Fxq custom-terminal.desktop "$existing_home/.config/xdg-terminals.list"
test "$(wc -l < "$existing_home/.config/xdg-terminals.list")" = 1

symlink_home="$test_root/symlink"
mkdir -p "$symlink_home/.config"
ln -s custom-terminal.desktop "$symlink_home/.config/xdg-terminals.list"
activate "$symlink_home"
test -L "$symlink_home/.config/xdg-terminals.list"
test "$(readlink "$symlink_home/.config/xdg-terminals.list")" = custom-terminal.desktop

system_config_dir="$test_root/system-config"
system_home="$test_root/system"
mkdir -p "$system_config_dir"
printf '%s\n' system-terminal.desktop > "$system_config_dir/xdg-terminals.list"
activate "$system_home" "$activation" "$system_config_dir"
test ! -e "$system_home/.config/xdg-terminals.list"

custom_home="$test_root/custom"
activate "$custom_home" "$custom_activation"
grep -Fxq "$custom_terminal_desktop" "$custom_home/.config/xdg-terminals.list"
custom_runtime_path=$(sed -n 's/^export PATH="\(.*\)"$/\1/p' "$custom_runtime/bin/omanixy-shell-runtime")
PATH="$custom_runtime_path" command -v xdg-terminal-exec >/dev/null
test -f "$custom_terminal_package/share/applications/$custom_terminal_desktop"

data_home="$test_root/data"
config_home="$test_root/config"
terminal_bin="$test_root/bin"
terminal_log="$test_root/terminal.log"
mkdir -p "$data_home/applications" "$config_home" "$terminal_bin"
mkdir -p "$test_root/home" "$test_root/cache"
cat > "$terminal_bin/fake-terminal" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" > "$TERMINAL_LOG"
EOF
cat > "$terminal_bin/terminal-app" <<'EOF'
#!/bin/sh
exit 0
EOF
cat > "$terminal_bin/uwsm" <<'EOF'
#!/bin/sh
if [ "$#" -ne 4 ] || [ "$1" != app ] || [ "$2" != -- ] || [ "$3" != gtk-launch ]; then
  exit 1
fi
shift 2
exec "$@"
EOF
chmod 0555 "$terminal_bin/fake-terminal" "$terminal_bin/terminal-app" "$terminal_bin/uwsm"
cat > "$data_home/applications/fake-terminal.desktop" <<EOF
[Desktop Entry]
Type=Application
Exec=$terminal_bin/fake-terminal
Icon=foot
Terminal=false
Categories=System;TerminalEmulator;
Keywords=shell;prompt;command;commandline;
Name=Omanixy test terminal
GenericName=Terminal
Comment=Omanixy test terminal
X-TerminalArgExec=--
EOF
cat > "$data_home/applications/terminal-app.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Omanixy terminal app
Terminal=true
Exec=terminal-app
Categories=System;
EOF
printf '%s\n' fake-terminal.desktop > "$config_home/xdg-terminals.list"

terminal_status=0
"$xvfb_run" -a --server-args="-screen 0 1024x768x24" \
  env \
  HOME="$test_root/home" \
  PATH="$terminal_bin:$runtime_path" \
    XDG_DATA_HOME="$data_home" \
    XDG_CONFIG_HOME="$config_home" \
    XDG_CACHE_HOME="$test_root/cache" \
    TERMINAL_LOG="$terminal_log" \
       uwsm app -- gtk-launch terminal-app.desktop > "$test_root/gtk-launch.log" 2>&1 || terminal_status=$?
if [ "$terminal_status" != 0 ]; then
  cat "$test_root/gtk-launch.log" >&2
  exit 1
fi
for _ in {1..50}; do
  test -f "$terminal_log" && break
  sleep 0.1
done
if ! grep -Fq 'terminal-app' "$terminal_log"; then
  cat "$test_root/gtk-launch.log" >&2 || true
  test -e "$terminal_log" && cat "$terminal_log" >&2 || printf '%s\n' 'terminal log missing' >&2
  exit 1
fi

printf '%s\n' 'launcher terminal provisioning checks passed'
