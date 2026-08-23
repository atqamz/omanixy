# Omanixy

> Omarchy UX. NixOS ownership.

Omanixy is an independent Nix-native integration layer for the Omarchy
Quattro desktop shell.

It consumes reviewed upstream Quattro presentation code and makes it usable as
a composable NixOS/Home Manager integration without turning a consumer's
machine into an Arch compatibility environment.

## What Omanixy is

The ownership model is intentionally small:

```text
Omarchy owns presentation.
NixOS owns the operating system.
Omanixy owns the integration boundary.
```

Omanixy provides the pinned Quattro/Quickshell runtime, Home Manager user
service, configuration and writable-state boundary, capability adapters,
optional NixOS system integrations, public compatibility metadata, and tests.

The public entry points are:

- `homeManagerModules.default` for user/session integration;
- `nixosModules.default` for optional privileged/system capabilities;
- `packages.${system}.omanixy-shell` for the packaged runtime and IPC surface;
- `programs.omanixy.*` options for consumer configuration.

Supported flake systems are `x86_64-linux` and `aarch64-linux`.

## What Omanixy is not

Omanixy is not a Linux distribution, Omarchy installer, Arch compatibility
layer, package manager, complete Omarchy CLI, complete Omarchy Hyprland
configuration, or independent fork of Quattro's presentation layer.

It does not provide pacman/AUR compatibility and does not copy the upstream
`bin/` tree into a mutable Omarchy filesystem.
Host hardware, users, applications, compositor policy, keybindings, firewall,
boot, power policy, and unrelated desktop services remain consumer-owned.

Omanixy is an independent community project. It is not an official Basecamp
project and is not endorsed by Basecamp. Omarchy remains the upstream source
and presentation authority: [basecamp/omarchy](https://github.com/basecamp/omarchy).

See [the project boundary](docs/project.md) and
[architecture](docs/architecture.md) for the complete ownership contract.

## Prerequisites and session assumptions

Omanixy targets Linux graphical sessions running the pinned Quattro shell on
Quickshell.
The current runtime depends on Wayland and Hyprland-facing APIs used by the
reviewed upstream source.

The Home Manager service joins `graphical-session.target` and expects the user
manager to receive the active graphical-session environment, including values
such as `WAYLAND_DISPLAY`, `XDG_RUNTIME_DIR`,
`HYPRLAND_INSTANCE_SIGNATURE`, and `DBUS_SESSION_BUS_ADDRESS`.
UWSM is the reviewed session model and is recommended; an equivalent setup is
acceptable only if it establishes the same user-manager environment and
lifecycle contract.

Omanixy does not start or own a complete compositor session for you.
A consumer should already have a working NixOS/Home Manager Wayland desktop.
Common shell surfaces also expect the corresponding NixOS-owned capabilities,
such as PipeWire, NetworkManager, BlueZ, UPower, and power-profiles-daemon,
when those feature groups are used.

## Install with flakes

Pin a reviewed release when one exists:

```nix
{
  inputs.omanixy.url = "github:atqamz/omanixy/v0.1.0";
}
```

Before the first public release, pin a reviewed commit rather than a floating
branch:

```nix
{
  inputs.omanixy.url = "github:atqamz/omanixy/<reviewed-commit>";
}
```

A standalone Home Manager consumer can import only the public Home Manager
module:

```nix
{
  imports = [ inputs.omanixy.homeManagerModules.default ];

  programs.omanixy.enable = true;
}
```

The NixOS module is not required for the safe core shell.
Import it when using a system-level Omanixy capability:

```nix
{
  imports = [ inputs.omanixy.nixosModules.default ];

  programs.omanixy.security.pam.password.enable = true;
}
```

When Home Manager is integrated through NixOS, import the Home Manager module
inside the user configuration as usual:

```nix
{
  home-manager.users.alice = {
    imports = [ inputs.omanixy.homeManagerModules.default ];
    programs.omanixy.enable = true;
  };
}
```

A complete, continuously evaluated third-party-style example lives in
[`examples/standalone`](examples/standalone).

## Minimal safe configuration

The minimal enable path uses Omanixy's safe defaults:

```nix
{
  programs.omanixy.enable = true;
}
```

Native session ownership for lock, polkit agent, idle management, and the
notification daemon is disabled by default.
Those responsibilities may remain with existing consumer services.

Feature groups can be narrowed without copying internal modules:

```nix
{
  programs.omanixy = {
    enable = true;
    features = [
      "audio"
      "launcher"
      "monitor"
      "network"
      "notification"
      "power"
      "screenshot"
      "weather"
    ];
  };
}
```

`core` is always selected internally.
Omitting a feature removes its presentation/runtime capability closure rather
than merely hiding a widget.

## NixOS vs Home Manager responsibilities

Home Manager owns user/session integration:

- `omanixy-shell.service` under `systemd --user`;
- the runtime package and command closure;
- selected presentation feature groups;
- shell configuration materialization;
- writable user state and theme seed;
- IPC-facing tools;
- optional session ownership such as native lock, polkit agent, idle manager,
  or notification daemon.

NixOS owns privileged/system capability declarations:

- the dedicated password PAM service for the optional native lock;
- the optional fingerprint PAM/fprintd capability;
- the system polkit capability used by an optional session agent.

The consumer still owns unrelated host policy.
Enabling one Omanixy system capability does not grant Omanixy authority over
login, users, compositor configuration, networking policy, or hardware setup.

## Feature and support matrix

The compatibility ledger in
[`upstream/porting-matrix.yaml`](upstream/porting-matrix.yaml) is the detailed
authority. The public support view is:

| Surface | Public state | Default | Ownership |
| --- | --- | --- | --- |
| Core Quattro runtime and user service | supported | enabled by `programs.omanixy.enable` | Omanixy/Home Manager |
| `audio`, `bluetooth`, `clipboard`, `launcher`, `monitor`, `network`, `notification`, `power`, `screenshot`, `weather` feature groups | supported within the audited compatibility closure | selected by default | Omanixy runtime + NixOS host capabilities |
| Native Quattro lock | experimental | off | opt-in Home Manager + NixOS password PAM |
| Fingerprint unlock | experimental | off | opt-in Home Manager + NixOS fingerprint capability |
| Native Quattro polkit agent | experimental | off | opt-in Home Manager + NixOS polkit capability |
| Native Quattro idle manager | experimental | off | opt-in Home Manager and requires native lock |
| Native Quattro notification daemon | experimental | off | opt-in Home Manager |
| Full Omarchy CLI/package-manager behavior | omitted | unavailable | upstream/non-goal |
| Unsupported Arch-only helpers and unaudited surfaces | omitted or blocked | unavailable | compatibility ledger |

`notification` in `features` is the client capability for sending
notifications. It does not select ownership of
`org.freedesktop.Notifications`.

Experimental session owners are intentionally independent options and remain
disabled unless the consumer explicitly chooses them.
Known declarative owner conflicts fail evaluation instead of being killed or
silently replaced at runtime.

## Optional security and session integrations

A native password lock requires both halves of the ownership handshake:

```nix
{
  programs.omanixy.security.pam.password.enable = true;

  home-manager.users.alice.programs.omanixy.security.lock.enable = true;
}
```

The Home Manager lock option intentionally fails with an actionable diagnostic
when enabled standalone because standalone Home Manager cannot provision the
required PAM service.

Fingerprint, polkit-agent, idle, and notification-daemon ownership have their
own independent options. Read the option descriptions and
[`docs/runtime.md`](docs/runtime.md) before enabling them.
They are experimental even when they are exercised by downstream dogfooding.

Do not intentionally run two owners of the same session role. In particular,
avoid pairing Omanixy's native notification daemon with Mako/Dunst/SwayNC/Fnott,
its native idle manager with Hypridle/Swayidle, or its native polkit agent with
another known Home Manager polkit agent.

## Shell configuration

`programs.omanixy.shell.config` is the structured upstream-compatible escape
hatch for Quattro's `shell.json` schema.
It is deliberately not expanded into one Nix option per QML property.

For example, a consumer can add an explicit disabled plugin while preserving
Omanixy's immutable safety floor:

```nix
{
  programs.omanixy.shell.config.disabledPlugins = [ "omarchy.bluetooth" ];
}
```

Omanixy always preserves the baseline blocked/disabled floor in generated
runtime state. A writable user config cannot revive a capability that was not
selected or a security surface that remains outside the chosen ownership
contract.

The generated config is seeded on first activation and then treated as
user-owned state. Exact known Omanixy-generated historical baselines may be
migrated; customized or malformed files are not silently rewritten into a new
policy.

## Theme and state ownership

Omanixy seeds Quattro runtime theme state under the user's writable state
boundary. That state belongs to Quattro presentation and is not a universal
source of truth for GTK, Hyprland, launchers, terminals, or application themes.

A consumer should own its palette policy and feed each owned surface explicitly.
Omanixy may provide integration adapters, but it does not absorb personal or
host-specific theme policy.

See [public adoption and downstream validation](docs/adoption.md) for the
ownership model used during downstream migration.

## Service lifecycle

Home Manager generates `omanixy-shell.service`.
The unit is part of and wanted by `graphical-session.target`, starts after that
target, runs `${runtime}/bin/omanixy-shell-runtime`, and uses systemd as the
only supervisor.

The reviewed defaults are:

- `Restart=on-failure`;
- `RestartSec=2s`;
- `TimeoutStopSec=10s`;
- five starts per 60-second start-limit window;
- immutable `OMARCHY_PATH` plus `QS_DISABLE_FILE_WATCHER=1` and
  `QS_NO_RELOAD_POPUP=1`.

These are ordinary module values and can be overridden through normal Nix
module priority when a consumer has a justified local policy.

## Troubleshooting

Start with the generated user unit:

```text
systemctl --user status omanixy-shell.service
journalctl --user -u omanixy-shell.service -b
```

Useful checks include:

```text
systemctl --user show-environment
systemctl --user cat omanixy-shell.service
```

If the shell starts outside the graphical session, verify that the user manager
received the active Wayland/Hyprland/D-Bus environment and that
`graphical-session.target` is active.

If an optional security/session integration fails evaluation, read the complete
assertion text before trying to bypass it. The assertions encode ownership
requirements such as paired PAM/polkit capability options and known conflicting
session daemons.

If a panel/backend is unavailable, compare the selected `features` against the
required NixOS host capability and the compatibility ledger before adding host
commands to `PATH`. Omanixy's runtime closure is intentionally hermetic.

More runtime detail is in [`docs/runtime.md`](docs/runtime.md).

## Upstream compatibility pinning

Omanixy does not follow Omarchy or Quickshell branch tips implicitly.
One reviewed Omarchy Quattro revision, Quickshell revision, and nixpkgs build
context form the tested compatibility unit.

The current exact revisions and upgrade rules are recorded in
[`docs/upstream.md`](docs/upstream.md) and [`upstream/omarchy.yaml`](upstream/omarchy.yaml).
The compatibility matrix records each audited surface as exact, adapted,
omitted, or blocked and carries its support state.

An upstream upgrade is dedicated compatibility work. It is not an incidental
result of a broad `nix flake update`.

## Upgrades and releases

Omanixy versions describe the Omanixy public API/support contract, not the
Omarchy version number.
Consumers should prefer reviewed SemVer tags once releases exist and update
pins deliberately.

The release process records the tested upstream pair and compatibility state in
the release context. The first public release remains gated on standalone
public usability rather than one personal workstation.

Release semantics, Conventional Commit rules, migration-note requirements, and
Release Please ownership are documented in [`docs/release.md`](docs/release.md).

## Public adoption evidence

The canonical third-party fixture is
[`examples/standalone`](examples/standalone), and its validation contract is
explained in [`docs/adoption.md`](docs/adoption.md).

`atqamz/universe` is a downstream dogfooding consumer. It validates Omanixy as
a normal flake/module dependency, but Universe is neither a public dependency
nor an architecture authority for Omanixy.
Machine-specific keybindings, layout, applications, themes, hardware policy,
and workflow integrations remain downstream.

## Development

Run the canonical verification:

```text
just check
```

It includes the root flake checks and the standalone consumer fixture.

Format Nix sources with:

```text
just fmt
```

Configure repository hooks once with:

```text
just bootstrap
```

Contributor architecture and workflow rules are in [`AGENTS.md`](AGENTS.md).
