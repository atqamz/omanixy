# Standalone consumer fixture

This directory is intentionally written like a small third-party configuration.
It has no dependency on Universe, machine-specific host names, personal paths,
or private configuration.

The fixture uses `path:../..` for the Omanixy flake input so CI evaluates the
exact checkout under review. A real consumer should use a reviewed release or
repository revision instead, for example:

```nix
inputs.omanixy.url = "github:atqamz/omanixy/v0.1.0";
```

Before the first public release exists, pin a reviewed commit instead of a
floating branch.

`home.nix` demonstrates the safe default ownership model: Omanixy owns the
Quattro shell service, Mako remains the notification daemon, native lock,
polkit-agent, idle, and notification-daemon ownership stay disabled, clipboard
presentation is omitted, and an upstream shell plugin is explicitly disabled
through `programs.omanixy.shell.config`.

`configuration.nix` demonstrates NixOS-owned host capabilities and the system
half of the optional native-lock handshake. The integrated NixOS configuration
in `flake.nix` enables the matching Home Manager lock option, proving that the
NixOS and Home Manager modules compose without making the NixOS module a
requirement for the safe standalone Home Manager case.

Run the fixture directly with:

```text
nix flake check --show-trace --print-build-logs --no-write-lock-file ./examples/standalone
```

The root `just check` command runs this automatically.
