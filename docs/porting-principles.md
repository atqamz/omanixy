# Porting Principles

Omanixy ports required external contracts, not an Omarchy implementation.
The question is what capability the supported Quattro shell needs, not which
upstream script happens to provide that capability on Arch.

## Decision order

When upstream assumes an Omarchy capability, decide in this order:

1. use a native NixOS or Quickshell capability directly;
2. implement a narrow compatibility adapter matching the required observable
   contract;
3. contribute a portability improvement upstream;
4. carry a minimal downstream source patch only as a last resort.

Native capabilities include the system services and APIs already owned by the
consumer's NixOS configuration, such as PipeWire, NetworkManager, BlueZ,
UPower, D-Bus, and declarative PAM or polkit integration where applicable.

Do not copy an Omarchy helper merely because the helper exists.
Trace every adapter to a supported upstream consumer and record its required
arguments, output, exit status, failure behavior, and ownership boundary.

## Compatibility taxonomy

Every audited compatibility item uses exactly one of these classifications:

- `exact` means NixOS or Quickshell provides the same observable contract
  required by the upstream consumer without a semantic workaround.
- `adapted` means Omanixy provides equivalent supported behavior through a
  narrow Nix-native integration or compatibility adapter.
- `omitted` means the feature is intentionally outside Omanixy's scope or is
  not applicable to the NixOS integration.
- `blocked` means the feature cannot currently be provided safely or
  correctly, and the limitation is documented.

The taxonomy describes compatibility, not stability.
A feature may be `adapted` and still be experimental, or `omitted` because
omission is the correct architecture rather than unfinished work.

Support state is a separate field from compatibility classification.
Every security and session-ownership entry records one of these support
states:

- `supported` means the surface is enabled by default or explicitly supported
  with the required evidence.
- `experimental` means the surface is explicit opt-in, has bounded failure
  behavior, and still lacks promotion evidence.
- `omitted` means Omanixy intentionally does not provide the surface.
- `blocked` means the surface is not reachable or is not safe to enable.

`maturity: audited` means the declared contract is recorded against pinned
consumer evidence, a deterministic upstream identity, and the contract
snapshot.
`maturity: validated` additionally requires focused behavioral evidence for
every applicable matrix case and a passing contract-closure check.
Neither maturity nor support state means that a security surface owns the
consumer's system policy.
It never means that an Omanixy implementation merely agrees with its own
tests, and it never upgrades an `adapted` entry to `exact`.
For `exact`, `omitted`, and `blocked` entries, the evidence proves the native
capability or the documented reachability boundary rather than an adapter
implementation.

The porting matrix is a compatibility ledger, not a percentage-complete
tracker.
The number of `exact` entries is never a project quality score.
Issue #2 records the narrow runtime source contracts needed to make the pinned
Quattro baseline auditable.
Issue #3 defines the comprehensive contract audit and ledger; this branch
implements the pinned baseline and its reviewed compatibility edges.

The contract scanner is a static pin-drift guard.
It records direct commands, dynamic command expressions, menu fields, absolute
helper paths, filesystem and environment contracts, native Quickshell imports,
service names, and security references from the pinned source roots.
Issue #4 adds a bounded list of exact lock, PAM, polkit, idle, notification,
and transitive helper source files.
Those files are audited as references only and are not copied into the runtime
compatibility view.
It intentionally excludes the complete upstream `bin/` tree while retaining a
narrow compatibility-bin view for the audited absolute helper paths that are
reachable from supported Quattro.
Behavioral adapter tests and live Wayland/Hyprland smoke are separate runtime
evidence and do not get replaced by static scanning.

## Adapters and downstream patches

A compatibility adapter is allowed only when a supported upstream component
needs an external contract that native NixOS or Quickshell cannot provide
directly.
It must be the smallest useful implementation and must preserve the shell's
observable contract.

A persistent downstream source patch requires:

- documented justification;
- an explanation of why native integration or an adapter was insufficient;
- minimal scope;
- focused regression coverage;
- an explicit relationship to the pinned upstream source.

Broad QML reimplementation or a continuously maintained presentation fork is
not a compatibility adapter.
Upstream presentation remains upstream-owned.

The current adapters remain Bash where their boundary is process invocation,
argv/stdout/stderr handling, bounded command timeouts, and small filesystem
transactions with explicit rollback.
Shared timeout and failure helpers keep those paths explicit, and focused
failure tests cover the stateful audio, network, display, power, clipboard,
and launcher mutations.
QML and JavaScript remain the structured layer for presentation state and
consumer parsing; no domain was split into a second language without a
specific parsing or state-management benefit.

## Ownership and reuse

NixOS owns host capabilities and privileged system configuration.
Home Manager owns user and session integration.
Omanixy owns the boundary and the narrow adapters required to connect them.
Consumers own unrelated machine and user policy.

Public modules must remain independent of `atqamz/universe`, Atqa-specific
dotfiles, `sfx14`, `pavg15`, Hand, `/home/atqa`, local checkout paths,
personal applications, personal keybindings, and machine-specific GPU policy.

The dependency direction is always:

```text
Omarchy
   ↓
Omanixy
   ↓
consumer NixOS and Home Manager configuration
```

Universe is a downstream consumer and validation environment.
It can reveal missing generic capabilities, but it is never a public Omanixy
dependency.

## Pinned source discipline

Every port and adapter must identify the pinned upstream source it supports.
Never silently copy behavior from a newer branch or release.
Upstream upgrades are dedicated work that re-audits affected contracts and
updates the ledger.
