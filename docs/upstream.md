# Upstream

Omanixy attributes the presentation source to
[`basecamp/omarchy`](https://github.com/basecamp/omarchy).
The repository pins the reviewed Quattro source at revision
`f0020448ca87329199de7cb12f2015ebc4a3e5e7`.
The validated Quickshell pairing is revision
`28771c7c74b42e20afca0b1b63980cb46515537c`.
The pair and validation state are recorded in
[`upstream/omarchy.yaml`](../upstream/omarchy.yaml).

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

Issue #2 selected and tested the concrete pair.
The recorded pair is the release baseline until an explicit upstream upgrade
issue revalidates both inputs together.

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

`upstream/porting-matrix.yaml` contains only the durable runtime lifecycle
decision made by issue #2.
Issue #3 owns the comprehensive contract audit and all broader ledger
population.

See [porting-principles.md](porting-principles.md) for the `exact`, `adapted`,
`omitted`, and `blocked` taxonomy.
