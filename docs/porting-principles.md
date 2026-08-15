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

The porting matrix is a compatibility ledger, not a percentage-complete
tracker.
The number of `exact` entries is never a project quality score.
Issue #3 owns the real contract audit and matrix population.
The current empty `upstream/porting-matrix.yaml` is therefore intentional and
does not represent fabricated support claims.

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
Universe
```

Universe can dogfood Omanixy and reveal missing generic capabilities.
Those capabilities must be generalized before they become public Omanixy
behavior.

## Pinned source discipline

Every port and adapter must identify the pinned upstream source it supports.
Never silently copy behavior from a newer branch or release.
Upstream upgrades are dedicated work that re-audits affected contracts and
updates the ledger.
