# Upstream

Omanixy attributes the presentation source to
[`basecamp/omarchy`](https://github.com/basecamp/omarchy).
The repository pins the reviewed Quattro source at revision
`f0020448ca87329199de7cb12f2015ebc4a3e5e7`.
The pinned Quickshell pairing is revision
`28771c7c74b42e20afca0b1b63980cb46515537c`.
The pair and validation state are recorded in
[`upstream/omarchy.yaml`](../upstream/omarchy.yaml).

## Pinning policy

Runtime and release inputs must use exact immutable revisions.
Mutable branch heads may be inspected during research, but they are never
release inputs.

An upstream upgrade requires a dedicated GitHub Issue that records:

- the exact Omarchy revision and source date;
- the exact or deliberately selected Quickshell revision;
- the contracts affected by the change;
- the compatibility and regression checks performed;
- the Omanixy impact and release decision.

Do not let a routine `nix flake update` silently change the supported shell
behavior.
Ports use the current recorded revision until that explicit upgrade issue
changes the pin.

## Quattro compatibility pair

The target source model is:

```text
Omarchy Quattro f0020448ca87329199de7cb12f2015ebc4a3e5e7
              +
Quickshell 28771c7c74b42e20afca0b1b63980cb46515537c
              ↓
         Omanixy release
```

The pair is one auditable compatibility unit.
Quickshell compatibility must be tested independently of source changes because
the stable package available from Nixpkgs is not automatically suitable for
every Quattro revision.

Issue #2 selected and tested the concrete pair.
The recorded pair is the release baseline until an explicit upstream upgrade
issue revalidates both inputs together.

## Source consumption

The runtime consumes the reviewed upstream shell from a deterministic,
immutable compatibility root derived from the source-only flake input.
The root contains the pinned runtime entrypoint, shared QML libraries, service
objects, and the selected plugin files required by the supported baseline and
its reachable panels.
It applies eleven narrow compatibility patch sites:

- `shell/services/PluginRegistry.qml` applies the disabled-plugin floor to bar
  widgets so blocked first-party widgets cannot be re-enabled through layout
  entries.
- `shell/plugins/panels/network/Panel.qml` and its `Model.js` filter enterprise
  Wi-Fi entries because the pinned panel otherwise exposes an unsupported
  credential flow.
- `shell/plugins/panels/network/Panel.qml` also removes the Custom DNS
  provider, action, and pill because the corresponding Omarchy terminal
  workflow is not a generic NixOS contract.
- `shell/plugins/panels/network/Panel.qml` hides the speed-test action because
  the pinned third-party benchmark cannot be represented honestly by a narrow
  generic adapter.
- `shell/plugins/panels/clock/BarWidget.qml` routes middle-click to the
  supported clock panel instead of the unavailable timezone command.
- `shell/plugins/bar/Bar.qml` replaces the Omarchy helper-backed transparent
  foreground path with the native theme color and removes its helper process.
- `shell/plugins/menu/Menu.qml` removes the pinned power-profile provider when
  the selected runtime lacks the power-control capability, so persisted menu state cannot
  invoke an absent helper or backend.
- `shell/plugins/menu/Menu.qml` removes the pinned font provider because the
  generic runtime does not provide Omarchy font enumeration or mutation.
- `shell/plugins/menu/BarWidget.qml` removes the unsupported terminal-provider
  right-click action while preserving the remaining menu behavior.
- `shell/plugins/menu/Menu.qml` routes launcher deletion through a
  user-owned-entry predicate rather than presenting a false system deletion
  affordance.
- `shell/services/AppLibrary.qml` adds the user-owned entry scan and
  `canRemove()` predicate behind that guard, and validates the desktop ID
  before composing a launch command, so an entry with an unrepresentable ID
  does not launch instead of interpolating the ID into a shell string.

Each patch is tied to a pinned source location, has a focused compatibility
assertion, and is kept smaller than the upstream feature it excludes.
Unsupported first-party plugin directories are absent rather than merely
advertised as disabled.
The screenshot adapter preserves the pinned smart picker, including frozen
selection geometry, monitor transforms, tiny-click snapping, and the
best-effort clipboard and notification behavior after a successful capture.
The direct `--editor` form is implemented and tested, but no pinned default
Quattro consumer reaches it, so it is not claimed as shell-facing support.
The root also supplies Omanixy's safe fallback shell configuration, audited
menu, launcher-hides file, and helper surface.
Runtime-writable configuration and state must be materialized outside the
store.
The feature audit assigns always-loaded `PluginRegistry.qml` and
`BarWidgetRegistry.qml` to `core`, launcher library sources to `launcher`, and
the generated safe menu to `core` with per-invocation feature attribution for
clipboard, screenshot, launcher, and power actions.
This prevents a broad directory label from hiding a cross-feature dependency.

`OMARCHY_PATH` points at this compatibility root as an intentional source
compatibility interface.
The root has a narrow `bin/` view containing only the audited helper links
required by reachable Quattro consumers.
It does not authorize emulating the complete Omarchy filesystem or copying the
upstream `bin/` tree.

## Porting ledger

`upstream/porting-matrix.yaml` is the durable compatibility ledger.
Each entry records the exact Quattro revision, source path, observable
requirement, classification, ownership, dependencies, helper or native API,
tests, and rationale.
It distinguishes native Quickshell contracts from Omanixy adapters, records
support state independently from compatibility classification, and records
intentional omissions and issue #4 security boundaries.

`scripts/audit-quattro-contracts` scans the pinned Quattro roots without
fetching the network or treating the complete upstream `bin/` tree as
reachable.
Its deterministic checked-in output is
[`upstream/quattro-contracts.json`](../upstream/quattro-contracts.json).
The flake check regenerates it from the exact source and fails closed when a
new helper, executable, absolute helper path, environment variable, service,
PAM path, or menu command appears.
The security audit also scans the explicit pinned security-source inventory
and follows the helper closure from each edge whose disposition is
`audited-source`, so new helper and executable references in lock, PAM,
polkit, idle, notification, and their audited-source host-policy scripts
cannot hide behind the excluded upstream `bin/` tree.
A helper edge dispositioned anything other than `audited-source` is recorded
but not traversed further: that disposition is a reviewed decision to trust
the helper at its own boundary, not a claim that whatever it in turn invokes
has also been discovered.
The audit is a static discovery guard, not proof of semantic completeness.
The structured compatibility manifest adds referenced-helper hashes, consumer
edges, adapter ownership, and focused-test edges, while closure checks make
those relationships fail closed.
A referenced-helper hash is provenance and drift evidence: it proves the file
is unchanged since its disposition was reviewed, not that its behavior is
safe.
Its external executable capability map is consumed by the feature-consumer
closure and runtime capability checks, so a known command added to a selected
source requires its capability to be present in that presentation feature's
runtime closure.
Focused adapter tests provide behavioral evidence.
Live Wayland, Hyprland, and UWSM smoke is separate integration evidence and is
not claimed by this branch.

## Native Quickshell backend mapping

The selected Quickshell revision supplies native bindings for several Quattro
contracts.
Omanixy keeps these capabilities native and records the host service as the
owner.

| Quickshell source area | Quattro capability | Host backend |
| --- | --- | --- |
| `src/network/` and `Quickshell.Networking` | Network devices and Wi-Fi state | NetworkManager, `org.freedesktop.NetworkManager` |
| `src/bluetooth/` and `Quickshell.Bluetooth` | Adapters and device state | BlueZ, `org.bluez` |
| `src/services/upower/` and `Quickshell.Services.UPower` | Battery and power profiles | UPower, `org.freedesktop.UPower`; power-profiles-daemon, `org.freedesktop.UPower.PowerProfiles` |
| `src/services/mpris/` and `Quickshell.Services.Mpris` | Media discovery and playback | MPRIS, `org.mpris.MediaPlayer2` |
| `src/services/pipewire/` and `Quickshell.Services.Pipewire` | Audio nodes and streams | PipeWire and WirePlumber |
| `src/services/status_notifier/` and `Quickshell.Services.SystemTray` | Status notifier tray items and menus | StatusNotifierWatcher, `org.kde.StatusNotifierWatcher` |

The adapters in the ledger exist only for observable commands that the pinned
Quattro consumers still invoke around these native APIs.
Pinned-source references are not sufficient evidence of support: the
post-patch compatibility root must also retain a reachable consumer.
They do not start or configure a second instance of any host service.

See [porting-principles.md](porting-principles.md) for the `exact`, `adapted`,
`omitted`, and `blocked` taxonomy.
