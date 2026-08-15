# Upstream

Omanixy attributes the presentation source to
[`basecamp/omarchy`](https://github.com/basecamp/omarchy).
The repository currently pins release `v3.8.4` at revision
`8fcc9d6048af4cb0e3af8512c78049857a3b53dd`.

That revision is the current repository source baseline.
This architecture change does not claim that it is a validated runtime
Quattro and Quickshell compatibility pair.
The actual Quattro runtime revision and Quickshell pairing belong to issue #2.

## Pinning policy

Runtime and release inputs must use exact immutable revisions.
Mutable branch heads may be inspected during research, but they are never
release inputs.

An upstream upgrade requires a dedicated GitHub Issue that records:

- the exact Omarchy revision and source date;
- the exact or deliberately selected Quickshell revision;
- the contracts affected by the change;
- the compatibility and regression checks performed;
- the Omanixy impact and release decision.

Do not let a routine `nix flake update` silently change the supported shell
behavior.
Ports use the current recorded revision until that explicit upgrade issue
changes the pin.

## Quattro compatibility pair

The target source model is:

```text
reviewed Omarchy Quattro revision X
              +
     tested Quickshell revision Y
              ↓
         Omanixy release
```

The pair is one auditable compatibility unit.
Quickshell compatibility must be tested independently of source changes because
the stable package available from Nixpkgs is not automatically suitable for
every Quattro revision.

Issue #2 owns selecting and testing the concrete pair.
Until that work lands, metadata must not invent a Quattro SHA, claim runtime
validation, or repin this repository to a moving `quattro` branch.

## Source consumption

The intended runtime consumes the reviewed upstream shell source as a
source-only flake input where technically possible.
Omanixy should run it from a read-only Nix store path rather than vendor a
second QML tree.
Runtime-writable configuration and state must be materialized outside the
store.

An `OMARCHY_PATH` value pointing at an immutable Nix store source can be an
intentional compatibility interface.
It does not authorize emulating the complete Omarchy filesystem.

## Porting ledger

`upstream/porting-matrix.yaml` is the future compatibility ledger.
It is currently empty because issue #3 owns the contract audit and must add
traceable entries from the supported upstream source.
An empty ledger is more truthful than an inventory of unverified features.

See [porting-principles.md](porting-principles.md) for the `exact`, `adapted`,
`omitted`, and `blocked` taxonomy.
