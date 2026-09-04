# ADR 0007: Portable Omarchy Host Contract

## Status

Accepted for Omanixy v0.2.

## Context

Omanixy v0.1 proves the Quattro runtime and Nix-native host adapters, but its
compatibility model mixes semantic capabilities, helper spellings, runtime
dependencies, source mutations, and presentation feature selection.

The v0.2 boundary keeps one ownership rule:

```text
Omarchy owns presentation.
NixOS owns the operating system.
Omanixy owns the boundary.
```

The Host Contract describes portable semantic operations at that boundary. It
is not the complete Omarchy CLI, an Arch compatibility layer, or a generic
command-execution protocol.

## Decision

### Capability identity

`capabilityId` is semantic identity, not command spelling. It is mechanically
derived as:

```text
<semanticDomain>.<operation>
```

`semanticDomain` is one lower-case segment. `operation` is one or more
lower-case dot-separated semantic segments; hyphens may occur inside a
segment. The ID is never independently authored.

Examples:

```text
application.activate
audio.default-output.set
network.band.query
network.band.set
session.suspend
```

#27 may discover which operations exist in the frozen graph, but it does not
choose a second naming policy for the same semantic operation. Any proposed ID
that cannot be derived by this rule is an architecture change owned here, not
an implementation-local choice.

`canonicalRoute` stores the reviewed route tokens after `omarchy`.
`flatBackingBinary` stores an exact `omarchy-*` compatibility binding when the
frozen consumer requires one, otherwise JSON `null`. Route or filename drift
does not change semantic identity by itself.

Every portable capability has one execution class:

```text
query
mutation
interactive
```

Long-running watcher and service lifecycle is not a canonical request/response
Host Contract operation.

### Crossing taxonomy

Every audited first-party Quattro-to-host crossing has exactly one `kind`:

```text
native-api
host-contract
declarative-host-integration
state-contract
trusted-extension
distribution-policy
internal-provider-seam
```

`kind`, `transport`, `capabilityId`, `disposition`, and `supportState` are
orthogonal. `capabilityId` is required for `host-contract` and is explicit JSON
`null` for every other kind. `supportState` is one of `supported`,
`experimental`, `omitted`, `blocked`, or `not-applicable`.

Trusted user menu commands and third-party QML/plugins stop at
`trusted-extension`; their arbitrary command strings do not expand the
first-party Host Contract. Immutable Omanixy-shipped actions remain first-party
review surface.

Good native APIs remain native. PipeWire, NetworkManager, UPower, MPRIS,
StatusNotifier, Wayland/Hyprland, DesktopEntries/toplevel, PAM, polkit, logind,
and D-Bus are not wrapped in subprocesses for symmetry.

### Directionality

Quattro-to-host and host-to-Quattro are separate contracts:

```text
Quattro -> Host
  native APIs / Host Contract / declarative integration / state contracts

Host -> Quattro
  Quattro shell IPC
  canonical binding: omarchy shell ...
  flat compatibility: omarchy-shell
```

`omarchy-shell` is not a portable Host Contract capability and is never mixed
into the Quattro-to-host semantic adapter registry. #28 owns the physical
package separation, with host adapters forbidden from depending on shell IPC
or `quattroRuntimeRoot`.

### Process contract

The default process profile is `host-contract-v1`:

```text
0    success
1    domain or operation failure
2    invalid arguments or usage
69   packaged capability, runtime backend unavailable
124  Omanixy-owned deadline exceeded
127  unknown route or missing advertised backing executable
```

stdout is result data. Diagnostics go to stderr. Omanixy-owned timeout
termination is normalized to 124. A backend-unavailable code other than 69
requires explicit pinned evidence in the capability row.

Portable commands never shell into `sudo`. Their privilege model is either
`unprivileged` or `authorized-runtime-api`. Privileged capability is provisioned
declaratively and mediated by the appropriate authorization/session API. This
preserves the architecture and security ownership established by #1 and #4;
normalizing bindings does not widen privileged runtime authority.

### State ownership

| Class | Owner / path |
| --- | --- |
| Immutable upstream source | `omarchySource` in the Nix store |
| Immutable selected runtime | `quattroRuntimeRoot` in the Nix store |
| User configuration/extensions | `~/.config/omarchy/*` |
| Upstream-compatible runtime/presentation state | `~/.local/state/omarchy/*` |
| Omanixy-private state/diagnostics | `~/.local/state/omanixy/*` |
| Host policy/services | NixOS/Home Manager declarations |

Runtime commands do not write to the Nix store. UI actions do not imperatively
mutate Nix-owned policy while presenting it as declarative configuration.
`~/.local/state/omanixy/capabilities.json`, if retained, is internal state and
is not a Quattro portable ABI.

### Authoritative data

| File | Authority |
| --- | --- |
| `upstream/host-contract.json` | Semantic portable Host Contract capabilities |
| `upstream/quattro-host-crossings.json` | Frozen upstream and post-overlay first-party crossings |
| `upstream/portability-overlay.json` | Remaining Omanixy source mutations/provider seams |
| `upstream/host-contract.schema.json` | Shared machine schema |

#26 introduces `upstream/host-contract.json` as `registryState = schema-only`
with no capability rows. This records the ontology without claiming that the
unfrozen v0.2 graph has already been audited.

#36 freezes the compatibility tuple. #27 then creates and populates
`quattro-host-crossings.json` and `portability-overlay.json`, populates semantic
Host Contract rows, and changes the registry to `authoritative` only when its
coverage is complete for that tuple. Empty pre-audit crossing/overlay files are
not created because they would falsely assert an empty graph.

The v0.1 `upstream/compatibility-contracts.json` remains authoritative for
existing v0.1 build/runtime wiring until #27 migrates useful evidence. It must
not remain a second semantic authority afterward. `upstream/porting-matrix.yaml`
likewise becomes a generated or validated maintainer summary where practical.
The mixed presentation/capability concerns in `upstream/shell-baseline.json`
are physically cleaned up by #34.

### Derivation direction

```text
presentation feature selection
        ↓
semantic Host Contract/native capability requirements
        ↓
host/backend capability registry
        ↓
Nix packages/services/runtime closure
        ↓
generated command set and flat compatibility bindings
```

Independent helper allowlists, helper-to-capability maps, command-availability
lists, and runtime dependency lists are retired once this model can derive
them.

### Schema and compatibility tuple

`schemaVersion` versions Omanixy's data model. It is not an upstream Omarchy
ABI and is not a compatibility tuple. It changes when required fields, field
meaning, or closed vocabulary change incompatibly.

The separate compatibility tuple contains exact identities for:

```text
Omarchy
Quickshell
nixpkgs
Home Manager
```

#36 owns tuple selection. Crossing and overlay rows carry that exact tuple.
Host Contract upstream evidence also binds asserted route/behavior evidence to
an exact tuple.

Changing a tuple component, backend implementation, canonical route, or flat
binding does not by itself change `schemaVersion` or `capabilityId`. Semantic
behavior drift updates the contract/evidence; a new ID exists only for a
different semantic operation.

### Omarchy router metadata

Router metadata is a machine directive and is allowed only in this exact line
shape:

```text
# omarchy:<key>=<value>
```

`<key>` is exactly one of:

```text
group
name
summary
args
examples
alias
aliases
requires-sudo
hidden
```

The line starts exactly with `# omarchy:`, uses a mandatory `=`, and contains
no carriage return, newline, or tab in the value. `requires-sudo` and `hidden`
accept only `true` or `false`. This is not a general narrative-comment
exception. #28 owns wiring this grammar into the source checker and validating
route/alias collisions and values.

## Migration

```text
#26 ontology/schema
  ↓
#36 immutable compatibility tuple
  ↓
#27 authoritative crossings + semantic registry + overlay
  ↓
#28 canonical router/package topology
  ↓
#29-#33 domain convergence
  ↓
#34 duplicate-ledger/overlay cleanup
  ↓
#35 conformance + behavioral closure
```

## Consequences

Implementation after #26 has one answer for semantic identity, crossing kind,
process status, privilege, directionality, state ownership, source authority,
and versioning. The schema closes those decisions without creating a generic
execution DSL or full Omarchy CLI model.
