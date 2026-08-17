# ADR 0004: Immutable Quattro Compatibility View

## Status

Accepted.

## Context

The pinned Quattro source invokes some helpers through `PATH` and other
helpers through absolute expressions derived from `OMARCHY_PATH/bin`.
A PATH-only adapter cannot satisfy the latter contract.
The upstream default menu also contains distro-specific actions that would be
dead or unsafe in a generic NixOS integration.
Copying the full Omarchy tree or changing the upstream QML would turn Omanixy
into a filesystem emulation layer or a presentation fork.

## Decision

Omanixy sets `OMARCHY_PATH` to an immutable compatibility root derived from the
exact pinned source.
The root exposes only the pinned shell entrypoint, shared libraries, services,
and selected plugin paths required by the supported runtime graph.
It supplies an Omanixy safe fallback `config/omarchy/shell.json`, the
launcher-hides file required by app discovery, and a checked-in safe menu
definition.
Its complete `bin/` surface is not copied into the root.
The root contains only dispatch wrappers for the audited helper names required
by reachable Quattro consumers.
The compatibility view carries ten documented persistent source patch sites:
the registry safety floor for bar widgets, enterprise Wi-Fi filtering through
the network panel's model, removal of the Custom DNS provider/action/pill,
hiding the unsupported speed-test action, clock middle-click routing, the
native bar transparency fallback, the selected-feature power-provider gate, a
selective user-owned launcher-delete action, and the app-library ownership scan
and validated launch path behind it.
Each patch is pinned to a source path and covered by a focused closure or
behavioral check because native Quickshell APIs and a helper adapter cannot
remove an unreachable presentation affordance.
The runtime package exposes only explicitly audited helper names, each linked
to a narrow shared adapter or a native executable.
The public `bin/omanixy-shell` path belongs to the dedicated IPC package and
is not linked through the generic compatibility-helper loop.
The internal compatibility-bin copy retains an `omarchy-shell` route only for
dispatcher and source-closure evidence.

Feature selection is capability policy, not persisted shell preference.
The writable `shell.json` contains the baseline permanent disabled-plugin set
and explicit user choices.
The compatibility root computes a separate immutable block set from that
baseline plus every plugin belonging to an unselected feature.
Omanixy-owned capability metadata records the selected set outside
`shell.json`, while the registry remains the enforcement boundary.
Consequently a fresh narrow activation can expand later, and a stale broad
file cannot revive an unselected runtime.

`passthru.omarchySource` remains the exact unmodified source identity.
`passthru.omarchyCompatibilityRoot` identifies the separate compatibility
view.
The contract scanner and closure checks fail when new reachable source
contracts appear or when the compatibility surface expands accidentally.

The safe menu retains Quattro's existing menu presentation and data-loading
mechanism.
It retains the pinned smart screenshot action while omitting Omarchy update,
Arch package, theme-management, agent, privileged DNS mutation, and issue #4
security actions.
User-owned extension menus remain outside the baseline support claim.

### Persistent source patch inventory

The compatibility view carries exactly these ten pinned-source patch sites.
Each patch is a presentation reachability guard or a native portability fix,
not a replacement for an adapter that could provide the same contract.

| Pinned source location | Behavioral delta | Why an adapter is insufficient | Ownership and regression evidence |
| --- | --- | --- | --- |
| `shell/services/PluginRegistry.qml`, `isEnabled()` before manifest dispatch | Applies the immutable disabled-plugin floor before any first-party widget or panel can be enabled, even if a user-owned config removes the entries. | The registry decides reachability before any helper runs, so a command adapter or a mutable config cannot re-enable blocked issue #4 or unsupported first-party surfaces. | Omanixy owns the compatibility safety floor; `test/feature-lifecycle.sh` executes the registry policy for full, clipboard-only, and core selections, while `test/runtime-closure.sh` proves the blocked source directories are absent. |
| `shell/plugins/panels/network/Model.js`, exported network model functions, and `shell/plugins/panels/network/Panel.qml`, `syncWifiNetworks()` | Filters WPA2-Enterprise and WPA-EAP networks before display and exposes only supported DNS providers. | The unsupported credential flow is created by the panel model and the Custom DNS row is created by QML; command failure cannot remove those visible affordances. | Omanixy owns the narrow reachability adaptation while NetworkManager remains host-owned; `test/qml-patch-behavior.sh` covers enterprise filtering and provider values. |
| `shell/plugins/panels/network/Panel.qml`, DNS provider list, selection handler, and provider pill | Removes the Custom DNS action and pill. | Custom DNS would require the pinned privileged global `/etc` mutation, which is outside the host-owned NetworkManager boundary. | Omanixy omits the global policy action; the exact Nix substitutions fail closed during package construction, while `test/qml-patch-behavior.sh` executes the exported supported-provider model. |
| `shell/plugins/panels/network/Panel.qml`, `canRunSpeedTest` and speed header/action properties | Hides the speed-test action. | The benchmark helper cannot provide honest generic measurements without its Omarchy-specific endpoint and transfer stack. | Omanixy omits the feature; `test/runtime-closure.sh` proves the unsupported speed-test source and overlay are absent. |
| `shell/plugins/panels/clock/BarWidget.qml`, middle-button handler | Opens the supported clock panel instead of invoking `omarchy-menu-timezone`. | The timezone command is outside the generic boundary and the panel route is a presentation event, not an external helper contract. | Omanixy owns the portability patch; the exact pinned-text substitution fails closed during package construction. |
| `shell/plugins/bar/Bar.qml`, `refreshTransparentForeground()` and its helper `Process` | Uses the native Quickshell theme foreground for transparent bars and removes the unavailable helper process. | A helper could not reproduce the bar's live theme binding without retaining a downstream presentation process, while the pinned Quickshell property already supplies the required value. | Omarchy remains presentation owner and Quickshell remains runtime owner; `test/qml-patch-behavior.sh` executes the patched bar and verifies its native foreground binding and bar-off state. |
| `shell/plugins/menu/Menu.qml`, pinned power-profile provider block | Removes the power-profile provider and its helper actions when the selected runtime does not include the power feature, while preserving unrelated menu providers. | The immutable feature boundary must not leave a persisted user menu able to invoke helpers or backends absent from the selected runtime. | Omanixy owns the fail-closed feature gate; `scripts/patch-menu-power-provider` performs an exact source-shape replacement and `test/qml-patch-behavior.sh` proves both removal and drift failure. |
| `shell/plugins/menu/Menu.qml`, pinned font provider block | Removes the font provider and its unsupported enumeration and mutation commands. | A generic runtime cannot claim Omarchy font management without a separate Nix-native design. | Omanixy omits the provider; `scripts/patch-menu-font-provider` performs an exact source-shape replacement and `test/qml-patch-behavior.sh` proves both removal and drift failure. |
| `shell/plugins/menu/Menu.qml`, Delete-key handler | Routes Delete through `AppLibrary.canRemove()` and does not invoke removal for system, Nix-store, missing, malformed, symlink, or traversal entries. | Omanixy can safely remove only a user-owned desktop entry, while AppLibrary displays system and Nix-managed entries too. | Omanixy owns the removability guard and the adapter retains a separately tested user-entry contract; `test/qml-patch-behavior.sh`, `test/launcher-delete-contract.sh`, and `test/compat-adapters.sh` cover both sides. |
| `shell/services/AppLibrary.qml`, user-owned entry scan, `canRemove()`, and the launch dispatch, applied by `scripts/patch-app-library` and two pinned-text substitutions | Adds the `userOwnedEntryIds` scan and the `canRemove()` predicate that back the Menu delete guard, and routes launching through `AppLibrarySupport.launchCommand()`. A desktop ID that fails `^[A-Za-z0-9][A-Za-z0-9_.@+-]*$` yields no command, so the entry does not launch and no shell command is composed from it. | The delete guard needs the ownership of every displayed entry, which only the library that enumerates them can compute; and the launch path interpolates a desktop ID into a shell string, so a helper invoked after interpolation could not undo an unsafe ID. | Omanixy owns the ownership scan and the ID validation; `test/launcher-delete-contract.sh` executes `userOwnedEntryIds` and `canRemove()` in the patched library, and `test/uwsm-integration.sh` executes `AppLibrarySupport.launchCommand()` for the accepted and the rejected desktop ID. The rejected-ID case is silent by design: the library composes no command and shows no error, and the live launch smoke is unclaimed unless `OMANIXY_LIVE_UWSM=1`. |

The network model and panel edits are one behavioral patch site family, so the
inventory has ten sites while documenting every persistent file and symbol.
Each source edit uses an exact pinned-text substitution or a fail-closed
structured transformer and therefore fails the build if the pinned source
shape changes.

## Rationale

This preserves upstream Quattro presentation while satisfying the declared
absolute-helper contracts that supported consumers use.
The immutable view is deterministic and reviewable, and it prevents an
accidental passthrough of the large upstream `bin/` tree.
The menu rule prevents visible controls from silently invoking unsupported
Omarchy behavior.

## Consequences

- Absolute helper references can be supported without mutating `/nix/store`.
- The compatibility root adds one small immutable store path to the runtime.
- New upstream helper or menu contracts require an intentional snapshot and
  ledger review.
- Omanixy owns adapters and menu compatibility, but host services remain
  owned by NixOS or the session.
- A future upstream portability improvement can remove the compatibility view
  or reduce it without changing Quattro presentation ownership.

## Contract evidence

The compatibility manifest records pinned consumer evidence, post-patch
reachability, implementation identity, observable fields, and focused test
cases separately.
`exact` describes an unchanged observable contract.
`adapted` records a deliberate narrowing or hardening and names the changed
failure or side-effect behavior.
Static source scanning is discovery evidence only; it does not establish
semantic compatibility by itself.
