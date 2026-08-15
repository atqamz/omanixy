# Omanixy

> Omarchy UX. NixOS ownership.

Omanixy brings the Omarchy Quattro desktop experience to NixOS using
composable NixOS and Home Manager modules.

It consumes the upstream Omarchy shell while keeping packages, services,
authentication, configuration, and system ownership Nix-native.

Omanixy is an independent community project.
It is not an official Basecamp project, is not endorsed by Basecamp, and is
not an Omarchy distribution.
See [Basecamp's Omarchy project](https://github.com/basecamp/omarchy) for the
upstream shell source and attribution.

## Ownership

The architecture is intentionally narrow:

- Omarchy owns Quattro's presentation and shell UX.
- NixOS owns the operating system and host capabilities.
- Omanixy owns the integration boundary between them.

Omanixy is not a Linux distribution, an Arch compatibility layer, an Omarchy
package manager, or a broad rewrite of Omarchy in Nix.
It does not provide pacman/AUR compatibility, a complete installer, a
complete Omarchy CLI, or a complete Omarchy Hyprland configuration.

The full product boundary is in [docs/project.md](docs/project.md), and the
component contract is in [docs/architecture.md](docs/architecture.md).

## Public Nix contract

The intended minimal consumer entry point is:

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

Integrations that need system-level capabilities will also import
`inputs.omanixy.nixosModules.default`.
The module outputs and `programs.omanixy.enable` option are the public
architecture contract for the implementation work that follows.
This repository baseline does not yet implement the runtime API.

Omanixy will expose opinionated but overridable defaults and a structured
upstream-compatible shell configuration escape hatch.
It will not turn every upstream QML property into a Nix option or require
consumers to copy internal modules.

## Documentation

- [Project boundary and non-goals](docs/project.md)
- [Architecture and module ownership](docs/architecture.md)
- [Porting and compatibility rules](docs/porting-principles.md)
- [Upstream pinning and upgrade policy](docs/upstream.md)
- [Contributor workflow](AGENTS.md)

Project workflow lives in `AGENTS.md`.

## Development

Run `just check` for the canonical verification command.

Run `just fmt` to format Nix files.

Run `just bootstrap` once to configure repository hooks.
