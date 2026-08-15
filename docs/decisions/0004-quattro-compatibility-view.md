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
The root exposes the exact Quattro `shell/` source tree, the one upstream
`config/omarchy/shell.json` file read by shell startup, the launcher-hides file
required by app discovery, and a checked-in safe menu definition.
Its `bin/` surface is not copied into the root.
The runtime package exposes only explicitly audited helper names, each linked
to a narrow shared adapter or a native executable.

`passthru.omarchySource` remains the exact unmodified source identity.
`passthru.omarchyCompatibilityRoot` identifies the separate compatibility
view.
The contract scanner and closure checks fail when new reachable source
contracts appear or when the compatibility surface expands accidentally.

The safe menu retains Quattro's existing menu presentation and data-loading
mechanism.
It omits Omarchy update, Arch package, theme-management, unsupported capture,
agent, privileged DNS mutation, and issue #4 security actions.
User-owned extension menus remain outside the baseline support claim.

## Rationale

This preserves upstream Quattro presentation while satisfying the exact
absolute-helper ABI that supported consumers use.
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
