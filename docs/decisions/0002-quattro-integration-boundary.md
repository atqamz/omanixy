# ADR 0002: Quattro Integration Boundary

## Status

Accepted.

## Context

The original Omanixy model treated useful Omarchy behavior as a collection of
desktop subsystems to recreate or wire together independently in Nix.
That approach made the downstream project responsible for a bar, launcher,
notifications, OSD, lock screen, idle behavior, wallpaper tooling, panels,
themes, and shell scripts as separate maintenance surfaces.

Omarchy Quattro centralizes much of the visible desktop presentation in an
upstream Quickshell-based shell.
Maintaining a downstream presentation implementation would duplicate upstream
work and create visual and behavioral drift.

NixOS already owns the operating system capabilities that the shell consumes.
The missing product boundary is therefore integration between the upstream
shell's external contracts and Nix-native user, session, and system
capabilities.

## Decision

Omanixy will be the Nix-native integration layer for the Omarchy Quattro
desktop shell.

It will:

- consume a reviewed and pinned upstream Quattro shell;
- leave presentation and shell UX upstream-owned;
- adapt only the external contracts required for NixOS integration;
- leave operating system authority with NixOS;
- provide Home Manager integration for user and session responsibilities;
- provide a NixOS module only for capabilities that genuinely require system
  authority;
- own the boundary, compatibility metadata, tests, and upgrade checks.

The dependency direction is:

```text
basecamp/omarchy
   Quattro shell source
          │
          ▼
      Quickshell
          │
          ▼
       Omanixy
 Nix integration boundary
          │
          ▼
        NixOS
```

The concrete Quattro and Quickshell runtime pair is selected and tested by
issue #2.
This ADR does not repin the current source baseline; the current pin and its
validation state are recorded in `upstream/omarchy.yaml`.

A narrow compatibility adapter is not a presentation fork.
An adapter is permitted only when a supported upstream consumer needs an
observable external contract that native NixOS or Quickshell cannot provide
directly.
Persistent source patches require documented justification, minimal scope,
focused regression coverage, and an explicit relationship to the pinned
source.

## Positive consequences

- The downstream codebase is smaller.
- Upstream UI improvements can flow naturally into the integration.
- Behavioral and visual drift is reduced.
- System ownership is explicit.
- Third-party reuse is the primary correctness target.
- Compatibility work is easier to audit.
- The review surface is smaller and focused on integration contracts.

## Negative consequences

- Upstream shell-contract changes become explicit compatibility work.
- Some `omarchy-*` ABI adapters may remain necessary.
- Quickshell compatibility becomes part of the tested support matrix.
- New upstream QML dependencies can introduce integration work.
- Security-sensitive lock and polkit integration remain platform-specific
  work.

## Rejected alternative

Omanixy will not broadly reimplement every Omarchy desktop subsystem as
independent Nix modules.

That alternative duplicates upstream presentation and creates an indefinitely
expanding maintenance surface.
It also makes Omanixy responsible for visual behavior that Quattro already
owns.

Keeping a narrow adapter for an external contract does not weaken this
decision.
The adapter connects an upstream consumer to a Nix-native capability without
copying the presentation layer.

## Follow-up boundaries

- Issue #2 owns the runtime, exact source selection, tested Quickshell pairing,
  configuration state, service lifecycle, and IPC substrate.
- Issue #3 owns the Quattro contract audit, compatibility adapters, and
  population of the porting matrix.
- Issue #4 owns lock, PAM, polkit, idle, notification, and session security.
- Issue #5 owns SemVer and release automation.
- Issue #6 owns standalone adoption documentation and Universe migration.
