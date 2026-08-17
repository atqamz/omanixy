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
This branch claims the hermetic checks and source/runtime closure only.
A live Wayland, Hyprland, and UWSM smoke result must be reported separately
for the exact built runtime.
An upstream upgrade must select and validate a new pair intentionally rather
than following a branch tip through an unrelated flake update.

## Public API

Import the Home Manager module and enable the shell:

```nix
{
  imports = [ inputs.omanixy.homeManagerModules.default ];

  programs.omanixy = {
    enable = true;
    # Optional; defaults to every feature group.
    features = [ "network" "audio" ];
    shell.config = {
      # Whole-file upstream-compatible shell.json configuration.
    };
  };
}
```

`programs.omanixy.enable`, `programs.omanixy.features`, and
`programs.omanixy.shell.config` are the public options.
`features` selects the optional compatibility feature groups whose runtime
dependencies, helpers, and menu actions are built into the runtime; it defaults
to every group and is closed transitively.
See [Source and runtime closure](#source-and-runtime-closure) for the group
list and for what omitting a group removes.
The structured config is the escape hatch for upstream schema changes rather
than a Nix option for every QML property.
Omanixy seeds the safety floor in `disabledPlugins` and enforces the same
immutable floor in the compatibility-root plugin registry, even when a custom
whole-file config omits or removes those entries.
The raw config escape hatch cannot enable unfinished lock, polkit, idle,
notification, or related security-sensitive surfaces.
The NixOS module is valid and intentionally has no privileged declarations for
this baseline.

The package output is
`packages.${system}.omanixy-shell`.
It contains the runtime entry point, the IPC wrapper, the selected Quickshell
executables, and only the audited compatibility helpers required by the
baseline.

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
The safe menu's Logout action uses `uwsm stop` and is visible only when the
current graphical session is UWSM-active, so it does not terminate unrelated
user-manager sessions or workloads.

## Source and runtime closure

Quattro is consumed from a deterministic immutable compatibility root through
`OMARCHY_PATH`.
The root contains the pinned source view used by the supported runtime graph,
including shared QML libraries, shell services, the baseline bar widgets, and
the copied panel and overlay sources needed by the registry.
It applies nine narrow patch sites: the disabled-plugin floor on bar widgets,
enterprise Wi-Fi filtering through the network panel's model, removal of the
Custom DNS provider/action/pill, hiding the unsupported speed-test action,
clock middle-click routing, the native bar transparency fallback, the
selected-feature power-provider gate, a user-owned launcher-delete guard, and
the validated app-library launch and removability path.
Some unsupported first-party plugin directories are omitted from the view,
while copied baseline modules remain unreachable when disabled by the
immutable registry floor.
The root supplies Omanixy's safe fallback shell configuration, launcher-hides
file, audited default menu, and helper view.
The root `bin/` contains dispatch wrappers only for helper names required by
reachable Quattro consumers; it is not the upstream `bin/` tree.
The runtime's hermetic `PATH` includes a separate immutable compatibility-bin
store path containing only the audited helper links.
The source identity exposed as `runtime.passthru.omarchySource` remains the
unmodified exact pinned source.
The compatibility root is exposed separately as
`runtime.passthru.omarchyCompatibilityRoot`.
The helper path is exposed as `runtime.passthru.compatibilityBin`.
The generated post-patch consumer probes and their fixtures are a separate
`probes` output of the same derivation, exposed as
`runtime.passthru.compatibilityProbes`.
They are referenced only by the flake checks, so the test scaffolding is
outside the runtime closure while the probes still bind to the packaged
dispatcher and helper links they validate.
The `probes` output records the helper path it was generated against, and the
closure check rejects a probe set whose recorded helper path or helper coverage
does not match the helper surface whose identity it is validating.
Omanixy never copies the upstream `bin/` tree or creates a mutable Omarchy
filesystem.

The closure contains the selected Quickshell, its Qt/QML dependencies,
`hyprctl`, `inotifywait`, and only the feature-group utilities selected by the
consumer.
The feature groups are `network`, `audio`, `bluetooth`, `screenshot`,
`clipboard`, `power`, `monitor`, `weather`, `notification`, and `launcher`.
Selecting `bluetooth` also selects `audio` because the pinned Bluetooth panel
uses the audio default-device contract when connecting a device.
The default enables all groups needed by the safe baseline.
When a group is omitted, its helpers and menu actions are omitted and its
baseline bar widgets are added to the immutable disabled-plugin floor.
The runtime also removes the pinned core-menu provider for power profiles when
power is omitted, because that provider is a cross-feature consumer.
The clipboard group also floors the clipboard and emoji plugin IDs so a custom
configuration cannot re-enable those panels without selecting their runtime
dependencies.
The upstream package list, Arch tools, `pacman`, `yay`, and
`atqamz/universe` are not dependencies.
The generated wrappers do not append the host `PATH`.

The dispatcher selects the helper it runs from `COMPAT_ADAPTER_NAME`, falling
back to the name of the link it was invoked through.
That variable is the documented dispatch mechanism rather than a test seam:
every compatibility-root `bin/` shim exports it so one dispatcher can serve
every helper name, and setting it selects the same helper that invoking that
helper's link would.

Beyond that dispatch input the dispatcher carries two named, accepted test
seams that expose its pinned `PATH` and its dispatched command identity.
`OMANIXY_PROBE_BACKEND_PATH`, when set, prepends the named directory to the
pinned backend `PATH`, and `OMANIXY_CONSUMER_MARKER`, when set, writes the
dispatched command name to a marker file after a successful invocation.
Both are unset in every packaged entrypoint, service unit, and menu action, so
the hermetic guarantee holds for the shipped runtime; the deviation is that a
caller running as the same user can opt back into an ambient backend lookup by
setting the first variable.
They exist so the generated consumer probes exercise the packaged dispatcher
itself rather than a test-only rebuild, which is what binds the probe evidence
to the shipped helper identity.

The runtime closure and compatibility-root checks fail if an unsupported
Omarchy executable surface appears.

## Contract audit

`scripts/audit-quattro-contracts` statically scans the pinned source roots and
writes the deterministic snapshot in
`upstream/quattro-contracts.json`.
It inventories direct commands, Omarchy helper names, absolute
`OMARCHY_PATH/bin` references, dynamic commands, menu fields, filesystem
contracts, environment variables, native Quickshell modules, service names,
and security-sensitive contracts.
The flake check regenerates the snapshot from the flake-pinned source and
fails on any drift.
The fixture test also proves deterministic output, dynamic-command retention,
menu-field coverage, narrow compatibility-bin construction, and fail-closed changes for
new helpers, executables, absolute paths, services, and PAM paths.
Static audit is a pin-drift and review guard, not semantic proof of every
runtime behavior.
The structured `upstream/compatibility-contracts.json` manifest closes each
adapted helper to its pinned consumer, post-patch reachable consumer,
implementation, focused test matrix, and referenced upstream implementation
hash.
It records exact observable fields separately from intentional hardening,
narrowing, omission, and missing-backend behavior.
The closure check fails on missing edges, helper hash drift, unexpected
compatibility-bin entries, or newly reachable unlisted contracts.
Behavioral adapter tests and live smoke are separate evidence.

## Configuration and state ownership

The ownership model is deliberately whole-file and idempotent:

| Path | Ownership |
| --- | --- |
| `~/.config/omarchy/shell.json` | Declaratively seeded, then fully user-owned and writable |
| `~/.config/omarchy/shell.toml` | User-owned theme/config file; the monitor text-size adapter updates only `[font].base-size`, while preserving unrelated content |
| `~/.config/omarchy/plugins/` | User-local plugin directory |
| `~/.local/state/omarchy/current/theme/` | Seeded generated theme state, then runtime writable |
| `/nix/store/.../omarchy-quattro-...` | Declaratively immutable upstream source |
| `/nix/store/.../omanixy-omarchy-compat-root-...` | Immutable compatibility view with audited menu and helper links |
| `/nix/store/.../omanixy-shell-theme-...` | Immutable theme seed |

First activation creates `shell.json` and the minimal theme seed.
The generated baseline is versioned in `upstream/shell-baseline.json` with the
upstream-required `version: 1` plus an `omanixyBaselineVersion` marker.
The checked-in `upstream/shell-baseline-v1.json` is the exact issue #2
generated baseline from commit `c756f85dc2ad546fa2cfbad1fdf3b51913bc6723`.
Only that historical baseline, compared as normalized JSON, migrates
idempotently to the current marker and widget set; customized, malformed, or
otherwise unknown files remain user-owned and are not rewritten.
Home Manager activation side effects run through its `run` helper, so
`home-manager switch --dry-run` logs planned writes without creating or
changing user state.
Later activations preserve existing regular files, including runtime-mutated
or manually edited content.
Manually removing a safety-disabled plugin from an ordinary user-owned file does
not re-enable that surface; the compatibility-root registry applies the same
immutable floor at runtime.
First-party plugins omitted from the immutable compatibility view remain
unavailable even if a user removes their disabled ID.
Store-backed shell configuration symlinks are the one migration case where
Omanixy preserves the existing JSON while adding its mandatory safety floor
before materializing the file.
If an older activation left a writable-state symlink into the store, the
activation copies its contents out to ordinary user storage before continuing.
It never writes runtime state into the store.
Disabling and re-enabling the module does not silently replace customization.

Quattro's user plugin directory remains discoverable.
The new-install baseline enables the native or adapted tray, media, audio,
network, Bluetooth, monitor, power, weather, clipboard, emoji, launcher, and
OSD paths covered by the ledger.
Feature selection is closed transitively: Bluetooth selects audio, and weather
and screenshot select notification because their reachable consumers invoke
those helper surfaces.
The updater, agents, background/theme workflow, nightlight, low-battery
automation, and issue #4 security plugins remain disabled or absent.
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
```

## Baseline and deferred surfaces

The baseline proves that Quickshell starts, Quattro loads from the pinned
compatibility root, the configured native and adapted widgets render, and
plugin discovery initializes.
The IPC wrapper contract is covered separately by `test/ipc-wrapper.sh`, which
tests argument forwarding, graphical-session validation, bounded failure
handling, and controlled IPC invocation.
The default menu is intentionally smaller than the upstream Omarchy menu.
Every actionable baseline row is backed by a native command, an audited
adapter, or a host-owned session action.
Existing writable `shell.json` files are not overwritten when new defaults are
added unless they are an exact known generated baseline covered by the versioned
migration.

The compatibility helpers are not a general Omarchy CLI.
They implement only the invocation forms reached by supported Quattro
consumers.
Unsupported user-edited menu actions remain outside the Omanixy support
claim and fail as explicit missing or rejected commands rather than reporting
success.

Issue #4 remains responsible for native locking, PAM, fingerprint, polkit,
idle, notification ownership, and lock recovery hardening.
The default baseline does not enable those security-sensitive surfaces.

## Debugging and upgrades

Inspect the rendered unit and activation output through Home Manager, then
use `systemctl --user status omanixy-shell` and
`journalctl --user -u omanixy-shell`.
The shell source, runtime pair, metadata, ledger, and checks should be reviewed
together for every upgrade.
