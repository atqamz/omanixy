# Quattro Runtime

Omanixy runs the pinned Omarchy Quattro shell as a Nix-native Home Manager
user service.
Omarchy owns the QML presentation, NixOS owns host capabilities, and Omanixy
owns the integration boundary.

## Reviewed runtime pair

The release baseline is one compatibility unit:

```text
Omarchy Quattro  f0020448ca87329199de7cb12f2015ebc4a3e5e7
Quickshell      28771c7c74b42e20afca0b1b63980cb46515537c
Nixpkgs         241313f4e8e508cb9b13278c2b0fa25b9ca27163
```

Both inputs are immutable flake sources.
The Quickshell input is compiled from its exact source revision by overriding
the pinned nixpkgs Quickshell package build.
This retains the package's Qt/QML dependency closure while making the
candidate revision explicit and auditable.
The nixpkgs revision, including the Qt/QML build recipe used for the
override, is part of the recorded validation provenance.

The pair was checked against the Quattro imports and APIs used during startup,
including `ShellRoot`, `IpcHandler`, process and file APIs, Wayland
layer-shell, Hyprland, plugin loading, PipeWire and networking imports, and
WlSessionLock type loading.
The hermetic checks and a real Wayland/Hyprland smoke test passed for this
pair.
An upstream upgrade must select and validate a new pair intentionally rather
than following a branch tip through an unrelated flake update.

## Public API

Import the Home Manager module and enable the shell:

```nix
{
  imports = [ inputs.omanixy.homeManagerModules.default ];

  programs.omanixy = {
    enable = true;
    shell.config = {
      # Whole-file upstream-compatible shell.json configuration.
    };
  };
}
```

`programs.omanixy.enable` and `programs.omanixy.shell.config` are the public
options.
The structured config is the escape hatch for upstream schema changes rather
than a Nix option for every QML property.
Omanixy always appends its #4 safety floor to `disabledPlugins`, even when a
custom whole-file config omits that field.
The raw config escape hatch cannot enable unfinished lock, polkit, idle,
notification, or related security-sensitive surfaces.
The NixOS module is valid and intentionally has no privileged declarations for
this baseline.

The package output is
`packages.${system}.omanixy-shell`.
It contains the runtime entry point, the IPC wrapper, the selected Quickshell
executables, and the small utility closure required by the baseline.

## Service lifecycle

Home Manager installs `omanixy-shell.service` for `systemd --user`.
It is wanted by `graphical-session.target`, ordered after that target so UWSM
can establish the compositor session first, and is part of the graphical
session.
Systemd is the only supervisor.
The service uses `Restart=on-failure`, `RestartSec=2s`, and a five-start limit
within 60 seconds.
Intentional stops do not relaunch the shell.
The upstream Bash restart loop is not used.

The service inherits the graphical-session environment supplied to the user
manager.
In a supported UWSM or equivalent session this includes the active
`WAYLAND_DISPLAY`, `XDG_RUNTIME_DIR`, `HYPRLAND_INSTANCE_SIGNATURE`, and
`DBUS_SESSION_BUS_ADDRESS`.
Display names are not hard-coded.
The service explicitly sets `OMARCHY_PATH`, `QS_DISABLE_FILE_WATCHER`, and
`QS_NO_RELOAD_POPUP`.
The latter two preserve Quattro's deliberate explicit-restart behavior for
the immutable source model.

## Source and runtime closure

Quattro is consumed directly from the immutable store source through
`OMARCHY_PATH`.
Omanixy does not copy the upstream QML tree or create a fake Omarchy
filesystem.

The closure contains the selected Quickshell, its Qt/QML dependencies,
`hyprctl` for shell-specific Hyprland integration, `fc-match`,
`inotifywait`, and the small command-line utilities used by the
pinned shell bootstrap and plugin discovery.
The upstream package list, Arch tools, `pacman`, `yay`, and
`atqamz/universe` are not dependencies.
The generated wrappers do not append the host `PATH`.

## Configuration and state ownership

The ownership model is deliberately whole-file and idempotent:

| Path | Ownership |
| --- | --- |
| `~/.config/omarchy/shell.json` | Declaratively seeded, then fully user-owned and writable |
| `~/.config/omarchy/shell.toml` | Optional fully user-owned theme override |
| `~/.config/omarchy/plugins/` | User-local plugin directory |
| `~/.local/state/omarchy/current/theme/` | Seeded generated theme state, then runtime writable |
| `/nix/store/.../omarchy-quattro-...` | Declaratively immutable upstream source |
| `/nix/store/.../omanixy-shell-theme-...` | Immutable theme seed |

First activation creates `shell.json` and the minimal theme seed.
Home Manager activation side effects run through its `run` helper, so
`home-manager switch --dry-run` logs planned writes without creating or
changing user state.
Later activations preserve existing regular files, including runtime-mutated
or manually edited content.
Manually removing a safety-disabled plugin from an ordinary user-owned file is
an explicit opt-in to that unsupported surface; Omanixy does not overwrite the
file or claim that the feature is safe or implemented.
Store-backed shell configuration symlinks are the one migration case where
Omanixy preserves the upstream JSON while adding its mandatory safety floor
before materializing the file.
If an older activation left a writable-state symlink into the store, the
activation copies its contents out to ordinary user storage before continuing.
It never writes runtime state into the store.
Disabling and re-enabling the module does not silently replace customization.

Quattro's user plugin directory remains discoverable.
Upstream first-party plugins are present in the pinned source, but the
baseline only claims the core bar and IPC surface.
Third-party and user-local QML are trusted, unsandboxed code running in the
shell process.
Omanixy does not provide a plugin installation or packaging framework.

The theme seed contains the `colors.toml` and `shell.toml` material needed by
the baseline Quattro surface.
It does not become a global GTK, Qt, terminal, Hyprland, or application theme
source.

## IPC

The package provides:

```text
omanixy-shell <target> <method> [args...]
```

The wrapper never starts Quickshell.
It invokes the exact packaged runtime, forwards positional arguments without
shell reparsing, adds the upstream-compatible empty payload for
`shell summon` and `shell toggle` calls with a plugin target, and uses a
bounded timeout.
It requires the authoritative `WAYLAND_DISPLAY` provided by the graphical
session and the authoritative absolute, existing `XDG_RUNTIME_DIR`.
The runtime directory is required for both exact socket validation and
Quickshell's IPC instance namespace.
An absolute `WAYLAND_DISPLAY` is used directly as the socket path.
For a relative display name, the wrapper resolves only
`$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY`.
It never selects a socket by mtime or guesses among multiple sessions.
Missing or stale session environment fails with a diagnostic before Quickshell
is invoked.
It distinguishes unavailable, not-ready, timeout, malformed, and IPC-level
target/function errors.

Examples:

```text
systemctl --user restart omanixy-shell
systemctl --user status omanixy-shell
journalctl --user -u omanixy-shell
omanixy-shell shell ping
```

## Baseline and deferred surfaces

The baseline proves that Quickshell starts, Quattro loads from the pinned
source, the core bar and Hyprland workspace surface render, configuration is
loaded, plugin discovery initializes, and IPC ping works.
Security-sensitive and host-capability-heavy plugins are disabled by the
default seed, including the clipboard overlay, rather than being made to
appear functional.

Issue #3 remains responsible for the comprehensive executable, file,
environment, D-Bus, audio, network, Bluetooth, power, screenshot, clipboard,
brightness, and source-drift contract work.
The baseline does not emulate those helpers.

Issue #4 remains responsible for native locking, PAM, fingerprint, polkit,
idle, notification ownership, and lock recovery hardening.
The default baseline does not enable those security-sensitive surfaces.

## Debugging and upgrades

Inspect the rendered unit and activation output through Home Manager, then
use `systemctl --user status omanixy-shell` and
`journalctl --user -u omanixy-shell`.
Run `omanixy-shell shell ping` only after the service is running.
The shell source, runtime pair, metadata, and checks should be reviewed
together for every upgrade.
