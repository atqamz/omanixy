# Architecture

Omanixy is the Nix-native integration layer for the Omarchy Quattro desktop
shell.
It consumes upstream presentation and supplies the NixOS and Home Manager
boundary required to run that presentation as a reusable desktop integration.

The ownership rule is:

```text
Omarchy owns presentation.
NixOS owns the operating system.
Omanixy owns the boundary.
```

## Dependency direction

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

The upstream Quattro source is the presentation authority.
Quickshell is the shell runtime that executes that presentation.
Omanixy provides the declarative integration boundary.
NixOS remains authoritative for the operating system and its capabilities.

Issue #2 provides the first pinned Quattro runtime baseline.
Later issues add compatibility adapters and security integrations without
changing the ownership boundary.

## Project naming

The repository remains named `omanixy` because the product owns the complete
Nix integration boundary, not only the process that launches QML.
That boundary includes modules, source and compatibility metadata, service
lifecycle, configuration and theme plumbing, adapters, capability
declarations, and tests.

`omanixy-shell` is runtime and service terminology.
For example, `omanixy-shell.service` names the systemd user unit provided by
the runtime baseline.
It is not a repository rename or a narrower product definition.

## Ownership boundaries

### Omarchy owns presentation

Upstream Omarchy owns the Quattro presentation layer, including:

- Quattro QML and visual composition;
- panels, launcher UI, and OSD presentation;
- notification presentation;
- theme-visible shell behavior;
- shell UX and other upstream presentation logic.

Omanixy consumes this presentation source.
It does not broadly copy or recreate it in Nix modules.

### NixOS owns the operating system

NixOS and the consumer's host configuration own:

- packages and system services;
- PAM configuration and authentication policy;
- polkit system capability;
- PipeWire, NetworkManager, BlueZ, and UPower;
- power-profiles-daemon and other host capabilities;
- system-level filesystem ownership;
- the kernel, boot, hardware, firewall, accounts, and provisioning policy.

Omanixy may declaratively integrate a capability that the supported shell
requires.
That integration does not make Omanixy the owner of the consumer's complete
system policy.

### Omanixy owns the boundary

Omanixy owns the integration concerns between the upstream shell and NixOS,
including:

- NixOS and Home Manager modules;
- source and version compatibility metadata;
- the Quickshell and Quattro compatibility declaration;
- systemd user integration and shell configuration plumbing;
- writable-state boundaries;
- narrow compatibility adapters;
- capability assertions and tests;
- PAM module declarations when a supported feature genuinely requires them;
- optional polkit integration;
- theme bridges and upgrade checks;
- the compatibility ledger.

Ownership is not the same as policy.
Omanixy can expose an option for a host-owned capability while leaving the
consumer free to select unrelated packages, services, keybindings, themes,
hardware policy, and user configuration.

## Module ownership

The public module split follows authority and privilege:

```text
Home Manager module
  user and session integration

NixOS module
  privileged and system capability integration

Consumer configuration
  unrelated host and user policy
```

### Home Manager responsibilities

The Home Manager module owns user and session-level shell integration, such as:

- shell enablement;
- the user package and runtime closure;
- systemd `--user` integration;
- user shell configuration;
- theme and configuration materialization;
- IPC-facing user tooling;
- user-owned state paths.

The Home Manager module must not hide privileged mutation or system-wide
configuration.

### NixOS responsibilities

The NixOS module is for capabilities that genuinely need system authority,
such as:

- declarative PAM service declarations;
- system polkit capability or integration;
- other privileged capability declarations proven necessary by later contract
  audits.

The NixOS module must remain optional when the core shell can operate without a
system-level capability.
One optional security or host integration must not make the broad NixOS module
mandatory for every consumer.

Opinionated defaults introduced during implementation must remain overridable,
using `lib.mkDefault` where appropriate.

### Security and session ownership

Security and session ownership are not presentation feature selection.
The existing `programs.omanixy.features` graph may select a notification-send
client capability, but it must not select ownership of a lock service, polkit
agent, idle manager, or notification daemon.

The foundation model has independent dimensions:

| Dimension | Question | Default |
| --- | --- | --- |
| Presentation | Does pinned Quattro contain the UI? | upstream evidence only |
| Session ownership | Which component owns lock, polkit agent, idle, or notification daemon? | consumer or external |
| System capability | Which host APIs or privileged services are available? | consumer NixOS policy |
| Compatibility | Is the contract exact, adapted, omitted, or blocked? | ledger classification |
| Support state | Is it supported, experimental, omitted, or blocked? | blocked until promoted |
| Evidence | Which validation level has passed? | static audit for the foundation |

The Home Manager module owns user and session integration.
The NixOS module owns declarative PAM, polkit, and other privileged system
capabilities when a later layer proves they are required.
The core shell must remain usable without importing the NixOS module.

Native Quattro security ownership is an explicit opt-in and starts
experimental.
Consumer-owned lock, polkit agent, idle manager, and notification daemon
remain safe defaults.
Omanixy does not kill or disable an unknown external owner to make an opt-in
surface work.
Known declarative conflicts may produce a diagnostic or assertion, while
runtime registration failure must remain bounded and observable.

The security contract and promotion gate are recorded in
[`docs/decisions/0005-quattro-security-session-boundary.md`](decisions/0005-quattro-security-session-boundary.md).

## Public Nix API contract

The obvious minimal Home Manager entry point is:

```nix
{
  inputs.omanixy.url = "github:atqamz/omanixy";

  # ...

  imports = [
    inputs.omanixy.homeManagerModules.default
  ];

  programs.omanixy.enable = true;
}
```

Consumers that need system-level integration also import:

```nix
{
  imports = [
    inputs.omanixy.nixosModules.default
    inputs.omanixy.homeManagerModules.default
  ];
}
```

The public flake outputs are `homeManagerModules.default`,
`nixosModules.default`, `packages.${system}.omanixy-shell`, and meaningful
runtime checks.

The option design must provide:

- one minimal and obvious enable path;
- useful opinionated defaults that remain overridable;
- no need to copy internal modules into consumer configurations;
- no one-option-per-QML-property explosion;
- a structured, upstream-compatible shell configuration escape hatch;
- a clear separation between Omanixy-owned behavior and upstream passthrough
  configuration.

The conceptual shape of the structured escape hatch is:

```nix
programs.omanixy = {
  enable = true;

  shell.config = {
    # upstream-compatible structured configuration
  };
};
```

The implementation issues must avoid freezing transient QML details as the
public API.

## Runtime concept

The eventual runtime flow is:

```text
reviewed Omarchy Quattro source
              +
     tested Quickshell pairing
              │
              ▼
     omanixy-shell.service
       under systemd --user
              │
              ▼
       graphical user session
              │
              ▼
    NixOS-provided capabilities
```

The service name `omanixy-shell.service` describes the runtime component.
It does not redefine the repository as only a shell package.
Issue #2 established the runtime lifecycle and pinned pairing.
This branch extends that baseline with the immutable compatibility view,
feature closure, and audited adapters described below.

The upstream shell source should remain pinned and read-only in the Nix store
where technically possible.
Runtime-writable state must be deliberately materialized outside the store.
`OMARCHY_PATH` may be an intentional source compatibility interface without
emulating the complete Omarchy filesystem.

For the pinned Quattro revision, the runtime uses an immutable compatibility
view because some reachable consumers construct absolute
`OMARCHY_PATH/bin/...` paths.
The view contains only the pinned source files required by the supported
runtime graph, ten narrow compatibility patch sites, the safe fallback
configuration, the audited default menu, and the helper surface.
It preserves `passthru.omarchySource` as the exact source identity and exposes
the view separately as `passthru.omarchyCompatibilityRoot`.
It does not copy the upstream `bin/` tree or make the store mutable.

## Compatibility boundary

A compatibility adapter is justified only when a supported upstream consumer
requires an observable external contract that native NixOS or Quickshell does
not provide directly.
The adapter must be narrow, traceable to that consumer, and tested for its
shell-facing behavior.

The decision order is:

1. use a native NixOS or Quickshell capability;
2. implement a narrow adapter matching the required contract;
3. contribute a portability improvement upstream;
4. carry a minimal downstream source patch only as a last resort.

A downstream QML patch requires documented justification, proof that native
integration and a narrow adapter are insufficient, minimal scope, focused
regression coverage, and an explicit relationship to the pinned source.
A narrow adapter is not a fork of the presentation layer.

The compatibility view and default menu are review surfaces, not a general
Omarchy filesystem or CLI.
Every baseline menu action must resolve to a native capability, an audited
adapter, or an explicit host session action.

See [porting-principles.md](porting-principles.md) for the compatibility
taxonomy and patch rules.

## Flake output policy

The flake must expose a real public output only when it has a consumer need:

- `homeManagerModules.default` is contracted as the public user integration
  output;
- `nixosModules.default` is contracted as the public privileged/system
  integration output;
- `packages.${system}.omanixy-shell` provides direct runtime and IPC
  consumption;
- `checks.${system}` covers evaluation, closure, service, ownership, IPC, and
  pin invariants;
- a standalone Omanixy CLI is not part of the architecture contract.

An internal runtime or IPC executable may exist when the runtime requires it.
That does not justify a broad CLI for symmetry.

## Generic public boundary

Public modules must not depend on `atqamz/universe`, Atqa-specific dotfiles,
`sfx14`, `pavg15`, Hand, `/home/atqa`, local checkout paths, personal
applications, personal keybindings, or machine-specific GPU policy.

Universe is a downstream consumer and validation environment.
It is not an architecture authority or an Omanixy dependency.

Omanixy does not own a complete Omarchy distribution, an Arch compatibility
universe, or complete Hyprland configuration.
The full non-goal list is in [project.md](project.md).

## Later issue ownership

The architecture predecessor intentionally leaves implementation to the
following work:

- #2 selects and validates the exact Quattro and Quickshell runtime pair and
  implements the user service;
- #3 defines the shell contract audit and compatibility ledger with traceable
  adapters;
- #4 handles lock, PAM, polkit, idle, notification, and session security;
- #5 defines SemVer and release automation;
- #6 proves standalone reuse and migrates Universe downstream.
