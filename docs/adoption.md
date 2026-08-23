# Public adoption and downstream validation

## Purpose

Public usability is proven from the outside of Omanixy's internal module tree.
A valid release must work for a clean consumer that knows only the documented
flake outputs and options.

Universe is downstream evidence, not a dependency and not a source of public
policy.

## Standalone fixture

`examples/standalone` is the canonical third-party-style fixture.

It deliberately uses a generic user, generic host name, ordinary NixOS and
Home Manager modules, and no personal path or machine policy.
The fixture consumes Omanixy as a flake input and imports only the public
`homeManagerModules.default` and `nixosModules.default` outputs.

Its safe standalone Home Manager configuration proves:

- `programs.omanixy.enable = true` is sufficient to create the shell runtime;
- the generated `omanixy-shell.service` has the documented graphical-session
  lifecycle, restart policy, runtime command, and immutable environment;
- presentation feature groups can be omitted;
- `programs.omanixy.shell.config` can override upstream-compatible state;
- native lock, polkit-agent, idle, and notification-daemon ownership can stay
  disabled while an external notification daemon remains enabled;
- the activation package builds without importing the NixOS module.

Its integrated NixOS configuration additionally proves:

- the public NixOS and Home Manager modules compose through the standard Home
  Manager NixOS integration;
- common host capabilities remain NixOS-owned;
- the optional native-lock system/session handshake is explicit: NixOS enables
  `programs.omanixy.security.pam.password`, while Home Manager separately
  enables `programs.omanixy.security.lock`;
- a NixOS toplevel evaluates far enough to force assertion checking and
  generated system configuration;
- the dedicated password PAM service is generated from the public option.

The fixture also constructs an intentionally unsupported standalone native-lock
configuration and verifies that the failed assertion contains the actionable
standalone/Home-Manager and PAM guidance.

The repository's canonical `just check` command runs the fixture with a nested
`nix flake check --no-write-lock-file`, so the example cannot silently drift
away from the public API.

## Validation layers

Different contracts are tested at the layer that can prove them without
pretending a fake graphical session is real hardware.

| Contract | Validation layer |
| --- | --- |
| Flake outputs and public imports | standalone fixture flake evaluation |
| Home Manager activation and runtime closure | standalone activation-package build |
| NixOS/Home Manager ownership handshake | integrated NixOS evaluation and assertions |
| Generated user-service fields and command paths | evaluated Home Manager unit contract |
| Unsupported option combinations | failed assertion and diagnostic contract |
| PAM, polkit, notification, and recovery system behavior | repository NixOS VM tests |
| Quattro helper and capability closure | root package and compatibility checks |
| Wayland rendering, monitor topology, suspend/resume, input, and GPU behavior | real downstream hardware |

A synthetic VM with a fake Wayland compositor would not prove shell rendering,
monitor hotplug, suspend/resume, or GPU behavior. Omanixy therefore does not add
visual tests merely to claim coverage.

## Universe downstream evidence

`atqamz/universe` became an ordinary downstream consumer in merged Universe PR
#46, `feat(presentation): migrate desktop presentation to Omanixy`.
That migration consumed Omanixy through its flake input and public Home Manager
module instead of copying Universe implementation into this repository.

The downstream split remains:

```text
basecamp/omarchy
       |
       v
    Omanixy
       |
       v
    Universe
       |
       +-- sfx14
       +-- pavg15
```

The migration kept host policy downstream: Hyprland bindings, host display and
input configuration, application selection, theme policy, external capability
services, power/GPU behavior, and machine-specific health checks did not become
Omanixy public API.

The migration also replaced Caelestia as the active presentation owner only
after the Omanixy runtime and capability split had been validated. Conflicting
session owners were not intentionally co-enabled during cutover. Rollback
remained available through the previous NixOS generation and Git history rather
than by running two presentation shells or two owners of the same D-Bus/session
role at once.

The merged downstream validation included full `sfx14` and `pavg15` toplevel
builds plus live shell, IPC, launcher, clipboard, screenshot, brightness,
media, volume, notification, and ownership smoke checks where the controlling
session allowed them.
Password-authenticated unlock, logout/login, and reboot were intentionally not
claimed by that automation because they would require credentials or terminate
the controlling session.

Universe may advance its pin independently after Omanixy changes land. A
Universe pin is validation evidence, never an Omanixy dependency or release
version source.

## Theme and configuration ownership

Omanixy seeds Quattro's shell configuration and runtime theme state, but it
does not own a consumer's global desktop palette policy.
The generated shell configuration becomes user-owned after seeding; only exact
known Omanixy-generated baselines are migrated automatically.
Customized or malformed user files are not silently rewritten into a new
policy.

A downstream configuration should choose its own theme source and feed the
parts it owns independently:

```text
consumer theme source
        |
   +----+-------------+
   v    v             v
Quattro GTK       compositor/apps
```

Consumers must not treat writable Quattro runtime theme state as an accidental
source of truth for unrelated GTK, launcher, compositor, or application
configuration.

## Hardware acceptance boundary

Real hardware remains the right place to validate graphical-session behavior
that depends on devices or lifecycle transitions.
Useful downstream checks include login/logout, shell restart, monitor hotplug,
suspend/resume, audio device changes, NetworkManager and Bluetooth surfaces,
battery/power profiles, notification delivery, launcher actions, clipboard and
emoji flow, screenshots, wallpaper/theme changes, and lock/unlock when the
chosen security path is ready to test safely.

A failure discovered downstream belongs in Omanixy only when the missing
capability is generic. Personal bindings, host layout, machine power policy,
and application preferences stay downstream.

## First-release readiness

The first public release is based on the standalone contract rather than on one
personal machine.
A release candidate must retain all of the following:

- the standalone fixture evaluates and its Home Manager activation package
  builds;
- the integrated NixOS fixture forces the public system/session ownership
  contract;
- unsupported combinations fail with useful diagnostics;
- the README documents prerequisites, module responsibilities, support state,
  ownership, troubleshooting, pins, and upgrades;
- the public examples contain no Universe or personal path assumptions;
- the root `nix flake check --print-build-logs`, `just fmt`, and `just check`
  remain green;
- experimental security/session ownership stays explicit and opt-in until its
  support state is deliberately promoted.

100% Omarchy parity is not required for the first release. The compatibility
ledger remains the authority for exact, adapted, omitted, and blocked surfaces.
