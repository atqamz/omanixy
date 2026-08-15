# Project

Omanixy is the Nix-native integration layer for the Omarchy Quattro desktop
shell.

It brings the upstream Omarchy desktop experience to NixOS through composable
NixOS and Home Manager modules.
It keeps the operating system, host policy, and privileged capabilities
declarative and Nix-native while consuming upstream presentation.

The ownership rule is:

```text
Omarchy owns presentation.
NixOS owns the operating system.
Omanixy owns the boundary.
```

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

## Goals

Omanixy exists to provide:

- a reusable NixOS and Home Manager integration layer;
- a host for a reviewed and pinned upstream Quattro shell;
- a narrow boundary for adapting upstream shell contracts to NixOS;
- declarative system integration when shell functionality genuinely needs
  system authority;
- an auditable compatibility and support surface;
- generic public modules that do not depend on one consumer's machine policy.

Omanixy consumes upstream presentation instead of maintaining a second shell
implementation.
It may carry a narrow adapter when an upstream component requires an external
contract that NixOS does not provide directly.

## Public reuse invariant

Public Omanixy modules must work for a third-party NixOS or Home Manager
consumer without knowledge of Atqa's machines or downstream repositories.

The dependency direction is always:

```text
Omarchy
   ↓
Omanixy
   ↓
consumer NixOS and Home Manager configuration
```

`atqamz/universe` is a downstream dogfooding consumer and validation
environment.
It may expose missing generic capabilities, but Omanixy must never depend on
it.
Omanixy must never depend on Universe, Atqa-specific dotfiles, personal
applications, personal keybindings, or machine-specific hardware policy.

## Non-goals

Omanixy does not own:

- Linux distribution identity or installation;
- pacman or AUR compatibility;
- an Omarchy installer, updater, or first-run provisioning flow;
- disk partitioning, bootloader policy, kernel selection, or firmware policy;
- a complete Omarchy application bundle;
- firewall, SSH, Docker, or virtualization policy;
- user account provisioning;
- complete Omarchy filesystem emulation;
- a complete Omarchy CLI;
- a complete Omarchy Hyprland configuration;
- imperative mutation of `/etc` outside normal Nix activation;
- Atqa-specific machine or user policy.

NixOS consumers retain ownership of unrelated host and user configuration.
Omanixy can expose configuration for a host-owned capability without becoming
the global policy owner for that capability.

## Scope of the v0.1 architecture baseline

Within the v0.1 epic at
[`atqamz/omanixy#7`](https://github.com/atqamz/omanixy/issues/7), this
architecture contract is implemented by the runtime baseline and remains the
boundary for the compatibility audit, security integration, releases, and
standalone adoption.
Issue #2 selected and validated the concrete Quattro and Quickshell pair.
Issue #3 established the compatibility ledger and narrow adapters.
Issue #4 owns the remaining security work.

See [architecture.md](architecture.md) for the component contract and
[upstream.md](upstream.md) for the current pinning boundary.

The project favors explicit options, overridable defaults, and documented
compatibility decisions over copying implementation details.
