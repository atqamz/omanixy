# ADR 0005: Quattro Security and Session Ownership Boundary

## Status

Accepted for the issue #4 foundation layer.

The security runtime remains blocked and unreachable after this decision.

## Context

The reviewed Quattro source contains lock, PAM, fingerprint, polkit, idle, and
notification behavior that crosses the presentation, user-session, and system
security boundaries.
The source is pinned to Omarchy
`f0020448ca87329199de7cb12f2015ebc4a3e5e7` and Quickshell
`28771c7c74b42e20afca0b1b63980cb46515537c`.
The NixOS policy source is pinned to nixpkgs
`241313f4e8e508cb9b13278c2b0fa25b9ca27163`.

The current Home Manager feature graph is a presentation selector with broad
defaults.
It is not a safe ownership control for security-sensitive session services.
The current `notification` feature selects the `notification-send` client
capability.
It does not own the `org.freedesktop.Notifications` service.

The pinned Quickshell process loads first-party Quattro service plugins and
third-party QML plugins as unsandboxed code in one primary process.
The pinned lock plugin is a keep-loaded service.
This makes native lock ownership a process and trust decision in addition to a
visual feature decision.

## Threat and trust boundary

NixOS owns system security policy, privileged capabilities, system services,
PAM files, polkitd, D-Bus system integration, accounts, and hardware policy.
Home Manager owns user and session integration.
Omanixy owns the declarative boundary and narrow adapters.
Omarchy owns Quattro presentation and its user-visible behavior.

Quickshell QML is trusted code in the session.
Third-party QML plugins share the primary process trust boundary and are not a
security sandbox.
A native lock therefore cannot claim process isolation from the other loaded
QML code.
It can only claim the upstream session-lock protocol and the failure behavior
that later validation proves.

No security integration may use a generic shell-interpolated command,
imperative `/etc` mutation, a setuid shortcut, a broad privileged helper, or a
command that silently changes a consumer's existing owner.

## Pinned contract findings

### Lock and session-lock protocol

`Service.qml` owns a `WlSessionLock` and creates a
`WlSessionLockSurface` for each real screen.
It does not request the lock until the password PAM file is present.
It delays acquisition for screen stabilization and keeps a pending request
while no usable screen exists.
It rechecks screen changes and uses `secure` state before starting the
fingerprint flow.

`ext-session-lock` state is retained by the compositor, not by the client
that requested it: once locked, the surface persists even if the requesting
client process exits or restarts.
A restarted shell process therefore cannot assume it still holds an
unreleased lock and cannot assume the previous lock is gone.
`omarchy-hyprland-session-locked` probes Hyprland monitor JSON and
`solitaryBlockedBy` to distinguish a locked monitor, an unlocked monitor, and
an indeterminate state, which is how a restarted client detects a stranded
lock from a prior process rather than tracking its own in-memory state.
The pinned recovery check retries twenty times at 500 ms and leaves an
indeterminate result unresolved.
This is a compositor-state detection and reacquisition contract for a
possibly-stranded lock, not proof that the original lock process is alive.

The lock reads the background through the current Omarchy state path and
blanks display and keyboard backlight through helper commands.
Display wake and clamshell handling are separate host-policy contracts.
Keyboard backlight is optional hardware behavior and cannot be a lock
precondition.

The password ABI is the PAM configuration name
`omarchy-lock-password`.
The fingerprint ABI is the PAM configuration name
`omarchy-lock-fingerprint`.
The plugin probes `/etc/pam.d/omarchy-lock-password` with a `FileView`.
It probes fingerprint support with a shell command that requires the
fingerprint PAM file, `fprintd-list`, and an enrolled finger for the current
`USER`.
Missing enrollment or missing `fprintd` is treated as unavailable.

The selected Quickshell `PamContext` uses the configured file name and user,
starts a PAM subprocess, runs an authentication conversation, calls
`pam_authenticate`, and ends the PAM handle.
It does not run a complete PAM account or session stack.
Password prompts are relayed through the QML conversation.
The lock increments a visible local failure count but has no local retry cap.

The fingerprint flow restarts after every non-success or error with a 250 ms
timer while fingerprint configuration remains true.
Repeated backend failure can therefore create a tight or effectively
continuous sequence of PAM and fprintd requests, excessive logs, and
authentication churn.
Layer 4 must add bounded attempts, backoff, backend-unavailable handling, and
a tested stop condition before fingerprint support can be promoted.
This foundation layer intentionally does not change the pinned source.

### PAM policy intent and NixOS strategy

The pinned Arch installer writes two files under `/etc/pam.d`.
Those writes are implementation details of the Arch installer and are not an
Omanixy architecture.

The password file intends to combine `pam_faillock`, `pam_systemd_home`,
`pam_unix` with `try_first_pass` and `nullok`, `pam_permit`, `pam_env`, and an
included account stack.
The fingerprint file intends to use required `pam_fprintd` authentication and
an included account stack.

The intentions do not justify copying the exact stack.
`nullok` would permit empty-password authentication and is not accepted for a
screen-lock contract.
`try_first_pass` couples module ordering and conversation state.
`pam_systemd_home` has host-specific behavior and must not be inherited
accidentally.
`pam_faillock` changes lockout state and requires a deliberate policy for
preauth, auth failure, success reset, storage, and recovery.
`pam_env` is not needed to authenticate a lock request.
The account include is outside the current Quickshell `PamContext` ABI because
the context calls `pam_authenticate` only.

The later PAM layer will use dedicated explicit
`security.pam.services.<name>.text` declarations for the two service names.
The text will be a complete auth-only stack with no implicit default rules or
unrelated login mechanisms.
The experimental generated `rules` API is not selected because nixpkgs warns
that its built-in ordering can change and hard-coded ordering can lock out or
open the system.
The later layer must make any `pam_faillock`, home authentication, or
fingerprint policy explicit and test its failure behavior.
No PAM service is enabled by this ADR.

### Polkit

NixOS already owns `polkitd`, the D-Bus/system integration, and the
`polkit-1` PAM service when `security.polkit` is enabled.
Omanixy must not provide a second daemon or duplicate that PAM service.

The pinned Quattro source provides a user-session `Quickshell.Services.Polkit`
agent at `/org/omarchy/PolkitAgent`.
It observes registration state, starts and cancels authentication flows, and
detects fingerprint prompts from the existing `polkit-1` PAM file.
It also checks the pinned laptop-lid helper before exposing a fingerprint
flow.

The future agent is explicit opt-in and session-owned.
A known declarative agent conflict may warn or assert.
An unknown external agent must not be killed or disabled.
Registration failure must be diagnostic, bounded, and free of a restart loop.

### Idle and DPMS

The pinned idle service uses Quickshell `IdleMonitor` with
`respectInhibitors: true`.
It launches the Omarchy screensaver, tracks its Hyprland window lifecycle,
calls the lock helper, wakes display state, and persists a stay-awake marker.
It also depends on raw Hyprland events and wall-clock timer behavior around
suspend and resume.

Omanixy must not import unrelated Omarchy screensaver or hardware policy just
to make idle detection work.
The future idle owner must declare a valid lock provider before enabling
lock-on-idle.
It must not knowingly run beside another declaratively managed idle owner.
Unknown external consumers remain the consumer's responsibility.

### Notifications

The pinned notification plugin creates a Quickshell
`NotificationServer` and therefore owns the
`org.freedesktop.Notifications` service.
It tracks replacement IDs, actions, DND state, persistent history, popup
state, and image state across shell reloads.

The existing `notification-send` capability is a client contract.
Its adapter invokes the host notification client and does not install,
configure, supervise, or own a notification daemon.
The weather and screenshot consumers do not change that boundary.

The future Quattro notification daemon is explicit opt-in with external or
consumer ownership as the default.
Known declarative conflicts may be diagnosed where reliable.
Omanixy must never kill `mako`, `dunst`, `swaync`, or an arbitrary daemon.

## Decisions

### Independent ownership and support model

Security architecture records these dimensions independently:

| Dimension | Meaning |
| --- | --- |
| Presentation | Pinned upstream UI and service source exists. |
| Session ownership | Consumer, external service, or explicitly selected Quattro owner. |
| System capability | PAM, fprintd, polkitd, D-Bus, Wayland, Hyprland, and host APIs. |
| Compatibility | `exact`, `adapted`, `omitted`, or `blocked`. |
| Support state | `supported`, `experimental`, `omitted`, or `blocked`. |
| Validation evidence | Static, hermetic, offscreen QML, nested compositor, or live manual/hardware. |

The current issue #4 security surfaces are `blocked` for both compatibility
and support state because they are not reachable in the shipped runtime.
Their planned native integrations are `adapted` and initially `experimental`.
This distinction is recorded in `upstream/porting-matrix.yaml`.

### Native lock topology

The initial native Quattro lock topology is in-process in the primary
Omanixy-managed Quickshell process.
This follows the pinned `Service.qml`, preserves its existing
`WlSessionLock`, screen stabilization, IPC, and stranded-lock recovery
semantics, and avoids a downstream presentation fork.

A dedicated lock process is rejected for the initial implementation.
It would require a separate Quickshell process, a state and IPC bridge,
duplicated shared QML state, and a new ext-session-lock recovery model.
It would also create a larger divergence from the pinned source before the
failure behavior is understood.
The decision accepts the shared process trust boundary while native lock is
experimental.
Promotion requires tests for shell crash and restart, an orphaned session
lock, no-screen startup, screen changes, monitor changes, lock status IPC,
and bounded recovery.

### Lock provider and keybinding boundary

The conceptual provider model has a consumer or external provider by default
and an explicitly selected Quattro native provider.
Provider selection is separate from keybinding policy.
Omanixy does not take ownership of a consumer's Hyprland keybinding.

`omanixy-shell` remains the narrow Quattro IPC client defined by issue #3: it
forwards a target and method to `quickshell ipc -n -p "$OMARCHY_PATH/shell"
call -- <target> <method> [args...]` and adds no provider logic of its own.
The pinned upstream `bin/omarchy-shell` already forwards the same way, and the
pinned idle `Service.qml` already calls `omarchy-shell lock isLocked` as a
plain target/method pair under that existing generic contract.
A future `lock lock` call is the same kind of plain IPC value, not a new
dispatcher operation, and requires no new code in `omanixy-shell`.
Provider selection, machine-readable status, and a non-zero
`provider-unavailable` result are the responsibility of whatever QML-side
service implements the `lock` IPC target, not of the IPC client.
An external provider contract, if needed, uses an explicit executable path and
fixed argv values rather than shell interpolation.
Layer 1 does not add or advertise this runtime operation.

### System and session ownership

The NixOS module may later declare only the PAM and system capability pieces
that require system authority.
The Home Manager module may later declare user service, session, provider, and
agent integration.
The core shell remains valid without the NixOS module.
Fingerprint capability, polkit agent ownership, idle ownership, and
notification daemon ownership remain independently optional.

## Promotion gate

No issue #4 security surface may move from blocked to experimental or from
experimental to supported without evidence appropriate to its risk.

The evidence ladder is:

1. Static pinned-source contract audit and compatibility ledger review.
2. Hermetic helper, metadata, closure, and failure tests.
3. Offscreen QML and Quickshell contract tests.
4. Nested compositor tests for Wayland session-lock, Hyprland events, and
   recovery.
5. Live manual and hardware validation for PAM, fingerprint, lid, display,
   keyboard backlight, polkit registration, idle, DND, and notification state.

Layer 1 provides only the first two levels where they can be hermetic.
It does not acquire a session lock, authenticate against the controlling
session, suspend, replace a compositor, register a polkit agent, own a
notification daemon, or start an idle manager.

## Consequences

- The safe default remains consumer or external ownership for every security
  and session surface.
- The current presentation feature graph cannot silently enable security
  ownership.
- PAM service names remain stable ABI candidates without installing files in
  this layer.
- The lock topology is simple and upstream-faithful while its shared trust
  boundary remains explicit.
- The notification client capability cannot be mistaken for daemon ownership.
- Hardware-specific wake, backlight, lid, and monitor behavior stays optional
  and outside the lock security core.
- The contract ledger carries both current reachability and future promotion
  evidence without pretending that static understanding is support.

## Planned stack

| Layer | Branch | Scope |
| --- | --- | --- |
| 1/8 | `4-01-security-contracts` | Security audit, threat model, ownership architecture. |
| 2/8 | `4-02-security-pam` | Declarative NixOS PAM and system capability foundation. |
| 3/8 | `4-03-security-lock` | Lock provider and password-only experimental Quattro lock. |
| 4/8 | `4-04-security-fingerprint` | Optional fingerprint capability and bounded retry behavior. |
| 5/8 | `4-05-security-polkit` | System polkit capability and Quattro session-agent ownership. |
| 6/8 | `4-06-security-idle` | IdleMonitor, inhibitors, lock dependency, and DPMS ownership. |
| 7/8 | `4-07-security-notifications` | Notification daemon ownership, DND, history, and conflicts. |
| 8/8 | `4-08-security-recovery` | Failure and recovery matrix and final promotion gate. |

Only the final layer may promote the complete issue #4 architecture or close
the issue.

## Layer 2 implementation note

`4-02-security-pam` implements the `security.pam-password` ledger entry only,
as `programs.omanixy.security.pam.password.enable` in the NixOS module.
Disabled by default, it declares exactly one
`security.pam.services."omarchy-lock-password".text`: a single explicit
`auth required ${config.security.pam.package}/lib/security/pam_unix.so` line,
using the public `security.pam.package` option rather than the
`internal = true` `pam_unixModulePath` option, matching how nixpkgs itself
resolves the module's absolute store path since NixOS has no FHS
`/lib/security/`.

The pinned Quickshell `PamContext` (`shell/plugins/lock/Service.qml`) calls
only `pam_start_confdir`/`pam_start`, then `pam_authenticate` once, then
`pam_end`; it never calls `pam_acct_mgmt`, `pam_open_session`,
`pam_close_session`, `pam_chauthtok`, or `pam_setcred`.
The generated service therefore carries only the `auth` phase; `account`,
`session`, and `password` rules are dead weight this ABI never consumes.

Two of the pinned Arch stack's modules are deliberately not carried over:

- `pam_faillock` is not adopted here. Lockout policy is a cross-cutting
  failure and recovery decision - it changes what "locked out" means for the
  whole session, not just this one service - and belongs to the layer 8
  failure and recovery matrix with its own explicit tests, not as an implicit
  side effect of declaring the password capability.
- `pam_systemd_home` is not adopted. The implemented password backend is
  `pam_unix` against ordinary shadow-backed local Unix accounts; systemd-homed
  authentication is not implemented by this layer. This is a support-scope
  omission, not a host-specific claim: a NixOS machine can have `systemd-homed`
  available while a given account is still an ordinary shadow-backed user, so
  this module makes no claim that the password capability, once enabled, can
  authenticate every account backend present on the machine. Extending the
  supported backend set is a consumer gate for whichever layer wires up the
  native lock, not a decision made here.

`nullok` and `pam_permit.so` remain rejected outright: neither is an
acceptable authentication-success path for a screen lock.

`security.pam.services.<name>` has an independently configurable `enable`
(default `true`, filtered out of `/etc/pam.d` generation entirely when
`false`) alongside a `text` typed `nullOr lines`, and `lines` merges ordinary
same-priority definitions by newline concatenation. An unrelated normal
module could otherwise disable the service outright, or extend its
authentication stack, while the Omanixy capability still reported `true`.
This layer's `config` sets both `enable` and `text` via `lib.mkForce`, so
while the option is enabled Omanixy owns the service's enabled state and its
entire text atomically, and a competing normal-priority definition of either
field is discarded rather than merged or honored.

`lib.mkForce` alone is not sufficient against an equally strong competing
definition: nixpkgs' `lines` merge type combines multiple definitions at the
same priority by concatenation rather than raising a conflict, so a second
`lib.mkForce` on `text` from another module would silently extend the
authentication stack even though Omanixy's own `mkForce` is present. This
layer adds an `assertions` entry that checks the *final resolved*
`security.pam.services."omarchy-lock-password"` matches the exact
Omanixy-owned contract (`enable == true` and `text` equal to the one auth
line) whenever the option is enabled, so an equal-or-stronger override fails
the build closed instead of silently composing. NixOS only runs assertion
checking when `config.system.build.toplevel` is evaluated, so every fixture
this layer uses to test this invariant forces that specific attribute rather
than reading `environment.etc` directly.

`pam_unix.so` shells out to a setuid `unix_chkpwd` helper to read the shadow
database; nixpkgs's own `security/pam.nix` unconditionally registers
`security.wrappers.unix_chkpwd` (setuid root, sourced from the same pinned
`linux-pam` package) independent of which PAM services are enabled, so this
layer neither vendors nor duplicates that privileged helper.

Build fixtures in `flake.nix`, checked by `security-pam-composition` and
`security-pam-capability`, prove: the generated file is byte-identical
whether or not an unrelated normal-priority `text` definition is present; the
generated file is byte-identical and the service stays enabled when an
unrelated normal-priority `enable = false` is present; and a second,
equal-priority `lib.mkForce` on `text` fails `config.system.build.toplevel`'s
evaluation closed rather than silently composing. A consumer who wants a
different policy for this service must disable this option rather than add
to it; this layer adds no `extraConfig` escape hatch, no imperative conflict
resolution, and does not delete or mutate any other file.

The Home Manager module and the NixOS module stay structurally independent:
Home Manager declares no PAM service, and the NixOS module declares no Home
Manager or desktop-session option, so a standalone `homeManagerConfiguration`
evaluation is unaffected by this option's existence.
A future layer that needs the NixOS module to communicate a capability (for
example, "password PAM is available") to Home Manager should use Home
Manager's `osConfig` (populated only when Home Manager is composed via
`home-manager.nixosModules.home-manager` inside a NixOS system, and absent
otherwise) rather than a new capability file or a hidden global; this is a
design note for a later layer, not code added here.

This layer promotes `security.pam-password` from `blocked`/`blocked` to its
already-declared target of `adapted`/`experimental`, and no other
`security.*` ledger entry.
`experimental`, not `supported`, because only the generated artifact is
hermetically proven; no live PAM conversation, prompt, cancel, or lockout
test has been run.

## Layer 3 implementation note

`4-03-security-lock` implements the `security.lock` ledger entry only, as
`programs.omanixy.security.lock.enable` in the Home Manager module
(`modules/home/default.nix`). Disabled by default, and kept structurally
separate from `programs.omanixy.features`: it is a dedicated `security.lock`
option, never a member of `selectedFeatures`/`selectedCapabilities`, matching
the independent-dimension model this ADR already records.

### `osConfig` PAM handshake

Home Manager's `osConfig` special argument (`osConfig ? null`, populated only
when Home Manager is composed via `home-manager.nixosModules.home-manager`
inside a NixOS system, per the layer 2 design note above) is now read, not
just anticipated. Two `assertions` entries enforce the promised handshake:

- `!cfg.security.lock.enable || osConfig != null` - a standalone Home Manager
  evaluation with the lock enabled fails closed, since there is no NixOS
  system to provision the PAM service the lock authenticates against.
- `!cfg.security.lock.enable || osConfig == null || (osConfig.programs.omanixy.security.pam.password.enable or false) == true` -
  an integrated evaluation with the lock enabled but the layer 2 PAM
  capability disabled also fails closed.

The resulting matrix - standalone/lock-off, standalone/lock-on,
integrated/pam-off/lock-off, integrated/pam-on/lock-off,
integrated/pam-off/lock-on, integrated/pam-on/lock-on - passes everywhere
except the two lock-on cases lacking a working PAM service. Only
integrated/pam-on/lock-on passes with the lock enabled. `security-lock`
proves this with real `nixosSystem`/`homeManagerConfiguration` evaluations
forced to `config.system.build.toplevel`/`activationPackage.drvPath`, not a
description of intended behavior.

### No shell.json ownership change

The lock capability does not add, remove, or reorder any `shell.json` key,
and does not gain a new mutation path. `home.activation.omanixyShellState`
is unchanged by `cfg.security.lock.enable`; the capability only selects which
runtime derivation is built (`omanixyRuntimeFor cfg.features (if
cfg.security.lock.enable then { lock = true; } else null)`), which affects
package contents, not the user's config file. `security-lock-shell-json`
proves this directly: it extracts the same `omanixyShellState.data` fragment
from a lock-disabled and a lock-enabled (integrated, PAM-on) configuration
and asserts byte-identical `shell.json` output across five starting states -
absent, the canonical seed, the seed with `omarchy.lock` manually removed
from `disabledPlugins`, a historical store-linked v1 config, and a broken
store symlink. `disabledPlugins` continues to list `omarchy.lock` by default,
unrelated to whether the Nix-side capability is enabled.

Instead, enabling the capability adds a Nix-owned runtime override layer.
`PluginRegistry.qml`'s `isEnabled`/`setEnabled` now consult an injected
`omanixyManagedSecurityPlugins` list (empty when the capability is disabled,
`["omarchy.lock"]` when enabled): a managed-enabled plugin reports enabled
regardless of the user's `disabledPlugins` entry, and a `setEnabled(id,
false)` attempt against a managed-enabled plugin is rejected - either with a
deterministic "managed by Omanixy/Nix configuration" error, or a truthful
idempotent no-op, never a silent write to the user's file. The user's
`disabledPlugins` list itself is never edited by this override; the override
lives entirely in the runtime read path.

### Password-only lock, fingerprint still unreachable

`scripts/patch-lock-service` patches the pinned `Service.qml` (only present
in the compat root when the lock capability is enabled) so that
`fingerprintConfigured` can never become `true`: the refresh path is forced
to `false` unconditionally, and the entire `fingerprintCheckProc` `Process`
block - the only code path that ever shelled out to `fprintd-list` - is
removed outright. No fingerprint PAM conversation, no `fprintd` process, and
no retry-loop activation are reachable; no fingerprint package enters the
runtime closure. `WlSessionLock`/`WlSessionLockSurface` topology, the
`omarchy-lock-password` PAM service name, the `PamContext` conversation, and
the single-attempt-per-submit flow are preserved exactly, matching the
"Lock and session-lock protocol" findings above and the layer 2 PAM
boundary.

### Stranded-lock ABI and DPMS

The same patch script converts the stranded-lock recovery `Process` from a
`bash -c "omarchy-hyprland-session-locked"` string into direct argv
(`["omarchy-hyprland-session-locked"]`), and converts the wake/blank
`Process` commands from the `omarchy-system-wake`/`omarchy-brightness-keyboard`/
`omarchy-brightness-display` helper invocations into direct-argv, time-bounded
Hyprland DPMS dispatches
(`["timeout", "--kill-after=1s", "3s", "hyprctl", "dispatch", "hl.dsp.dpms({ action = \"...\" })"]`),
reusing the same `timeout --kill-after=1s 3s` bound
`packages/omanixy-shell/adapters/common.bash`'s `timed()` already validates,
so a wedged `hyprctl` cannot stall the lock screen's wake/blank path
indefinitely. Neither the pinned wake/blank calls nor this replacement ever
involved clamshell logic; that concern belongs to the unrelated lid/monitor
helpers audited elsewhere in this ADR.

`omarchy-hyprland-session-locked` is a new narrow adapter
(`packages/omanixy-shell/adapters/lock.bash`) implementing the exit-code ABI
this ADR's "Lock and session-lock protocol" section describes: it reads
Hyprland monitor JSON and each monitor's `solitaryBlockedBy`, exiting `0`
when a monitor is still `LOCK`-blocked, `1` when a monitor is readable
(unlocked), and `2` when the state is indeterminate or the backend is
unavailable - a fail-closed default the retry loop in `Service.qml` treats
as "not yet resolved," not as "unlocked." `security-lock` exercises this
exit-code contract hermetically against a fake `hyprctl` for all three
states plus a malformed-output case, and separately against the real
packaged executable at `$lock_runtime/bin/omarchy-hyprland-session-locked`.
It is deliberately not registered in `upstream/compatibility-contracts.json`;
that ledger's helper set is exact-matched against
`test/compat-adapters.sh`'s executed test cases by
`test/compatibility-test-matrix.sh`, and this helper's fake-backend coverage
lives in `test/security-lock.sh` instead, outside that cross-check.

### Executable surface scanning and independence proofs

`scripts/scan-lock-executable-surface` fail-closed scans every `command:
[...]` array (declarative or procedural `x.command = [...]`) in the FINAL
patched `Service.qml` against an explicit allowlist. Discovery reuses the
shared QML source-discovery primitives (`scripts/source_discovery.py`) that
the layer-1 contract audit already relies on, so a multiline array, a
procedural `.command =` mutation, and any non-array dynamic binding
(`command: <expr>`, `x.command = <expr>`, a dynamic `exec(...)`/`.run(...)`
call) are all found the same way everywhere in this repo. This is a lexical
masker, not a parser: comments are stripped first, then quoted-string
content is separately, lexically masked before discovery runs, so a comment
marker or command-looking text sitting inside a string cannot satisfy or
spoof the scan, and cannot hide a real binding that follows it. The literal
values used for allowlist validation are still read from the
comment-stripped (not string-masked) text, so a legitimate command array's
real executable name is never itself blanked.

The shared source-discovery library contains conservative lexical support
for QML/JS backtick template literals and `${...}` interpolation - other
repository audits may legitimately encounter them - but the security.lock
executable-surface profile intentionally rejects live template literals
entirely rather than trying to prove their content safe. QML/JS template
literals admit full ECMAScript grammar, and regex literals in particular
make "}" -> interpolation-depth counting unprovable without a real parser
(division vs. regexp-literal ambiguity, character classes, escaped
slashes, flags); growing the shared lexer to chase that would only ever
close one gap at a time. Instead, after the comment-stripping and
string-masking passes above, any backtick that still appears in the
masked text is - by construction, since an ordinary quoted string's or
comment's content is already stripped or blanked by that point - a live
template delimiter, and the scanner rejects the file outright the moment
one is found, before command discovery even runs. This is acceptable
specifically because the real, reviewed lock Service.qml requires zero
template literals: the generated lock source stays within a smaller,
statically auditable command subset than general QML, and that is
intentional security policy for this profile, not a limitation needing a
follow-up. An unterminated backtick template literal, or a `${...}`
interpolation whose closing `}` is never found, is still separately
caught by the shared library's own `UnsafeSource` fail-closed path (used
by every source_discovery consumer) before the categorical rejection above
even runs.

Validation then tokenizes each discovered array positionally: the executable
position must be a literal naming an allowed direct executable (`readlink`,
`omarchy-hyprland-session-locked`) or the `timeout` wrapper around an
allowed wrapped executable (`hyprctl`) with its own literal flags and
duration, a `bash`+`-c` shape is rejected regardless of token position, and
any non-array dynamic binding is an automatic fail - only the identity of
what gets executed is in scope, so a trailing dynamic argument (e.g. a
dynamic path passed to `readlink`) does not fail the scan.
`test/security-lock-executable-surface.sh` proves this against the real
patched file plus an adversarial matrix covering both the single-line and
multiline shape of every case above - an unknown tool, a reintroduced
`bash -c` shape (including reordered under `timeout` and split across
lines), a dynamic (non-literal) executable, duration, or declarative/
procedural binding, an unknown executable wrapped by `timeout`, and a
same-line or block comment containing an otherwise-allowed-looking command
sitting next to a real unknown one - are all rejected, while the real
patched-file command shapes and their multiline/procedural-assignment
equivalents still pass. A further string-safety matrix proves the lexical
masker itself cannot be defeated: a command-looking fake inside a single-
or double-quoted (including escaped-quote) string, and a comment marker
appearing inside such a string right before a real unknown command, are
both covered - alongside a real allowed command sitting next to unrelated
strings/comments containing command-looking text, which still passes. A
dedicated template-literal rejection matrix proves the categorical policy
holds regardless of content: a plain template with no interpolation, a
static-text-only template, a template containing only an allowed-looking
command string, ordinary interpolation, nested interpolation, and two
distinct regex-literal shapes that would otherwise miscount a "}" as
closing an interpolation early (a bare `/}/ ` and a character class with an
escaped slash) are all rejected the same way, before discovery ever runs -
proving the regex blind spot in the shared lexer is irrelevant to this
scanner's actual guarantee. A template literal sitting alongside a real,
unrelated unknown `.command =` binding is rejected outright too, rather
than being defeated by (or credited for) whatever discovery would have
found inside it. Conversely, a literal backtick character inside an
ordinary single- or double-quoted string, or inside a `//`/`/* */`
comment, does not trigger the rejection, since both are already
stripped/masked before the check runs. Malformed backtick/interpolation
constructs - an unterminated backtick template literal, an unterminated
`${...}` interpolation, and an unterminated `/* */` comment inside one -
are separately proven to still fail closed via the shared library's
pre-existing `UnsafeSource` path, independent of the categorical
rejection.

`test/security-lock-managed-plugin.sh` proves two independent things with
real QML behavior rather than a source grep. First, defense against
contradictory/injected registry state: it instantiates the generated
`PluginRegistry.qml` directly with a hand-injected `installedPlugins` map
and drives `isEnabled`/`setEnabled` against both a plain lock-enabled
registry and one with a hostile local plugin shadowing the `omarchy.lock` id
as a `bar`-kind entry, proving the managed override still wins even over a
self-contradictory registry state, never mutates `shellConfigMutator`, and
reports the disabled-capability case as unreachable. Second, that the real
filesystem scan-and-merge path itself cannot produce that hostile state: a
separate harness points the real registry's `firstPartyDir`/`pluginsDir` at
a copy of the actual first-party `omarchy.lock` manifest tree and a hostile
third-party directory also claiming the `omarchy.lock` id, drives the real
`rescan()` (the actual `find`/merge script, not a stand-in for it), and
asserts the merged `installedPlugins["omarchy.lock"]` resolves to the
first-party manifest and entry point, never the hostile one.

`test/security-lock-core-only.sh` proves `security.lock` does not widen a
core-only build's dependency surface at two distinct levels. At the declared
level, `packages/omanixy-shell`'s own `runtimeInputs` - the explicit list of
package derivations named in the Nix expression, computed purely from
`selectedCapabilities`, which is itself derived only from `features` and
never from `security` - is exposed as `passthru.declaredRuntimeInputs` and
asserted byte-identical between the core-only and core+lock builds; this is
a direct claim about the dependency declaration itself, not an emergent
property of whatever ends up in a built closure. At the closure level, rather
than checking a hardcoded list of presentation-package name patterns
(core-runtime already pulls in packages like `pipewire`, `bluez`,
`libnotify`, `uwsm`, and `qrencode` transitively through `hyprland`/
`systemd`, independent of any Omanixy feature or of `security.lock`, so a
pattern list drifts out of sync with that baseline), it compares the
core-only and core+lock closures' full transitive store paths, stripped to
package name (hash removed), and asserts the lock capability adds zero new
names.

### Conditional packaging

`shell/plugins/lock/{Service.qml,LockView.qml,manifest.json}` are copied into
the compat root only when the lock capability is enabled; a lock-disabled
build has no `shell/plugins/lock` directory at all, matching the layer 2
precedent for `polkit`/`notifications`/`idle`.

### Scope

This layer promotes `security.lock` from `blocked`/`blocked` to its
already-declared target of `adapted`/`experimental`, and no other
`security.*` ledger entry; `security.pam-fingerprint`,
`security.polkit-agent`, `security.idle`, `security.notification-daemon`, and
`security.recovery` remain `blocked`. `experimental`, not `supported`,
because every proof in this layer is hermetic and fake-backend: no real
authentication, generation switch, logout, reboot, suspend, Hyprland
process, or live Quickshell session has been exercised. Omanixy still owns no
lock keybinding, and the native lock still runs in-process inside the
existing `omanixy-shell` user service with no new systemd unit.

## Layer 4 implementation note

`4-04-security-fingerprint` implements the `security.pam-fingerprint` ledger
entry only, adding fingerprint authentication as an optional,
disabled-by-default secondary unlock path alongside - never instead of - the
layer 2/3 password path. Password authentication remains the mandatory,
always-functional fallback throughout every configuration this layer adds;
nothing in this layer can make password authentication unavailable.

### NixOS fingerprint PAM capability

`programs.omanixy.security.pam.fingerprint.enable` (default `false`,
`modules/nixos/default.nix`) mirrors the password capability's ownership
contract exactly: `lib.mkForce` on both `enable` and the single-line `text`
of `security.pam.services."omarchy-lock-fingerprint"` (one
`auth required ${config.services.fprintd.package}/lib/security/pam_fprintd.so`
line), plus an assertion against the *resolved* service state rather than
the override alone, closing the same equal-priority `lines`-merge escape the
layer 2 note describes. No `account`, `session`, or `password` PAM phase is
declared, matching the `PamContext` ABI's single `pam_authenticate` call.

The capability also owns the daemon activation `pam_fprintd.so` needs: the
resolved `services.fprintd.package` is registered directly with
`services.dbus.packages`, `systemd.packages`, and
`environment.systemPackages`, the same three lists `services.fprintd`'s own
module would populate if enabled. This option deliberately never sets
`services.fprintd.enable` itself, because
`nixos/modules/security/pam.nix` reads that option as the default for every
*other* PAM service's own `fprintAuth` - turning it on would silently widen
fingerprint authentication into login/sudo/su/polkit-1/greetd/sshd and any
other PAM service that does not override `fprintAuth` itself. An assertion
verifies `services.fprintd.enable` stays `false` and that the resolved
package actually landed in all three registration lists, so a host or
another module contesting either invariant fails the build closed instead of
silently widening PAM scope or losing the daemon activation. This is a
Nix-declared capability, not a runtime readiness claim: a machine with this
enabled but no fingerprint reader, no enrolled finger, or no `fprintd`
running still builds and boots successfully.

### Home Manager `lock.fingerprint` option and the paired-capability handshake

`programs.omanixy.security.lock.fingerprint.enable` (default `false`,
`modules/home/default.nix`) extends the layer 3 `osConfig` handshake with
three further `assertions`, on top of the two `security.lock.enable` already
enforces: the option is only meaningful while
`programs.omanixy.security.lock.enable` is also `true`; a standalone Home
Manager evaluation (no `osConfig`) with fingerprint enabled fails closed,
for the same reason the lock option itself does; and an integrated
evaluation fails closed unless the paired NixOS configuration has *both*
`programs.omanixy.security.pam.password.enable` and
`programs.omanixy.security.pam.fingerprint.enable` set - the former because
fingerprint is only ever a secondary path to the mandatory password
fallback, never a replacement for it, and the latter because it provisions
the PAM service and daemon fingerprint authenticates against.

Crossing this option against the layer 3 lock/PAM matrix yields seven
scenarios: the two standalone cases (lock disabled, lock enabled) and the
four integrated password/fingerprint on/off combinations fail whenever
either paired NixOS capability is missing, only the fully-integrated
both-capabilities-on case succeeds with fingerprint enabled, and that same
integrated configuration continues to succeed with fingerprint left at its
default (`false`) - proving the new option is additive to, and never a
precondition of, the existing password-only lock. `security-lock-fingerprint`
proves this with real `nixosSystem`/`homeManagerConfiguration` evaluations
forced to `config.system.build.toplevel`, not a description of intended
behavior.

### Bounded fingerprint state machine

`scripts/patch-lock-service --fingerprint enabled|disabled` gains a second,
independent mode alongside the existing lock patch. In `enabled` mode it
reintroduces a fingerprint `PamContext` against the
`omarchy-lock-fingerprint` service name, but bounds it: a
`fingerprintMaxAttempts: 5` budget, a readonly `fingerprintExhausted`
property derived from it, and a non-repeating (`repeat: false`) retry timer
whose restart on both a failed attempt and a PAM error is guarded by
`!fingerprintExhausted`. The budget resets only in `beginLock`, tied to lock
acquisition, never to a screen change, DPMS event, or password failure,
matching the "Lock and session-lock protocol" finding above that the pinned
source's unbounded 250 ms retry-on-every-failure needed a tested stop
condition before promotion. The upstream `fingerprintCheckProc`
`bash -c`/`fprintd-list` probe is not reintroduced; its replacement is the
readiness adapter below, invoked as direct argv.

Fingerprint failure, exhaustion, or a PAM error can never call
`finishUnlock()`, release the lock, or touch password state: the only
`finishUnlock()` call in `handleFingerprintFinished` is gated on
`PamResult.Success`, and neither that handler nor the fingerprint PAM
context's error path references `failedAttempts` or the password `PamContext`.
Password submission stops the fingerprint retry timer and aborts any
in-flight fingerprint PAM conversation before starting its own; a password
failure calls `startFingerprint()` to resume scheduling but never refills
the fingerprint attempt budget itself, and `startFingerprint()` refuses to
start while a password check is in flight or the budget is exhausted. The
pre-existing `idleBlankTimer` stays gated on `authenticatingPassword` alone,
and the stale upstream comment claiming the fingerprint PAM stays armed for
the whole lock - no longer true once bounded and abortable - is rewritten in
both patch modes rather than left accurate only for the disabled build.
`status()` gains `fingerprintEnabled`, `fingerprintReady`,
`fingerprintAuthenticating`, `fingerprintAttempts`,
`fingerprintAttemptsRemaining`, and `fingerprintExhausted`; none of the six
carry biometric or PAM content, only capability and bounded-counter state.
`security-lock-fingerprint` proves all of this against the real generated
Service.qml source, not a description of the intended state machine -
including that `beginLock()` itself, not only `FingerprintPolicy.js`'s rules
in isolation, resets authentication state, invalidates readiness
(`fingerprintReady = false`) and consumes the budget (`fingerprintAttempts
= 0`) synchronously, then queues the actual lock and only afterward defers
a bounded fresh readiness refresh via `Qt.callLater`, in that order - and
`security-lock` continues to prove the disabled build is byte-identical to
the frozen layer 3 output. `security-lock-fingerprint-behavior` complements
that structural proof with a behavioral one: it `require()`s
`FingerprintPolicy.js` directly and drives every exported guard - including
a full simulated lock lifecycle covering an indeterminate readiness probe,
in-flight-conversation exclusion, budget exhaustion, password-authentication
precedence, and a stale success result arriving after mid-conversation
capability revocation - rather than re-deriving the same assertions from a
disconnected reimplementation of the rules.

The same file also drives four stress sequences through the identical
`canStartFingerprint()`/`shouldRetryAfterFailure()` decision sequence the
runtime itself uses, rather than shortcuts like `isExhausted(100, 5)`: 100
adversarial start attempts resolved as ordinary failures, and again resolved
through both the `onError` and `onCompleted(Error)` paths a single failed
conversation drives (see "Concurrency and abort semantics" below) - both
converge on exactly 5 actual starts and 5 final attempts, never 100, with no
retry re-permitted after exhaustion; a password submission arriving with a
fingerprint conversation already in flight and budget remaining permits zero
further fingerprint starts across 100 further adversarial cycles, and the
subsequent password failure resumes fingerprint only from the untouched
remaining budget - never resetting it - with the lock's total starts still
never exceeding 5; and a fresh `beginLock()` after a prior lock exhausted its
budget with readiness left `true` resets both attempts and readiness before
any probe runs, proving budget reset and readiness reset are two separate,
intentional transitions rather than one derived from the other.

### Concurrency and abort semantics

The pinned Quickshell revision's `PamContext` (`src/services/pam/qml.cpp`)
makes both `onError` and `onCompleted` call `this->abortConversation()`
*before* emitting anything to QML, and `abortConversation()` disconnects
every `PamConversation` signal from the `PamContext`, schedules the
conversation for `deleteLater()`, and clears the active-conversation
pointer - in that order - before returning. Two consequences follow
directly from reading that source, not from this layer's own design: first,
an explicitly aborted conversation (`fingerprintPam.abort()`, called from
`submitPassword()` and `onFingerprintPamConfiguredChanged`) can never later
deliver a `completed`/`error` signal through `PamContext`, because the
disconnect happens synchronously in the same call that clears the
conversation - so no additional generation token or sequence counter is
needed in this layer's QML to guard against a stale post-abort callback; the
pinned ABI already makes that case unreachable. Second, `onError` emits both
`error(...)` and `completed(PamResult::Error)` for the *same* failed
conversation, so `root.onError` and `handleFingerprintFinished` both
evaluate `FingerprintPolicy.shouldRetryAfterFailure()` around that one
failure - harmlessly redundantly, since `fingerprintRetryTimer.restart()`
just reschedules the same single `Timer` instance rather than double-firing
it. `security-lock-fingerprint-behavior`'s 100-error stress sequence models
this conservatively by evaluating the retry decision twice per failure
cycle and asserting both evaluations agree. This section documents what the
pinned revision (`quickshell-mirror/quickshell@28771c7c74b42e20afca0b1b63980cb46515537c`)
does; it is not a claim about any other Quickshell revision.

### Readiness adapter ABI

`omarchy-lock-fingerprint-ready` (`packages/omanixy-shell/adapters/lock.bash`)
is a new narrow adapter, argument-free and scoped to the current user via
`id -un`, replacing the upstream probe's `bash -c "fprintd-list | grep ..."`
shape entirely. It classifies `fprintd-list`'s own success/failure exit code
together with its stdout text - `fprintd-list` puts every message, including
errors, on stdout rather than stderr, and a successful call still reports "no
fingers enrolled" as a non-error condition - into the same three-way ABI the
"Lock and session-lock protocol" finding's compositor-state adapter already
uses: `0` ready, `1` definitely unavailable (no reader, or no enrollment for
this user), `2` indeterminate (missing `fprintd-list`, a D-Bus timeout, or any
output shape the probe cannot classify). The call is time-bounded through the
same `timed()` primitive `common.bash` already validates, so a wedged
`fprintd-list`/D-Bus call cannot stall the lock indefinitely, and indeterminate
is the fail-closed default rather than a guess. No hardware probing occurs
during Nix evaluation; this adapter only ever runs at runtime, invoked by the
patched Service.qml as direct argv, never through a shell.
`security-lock-fingerprint-ready` proves the classification itself against a
fake `fprintd-list`/`id` PATH-injection harness covering the full exit-code
matrix - missing backend, `id` failure, timeout, an unclassifiable exit
code, single- and multi-device enrollment, no enrollment, no devices, and
malformed output in both the success and failure paths - and asserts no raw
signal, timeout, or missing-backend exit code ever leaks past the adapter's
own `0`/`1`/`2` ABI.

### Package identity and TOD activation

Two further hermetic proofs close gaps the ledger flagged as unaddressed
when this layer's capability was first added. `security-pam-fingerprint-custom-package`
proves a custom `services.fprintd.package` threads through as a single
identity: the generated PAM service, all three NixOS registration lists, and
the Home Manager runtime's own `declaredRuntimeInputs` all resolve to that
exact overridden store path, with no independently-resolved default
`pkgs.fprintd` pulled in alongside it - the split-brain package ownership
this capability must never reintroduce.
`security-pam-fingerprint-tod` proves `services.fprintd.tod.enable` resolves
`services.fprintd.package` to the TOD-aware daemon on its own (independent
of `services.fprintd.enable`) and mirrors the one `FP_TOD_DRIVERS_DIR`
environment variable upstream's own `services.fprintd.enable`-gated block
would otherwise only set, pointed at the selected driver's real path. Both
proofs use hermetic fixtures rather than a real driver package: every
`libfprint-2-tod1-*` driver in the pinned nixpkgs is either marked
`meta.broken` or carries an unfree license this flake cannot evaluate
without `allowUnfree`, so the TOD fixture is a minimal stand-in derivation
exposing only the one `driverPath` passthru attribute the upstream module
actually reads.

### Executable surface scanning

`scripts/scan-lock-executable-surface` gains a `--fingerprint disabled|enabled`
profile argument alongside the existing positional file: in `enabled` mode,
the allowlist gains exactly one new allowed direct executable,
`omarchy-lock-fingerprint-ready`, and nothing else - no new wrapped
executable, no relaxation of the existing `bash -c` rejection or literal-only
tokenization rules the layer 3 note describes. `security-lock-fingerprint-executable-surface`
proves the disabled-mode allowlist is unchanged from layer 3 and that the
enabled-mode allowlist accepts only that one addition.

### Scope

This layer promotes `security.pam-fingerprint` from `blocked`/`blocked` to
its already-declared target of `adapted`/`experimental`, and no other
`security.*` ledger entry; `security.polkit-agent`, `security.idle`,
`security.notification-daemon`, and `security.recovery` remain `blocked`.
`experimental`, not `supported`, because every proof in this layer is
hermetic: no live `fprintd` daemon, real reader, enrolled or unenrolled
hardware, or repeated-failure log-volume behavior has been exercised, and a
real (non-fixture) TOD driver package has not been validated since every
license-clear candidate in the pinned nixpkgs is currently marked broken.
These remain the ledger's `required_before_promotion` items for this entry.
Omanixy still owns no polkit, idle, or notification-daemon surface, and
adds no new systemd unit beyond the `fprintd`-provided one this capability
merely registers for activation. `security-lock-fingerprint-closure`'s
declared-input-widening proof is an exact set difference - the
fingerprint-enabled build adds precisely one `declaredRuntimeInputs` entry
and removes none, and that one entry is asserted equal to the exact selected
fingerprint package store path the fixture was built with, not merely a
`fprintd`-prefixed name - rather than a substring match against the raw
diff, so a future change that widened the runtime by that package plus
something else unrelated, or by a same-named but differently-built package,
would fail this proof rather than pass it silently. This is a
declared-input and compatibility-bin level proof, not a full-transitive-
closure one: the closure-reachability check only proves the selected
fprintd package is absent from the fingerprint-disabled closure and
reachable from the fingerprint-enabled one, since that package carries its
own transitive closure and a claim of an exact path-count difference across
the full closure would overstate what is actually checked.

## Layer 5 implementation note

`4-05-security-polkit` implements the `security.polkit-agent` ledger entry
only, as two independent options: `programs.omanixy.security.polkit.system.enable`
in the NixOS module (`modules/nixos/default.nix`) and
`programs.omanixy.security.polkit.agent.enable` in the Home Manager module
(`modules/home/default.nix`). Both default to `false` and are kept
structurally separate from `programs.omanixy.features`, matching the
independent-dimension model this ADR already records. Unlike layers 3/4,
this layer introduces no PAM service of its own at all.

### System and session ownership split

The system option declares `security.polkit.enable = true` using an
ordinary (non-forced) assignment - deliberately not `lib.mkForce` - so that
a genuine, stronger consumer override is still possible; a resolved-state
assertion (`config.security.polkit.enable == true`) then fails the build
closed if such an override actually contests the capability, rather than
silently leaving it unfulfilled. This differs from layers 2/4's PAM
ownership contract on purpose: `security.polkit` is a whole-subsystem
capability NixOS's own `security.polkit` module already owns completely
(`polkitd`, its D-Bus/systemd integration, `polkit-agent-helper`, and the
`polkit-1` PAM service), so Omanixy's only job is turning that module on,
never re-declaring or forcing any part of what it produces.
`security-polkit-system` proves the resolved systemd/D-Bus/PAM surface is
identical whether `security.polkit.enable` is set by Omanixy's option or
directly by a host with no Omanixy involvement at all, and proves the
resolved-state assertion actually fails `config.system.build.toplevel`
closed against a `lib.mkForce false` adversary.

The agent option is the session-side half: enabling it makes the Quattro
`shell/plugins/polkit` agent reachable as a managed security plugin,
exactly parallel to `omarchy.lock` in layer 3. It requires an integrated
Home Manager + NixOS installation (standalone fails closed, for the same
`osConfig`-availability reason layer 3's lock option does) and additionally
requires the paired `programs.omanixy.security.polkit.system.enable` to be
`true` - the explicit system/session ownership handshake this ADR's
"Independent ownership and support model" section already calls for.
`security-polkit-hm` proves the full 12-case matrix this crossing produces,
including that `security.lock` and `security.polkit-agent` are mutually
independent in both directions: polkit reachable with the lock left
disabled, and the lock reachable with polkit left disabled.

### Known declarative agent conflicts, and the unknown-agent boundary

Pinned Home Manager exposes at least two other declarative session polkit
agents, `services.hyprpolkitagent.enable` and `services.polkit-gnome.enable`.
Enabling the Quattro agent alongside either fails Home Manager evaluation
closed with an actionable message; Omanixy never sets, stops, or kills
either service itself, and leaves both fully alone whenever the Quattro
agent is off. `security-polkit-hm`'s matrix proves both conflict directions
and both agent-off pass-through cases, and `security-contracts` statically
guards that neither service is ever imperatively assigned, `systemctl
stop`-ed, or killed anywhere in this repository.

An *unknown* external agent - one this repository has no way to detect
declaratively - is a different, narrower claim. The pinned Quickshell
`PolkitAgentListener` registers exactly once per agent construction
(`PolkitAgentImpl`'s constructor calls `qs_polkit_agent_register` once,
unconditionally); `registerComplete(false)` only logs a warning and never
re-registers, so there is no retry loop to runaway against a competing
registration. `PolkitAgentImpl::tryTakeoverOrCreate` exists to hand a
previous QML engine generation's registration to a new one during
Quickshell's own hot-reload, which is that pinned implementation's internal
behavior, not an Omanixy process killer, and this layer adds nothing on top
of it. `security-polkit-quickshell-contract` proves all of this as static
source-contract evidence against the pinned revision
(`quickshell-mirror/quickshell@28771c7c74b42e20afca0b1b63980cb46515537c`):
one registration attempt per construction, no retry on failure, agent- and
user-initiated cancellation never start a replacement session, ordinary
(non-cancelled) authentication failure emits `authenticationFailed` and then
does automatically start a fresh session for the same request/identity -
the pinned ABI's own support boundary, which this layer does not add a
restart loop on top of - and destruction cancels queued/active requests
while unregistering only the listener's own registration handle. A real,
live D-Bus registration collision is not exercised here; it remains a
required-before-promotion item, deferred to the layer 8 recovery/support
gate rather than hidden as resolved.

### Method-neutral QML adaptation

The pinned `PolkitAgent.qml` infers fingerprint availability by watching a
`FileView` on `/etc/pam.d/polkit-1` and gates it behind a laptop-lid helper
Process (`omarchy-hw-laptop-closed`, invoked via `bash -c`). Layer 5 removes
both entirely, along with the `fingerprintConfigured`/`laptopClosed`
properties and the `loadPamConfig()`/`refreshLidState()` functions that fed
them - Omanixy does not infer, and does not take over, the host's own
`polkit-1` PAM authentication policy the way the earlier ledger wording
implied. `polkit-1` is not merely a file the pinned QML reads for
fingerprint UI policy; it is the actual PAM service the native
`polkit-agent-helper` authentication path consumes, and Layer 5 leaves it
entirely to whatever the host's `security.polkit.system.enable` capability
(or an entirely separate host configuration) already resolves.

The resulting presentation is authentication-method-neutral: a single
`waitingForAuthentication` property (`dialogVisible && !responseRequired &&
!submitted && !errorFlash`) replaces the pinned `fingerprintMode`
computation, driven only by the pinned Quickshell `AuthFlow.
isResponseRequired` signal - it never assumes fingerprint, smartcard,
another PAM module, or a transient noninteractive phase, and shows a
generic waiting icon rather than a fingerprint glyph. `scripts/patch-polkit-agent`
performs this adaptation as the same exact-source, fail-on-drift
`replace_once` discipline `scripts/patch-lock-service` established -
every pinned block it touches must match verbatim exactly once, or the
build fails closed rather than silently producing a partially-adapted
plugin. `security-polkit-qml-behavior` proves the adapted, patched
`PolkitAgent.qml` behaviorally against a deterministic fake agent, following
`test/qml-patch-behavior.sh`'s offscreen-Quickshell pattern: inactive,
generic-waiting, response-required, submit, escape/cancel, ordinary
failure, success, and daemon-initiated cancellation, all against the real
generated source with only two harness-only, exact-match transforms
(`PanelWindow` to a plain `Item`, and the real `PolkitAgent` listener to an
inline fake `QtObject` exposing the identical property/signal surface) -
neither of which the reviewed production adaptation itself contains.
`security-polkit-model` drives the trimmed `PolkitModel.js` directly via
`require()`, proving `authorizationLabel` is unchanged while the now-dead
`promptLooksFingerprint`/`fingerprintConfiguredFromPamConfig` helpers are
gone from both the module body and its `module.exports` surface.

### Executable surface scanning

`scripts/scan-polkit-executable-surface` proves a different invariant than
`scan-lock-executable-surface`: where the lock scanner allowlists a bounded
set of literal, audited commands bound to `Process.command` and treats zero
bindings as unverifiable, the polkit scanner's audited invariant is
*absence of any process-execution surface at all*. A command-property
inventory alone is not that invariant: the pinned Quickshell `Process` type
also exposes `Q_INVOKABLE void exec(QList<QString> command)` (and a
`ProcessContext` overload), so a `Process` object with no `command:`
property whatsoever can still execute an arbitrary command via
`someProcess.exec([...])`, an unqualified `exec([...])` called from inside
that `Process`'s own scope, or a literal array handed to an unrelated
`object.run([...])` - none of which are a "command binding" in the sense
the lock scanner's allowlist model cares about, and the first remediation
pass's scanner generation (reusing `source_discovery`'s shared
`DYNAMIC_RUN_RE`, which deliberately excludes a literal array argument
because the lock allowlist needs to inspect rather than reject one) could
not see any of them. The scanner therefore enforces the stronger invariant
the real generated file actually satisfies: zero `Process` object
instantiations, zero `command:`/`.command =` property bindings, and zero
`exec(...)`/`execDetached(...)`/`.run(...)` calls of any shape - qualified
or bare, literal-argument or dynamic. It reuses the shared `source_discovery`
comment/string-masking primitives the lock scanner does for lexical
discovery only; the policy regexes themselves are local to
`scan-polkit-executable-surface` and do not touch `scripts/source_discovery.py`,
so Layer 3's lock scanner (and any other consumer of that shared module)
keeps its existing, narrower behavior unchanged.
`security-polkit-executable-surface` proves the real generated
`PolkitAgent.qml` passes with zero Process objects, zero command bindings,
and zero exec/run calls, and that a permanent adversarial fixture set is
rejected: a `Process` object driven purely through `.exec(...)` with a
literal or dynamic argument, an unqualified `exec(...)` call from inside a
`Process`'s own scope, the original `command:`/procedural-assignment
shapes, a literal- or dynamic-argument `object.run(...)` call, qualified
`Quickshell.exec`/`execDetached`, a multiline `.exec([...])` call, and a
reintroduced `omarchy-hw-laptop-closed` invocation - alongside fixtures
proving Process/exec/run-looking text sitting inertly in a `//` comment, a
`/* */` comment, or an ordinary quoted string produces no false positive,
and that a real call following such fake text is still caught at its
correct position. The template-literal fail-closed policy is unchanged.

### Scope

This layer promotes `security.polkit-agent` from `blocked`/`blocked` to its
already-declared target of `adapted`/`experimental`, and no other
`security.*` ledger entry; `security.idle`, `security.notification-daemon`,
and `security.recovery` remain `blocked`. `experimental`, not `supported`,
because every proof in this layer is hermetic and fake-backend: no live
D-Bus registration, no real polkit authentication success or wrong-password
behavior against actual `polkit-agent-helper`/PAM, no daemon
disappearance/reappearance, no Quickshell crash/restart during an active
request, and no nested-session validation has been exercised. These remain
the ledger's `required_before_promotion` items for this entry, and are the
layer 8 recovery/support gate's responsibility, not a new follow-up issue.
Omanixy still owns no idle or notification-daemon surface, adds no pkexec
wrapper (`security.polkit.enablePkexecWrapper` stays at its NixOS default of
`false`), adds no sudo/setuid helper, and
`security-polkit-no-fingerprint-widening` proves enabling polkit alongside
layer 4's fingerprint capability changes neither `services.fprintd.enable`
nor the dedicated `omarchy-lock-fingerprint` PAM service (byte-identical to
the fingerprint-only build), and that no policy is copied between the
screen-lock and polkit PAM services in either direction.
`security-polkit-core-only` proves `declaredRuntimeInputs` and the
compatibility-bin entry set are byte-identical between a core-only build
and a core+polkit build, and that the polkit-enabled build's transitive
dependency package-name set contains no new name. It also proves a
stronger, raw store-path-level claim: the Omanixy-owned compatibility root
genuinely gains new content (the polkit plugin files), and everything that
references the compatibility root's store path in its own build - `ipc`,
`compatAdapter`, the runtime script, the compatibility bin, and the final
package itself - therefore changes store path identity too, purely by Nix's
own content-addressed propagation. The test names those exact six
derivations per build (not an `/^omanixy-/` package-name pattern) as the
only closure entries allowed to differ, and after excluding precisely that
named set, asserts every remaining store path - the entire external
dependency surface - is byte-identical between the two closures, not merely
same-named. This is a stronger claim than layer 3/4's "one new helper, no
new package name" proofs: polkit adds no external runtime dependency store
path at all, only the expected, reviewed Omanixy-owned content derivations
differ. `security-polkit-closure` separately proves the polkit-agent-enabled
build's compatibility-bin entry set is byte-identical to the
polkit-disabled default build's (not merely the core-only comparison above),
that `fprintd` is unreachable from its closure, and that the compatibility
root contains exactly the polkit plugin files and none of layer 3/4's lock
or idle/notification surface.

## Layer 6 implementation note

`4-06-security-idle` implements the `security.idle` ledger entry only, as
`programs.omanixy.security.idle.enable` in the Home Manager module
(`modules/home/default.nix`).
Disabled by default, and kept structurally separate from
`programs.omanixy.features`, matching the independent-dimension model this
ADR already records.
Unlike layers 4/5, this layer introduces no new PAM service or system
capability at all - idle is a session-only concern, so there is
deliberately no NixOS-side idle option.

### Bounded ownership split, not a wholesale idle-manager port

The pinned idle service does five things this layer does not want as one
bundle: idle detection, a terminal screensaver choreography, lock-on-idle,
display wake/DPMS, and a stay-awake marker.
Layer 6 owns exactly the first, the last, and a *bounded* version of the
third: user-session idle detection, inhibitor-aware idle state, bounded
lock-on-idle orchestration, and user-controlled stay-awake state, plus
explicit conflict detection with known Home Manager idle managers.
It owns none of suspend-on-idle, pre-suspend locking, logind inhibitors,
system sleep policy, terminal screensaver presentation, display blanking,
DPMS wake policy, keyboard backlight, or clamshell policy.
The resulting ownership chain is: Quickshell `IdleMonitor` detects idle,
the Layer-6 service decides when to request a lock, Layer 3's native lock
owns `WlSessionLock`+DPMS, the consumer/NixOS owns suspend/power policy,
and Layer 8 owns suspend/resume/recovery.
This is a deliberately narrower boundary than importing Omarchy's wider
idle/sleep policy wholesale would draw.

Three upstream helpers are read but not ported, each for a distinct reason
recorded here rather than left as an implicit gap.
`bin/omarchy-launch-screensaver` (the entire terminal screensaver
choreography - `ttfx`, `socat`, a terminal launcher, and Hyprland raw-event
window tracking - is omitted outright; the adapted service has no
screensaver process, timer, tracking, or Hyprland connection of any kind).
`bin/omarchy-system-lock` (keyboard layout reset, 1Password locking, and
`pkill` calls are not ported; the adapted service's only lock action is the
direct argv `omanixy-shell lock lock`, the same generic IPC contract the
ADR's layer-1 "Lock provider and keybinding boundary" section already
anticipated).
`bin/omarchy-system-wake` (not ported at all, together with the
brightness/clamshell helpers it chains into, because Layer 6 never blanks
the display in the first place and so has nothing of its own to wake -
reintroducing a wake call here would create a second, competing DPMS owner
alongside Layer 3's).
A fourth pair, `bin/omarchy-system-sleep-monitor`/`bin/omarchy-system-sleep-lock`,
is not read at all in this layer.
Pre-suspend locking and system sleep policy are explicitly deferred to the
layer 8 recovery/support gate, and no claim of suspend safety is made
anywhere in this layer's evidence.

### Home Manager option and the lock/daemon-conflict handshake

`programs.omanixy.security.idle.enable` requires
`programs.omanixy.security.lock.enable` to also be `true` - enforced by an
`assertions` entry mirroring the layer 3/4/5 paired-capability pattern,
because Layer 6 owns no lock provider of its own and would otherwise have
nothing to request.
Idle is structurally independent of `programs.omanixy.security.lock.fingerprint`
and `programs.omanixy.security.polkit.agent` in both directions: enabling
either changes nothing about whether idle may be enabled, and idle never
implicitly enables lock, fingerprint, or polkit itself.

Two further `assertions` entries guard against a known-declarative
conflict, mirroring layer 5's `hyprpolkitagent`/`polkit-gnome` guard
exactly: enabling idle alongside `services.hypridle.enable` or
`services.swayidle.enable` fails Home Manager evaluation closed with an
actionable message.
Omanixy never sets, stops, or kills either daemon itself, and leaves both
fully alone whenever the Quattro idle owner is off.
`security-idle-hm` proves the resulting 10-case matrix (idle×lock crossed
with both conflict directions, both cases collapsing to vacuous while idle
itself is off, and idle's independence from fingerprint and polkit), and
`security-contracts` statically guards that neither daemon is ever
imperatively assigned or killed anywhere in this repository, alongside
guards against reintroducing the screensaver, system-lock/-wake, or
sleep-monitor vocabulary into the Home Manager module.

### Bounded lock-retry policy as a pure module

`packages/omanixy-shell/IdlePolicy.js` is a pure decision-logic module,
mirroring the `FingerprintPolicy.js` precedent layer 4 established:
`isExhausted`, `canRequestLock`, `classifyLockResult`, and
`shouldRetryLockResult`, all pure functions over an explicit state object
rather than closures over QML properties.
The retry budget is `lockMaxAttempts: 3`, a non-repeating (`repeat: false`)
1000ms `Timer`, reset only at the start of a fresh idle cycle (never by
activity alone re-arming mid-cycle) - matching the "tested stop condition
before promotion" lesson layer 4's ADR note already drew from the pinned
fingerprint retry's unbounded 250ms loop.
An attempt is consumed *before* the `Process` starts, so a denied
`canRequestLock()` call - exhausted, terminal failure already recorded,
activity, or stay-awake - never itself counts as an attempt.

The lock IPC's own three-way result contract
(`shell/plugins/lock/Service.qml`'s `lock()` function returns `"ok"`,
`"missing-pam"`, or `"failed"` on exit 0, or a non-zero exit for anything
else) is classified into exactly four outcomes.
`ACCEPTED` (exit 0, `"ok"`) and `TERMINAL_UNAVAILABLE` (exit 0,
`"missing-pam"` or `"failed"`) both stop retrying outright - a terminal
failure is never reinterpreted as success, and never retried as if it
might resolve itself - while `TRANSIENT_ERROR` (non-zero exit) and
`INDETERMINATE` (exit 0 with empty or unrecognized output) both retry,
bounded by the same 3-attempt budget.
No "is already locked" probe precedes a lock request; Layer 3's own lock
IPC is already idempotent, so adding one here would only introduce a
TOCTOU window between probe and request for no benefit.
`security-idle-policy` drives this exact decision sequence -
`canRequestLock` → increment → classify → `shouldRetryLockResult` -
through 100-iteration adversarial loops for both transient and
indeterminate results (both converge on exactly 3 actual `Process` starts
and 3 final attempts, never 100, with no retry re-permitted after
exhaustion), a terminal failure on the very first attempt (1 start, no
retry), activity or stay-awake arriving while a retry is armed (cancels
it, and the cancelled cycle never resumes attempts on its own), and a
fresh idle cycle after a prior exhaustion (attempts reset to zero, a new
attempt is immediately permitted) - never a shortcut like
`isExhausted(100, 3)`.
`security-idle-qml-behavior` proves the real generated `Service.qml`
drives this same module rather than a disconnected reimplementation of its
rules.

### Stay-awake marker persistence and write-serialization

The pinned stay-awake marker path,
`$HOME/.local/state/omarchy/indicators/stay-awake`, is preserved exactly -
user session state, never `shell.json`.
`omanixy-idle-state` (`packages/omanixy-shell/adapters/idle.bash`) is a new
narrow adapter replacing every upstream bash-string-interpolated state
read/write with three verbs only - `probe`, `set awake`, `set idle` - and
no arbitrary path/eval surface: `probe` exits `0` when the marker exists,
`1` when absent, `2` when a parent directory exists but is unsearchable
(existence is unprovable, so this fails closed as indeterminate rather than
silently reporting absence); `set awake`/`set idle` exit `0` on success or
`2` on failure; any invalid verb, extra argument, or unset/relative `HOME`
exits `2`.
`security-idle-state` proves this ABI hermetically, including the
unsearchable-parent case and idempotent repeats of both `set` verbs.

The generated `Service.qml` preserves the pinned write-serialization
invariant: while a persist `Process` is already running, a further
desired-state request is coalesced into a single pending flag rather than
queued or dropped, and the *last* requested value wins once the in-flight
write completes.
`security-idle-qml-behavior` proves the exact awake→idle→awake-while-first-
write-in-flight sequence the ledger's evidence describes resolves to
awake, not to the first or an intermediate request.
`stayAwakeStateLoaded` starts `false` and `idleEnabled` is defined as
`stayAwakeStateLoaded && !stayAwake`, so idle stays disabled - fail-safe -
until the initial probe actually resolves, and a probe error (exit `2`)
leaves it `false` rather than assuming either state.

### Pinned Quickshell IdleMonitor ABI and the fail-safe no-protocol path

`Quickshell.Wayland`'s `IdleMonitor` (backed by `ext-idle-notify-v1`) is
the sole idle/activity source; `respectInhibitors: true` is set
unconditionally in the generated `Service.qml`, with no option anywhere in
this layer to disable it, and no wall-clock polling or
Hyprland-client-based activity detection is introduced alongside it.
`security-idle-quickshell-contract` proves, as static source-contract
evidence against the pinned revision
(`quickshell-mirror/quickshell@28771c7c74b42e20afca0b1b63980cb46515537c`),
several properties.
`respectInhibitors` defaults to `true` at the C++ property level.
An unsupported protocol (no `IdleNotificationManager` instance) logs a
warning and leaves the notification null - and therefore `isIdle` false,
via the `notification ? notification->bIsIdle.value() : false` binding -
with no fallback timer invented anywhere in the pinned source.
The configured timeout is converted from seconds to milliseconds exactly
once, clamped non-negative, immediately before being handed to the backend.
`respectInhibitors` (after a protocol-version-too-old fallback that forces
it back to `true` with a warning) selects between
`get_idle_notification`/`get_input_idle_notification`.
A missing seat yields `nullptr` rather than a crash or a retry loop.
`idled`/`resumed` map directly onto `isIdle` with no debouncing.
This is static evidence against the pinned revision, not a claim that a
real compositor/inhibitor interaction has been exercised - that remains a
required-before-promotion item, deferred to layer 8, exactly as layer 5's
polkit registration proof already models for a live D-Bus collision.

### Executable surface scanning: a bounded allowlist, learning the layer-5 lesson

`scripts/scan-idle-executable-surface` needs a third scanner shape,
distinct from both prior layers'.
Unlike `security.polkit-agent`'s zero-tolerance invariant (no `Process`
object may exist at all), idle legitimately needs bounded `Process` usage,
so a first-token allowlist alone - the shape layer 3's lock scanner
started from - is not the right invariant either.
The scanner allowlists exactly four exact-argv command forms
(`["omanixy-shell","lock","lock"]`, `["omanixy-idle-state","probe"]`,
`["omanixy-idle-state","set","awake"]`, `["omanixy-idle-state","set","idle"]`)
and, independently and unconditionally, rejects every
`exec`/`execDetached`/`.run(...)` call regardless of argument shape - the
same lesson layer 5's remediation drew when it discovered `Process.command`
is not the only execution API a pinned `Process` type exposes.
An exec/run call is checked *before* an overlapping array-literal match at
the same position, so a `Quickshell.exec([...])` wrapping an
otherwise-allowlisted-looking argv is still rejected, and rejected with
the accurate diagnostic (an exec call was found) rather than a
coincidentally-also-true but misleading one.
`security-idle-executable-surface` proves the real generated `Service.qml`
passes with exactly four command bindings and zero exec/run calls, and a
permanent adversarial matrix covers unknown executables, reintroduced
`bash -c`/`bash -lc` shapes, every removed upstream helper
(`omarchy-launch-screensaver`, `omarchy-system-lock`, `omarchy-system-wake`),
`hyprctl`/`pkill`/`systemctl`/`systemd-inhibit`/`dbus-monitor`, unknown
`omarchy-*` names, dynamic (non-literal) command construction, every
`exec`/`execDetached`/`.run(...)` shape (including one wrapping an
otherwise-allowed-looking argv), and template literals - plus
comment/string false-positive safety and a real disallowed call still
being caught correctly when it follows fake command-looking text.

### `shell.json` ownership and managed-plugin proofs

`security-idle-shell-json` mirrors `security-lock-shell-json` exactly:
enabling idle changes nothing about `shell.json` handling across the same
five starting states (absent, canonical seed, seed with `omarchy.idle`
manually re-enabled, a historical v1 config, and a broken store symlink).
`home.activation.omanixyShellState` is unaffected by
`cfg.security.idle.enable`, and the pre-existing `idle.lock` timeout
override in `shell.json` is preserved untouched either way.
`security-idle-managed-plugin` mirrors `security-lock-managed-plugin`:
`omanixyManagedSecurityPlugins` gains `"omarchy.idle"` when the capability
is enabled, so `isEnabled`/`setEnabled` behave identically to the lock
model - including against a hostile registry state and, separately,
against the real `PluginRegistry.rescan()` scan-and-merge algorithm
pointed at a hostile third-party plugin claiming the reserved
`omarchy.idle` id, which still resolves to the real first-party manifest
under `shell/plugins/services/idle/` (not `plugins/idle`).

### Timeout parsing hardening

`scripts/patch-idle-service` hardens the pinned `secondsFromConfig`
timeout parser beyond the upstream original: a value is floored *then*
checked for being strictly positive, not the reverse.
A naive "check-positive-then-floor" ordering would let a fractional input
between 0 and 1 (for example `0.5`) floor to `0` and recreate exactly the
near-immediate-lock danger a fallback exists to prevent.
Any non-finite, `NaN`, zero, or negative value falls back to the pinned
`300`-second default.
`security-idle-model` drives the real generated `IdleModel.js` directly
and locks this in with an explicit `0.5 -> 300` case alongside the rest of
the matrix (`300 -> 300`, `10.9 -> 10`, `1 -> 1`, `0 -> 300`, `-1 -> 300`,
`"bad" -> 300`, `Infinity -> 300`), and proves the dead screensaver-era
`eventParts`/`screensaverWindowsAfter` helpers are gone from both the
module body and its `module.exports` surface.

### Closure and no-DPMS-widening proofs

`security-idle-closure` compares core+lock against core+lock+idle - never
core-only against idle-only, since idle requires lock - at the same raw
store-path granularity layer 5's `security-polkit-core-only` established.
`declaredRuntimeInputs` is exact-equal (idle rides entirely on the
`coreutils`/`bash` the lock capability's own `runtimeInputs` already
provides, adding no package of its own), the compatibility-bin entry set
gains exactly one helper (`omanixy-idle-state`), no terminal emulator,
`fprintd`, or dedicated notification-daemon package is reachable from the
idle-enabled closure, and after excluding the exact, named set of
Omanixy-owned derivations expected to change identity because the
compatibility root's contents genuinely differ, every remaining external
dependency store path is byte-identical between the two closures.
`security-idle-no-dpms-widening` proves a narrower, absolute claim at the
byte level: Layer 3's own lock plugin `Service.qml` is compared
byte-for-byte before and after idle is enabled, and must be identical -
idle adds zero code to the lock plugin, consistent with never taking on a
second, competing DPMS/hyprctl/brightness/clamshell owner.

### Remediation: revocable trust and Process failure-to-start handling

A follow-up pass to this same layer closes a set of runtime
failure/revocation gaps the initial review left open, without changing
the architecture this ADR already accepted.

Persisted stay-awake trust is now revocable, not merely fail-safe at
startup. `markStayAwakeStateUnknown(reason)` is the one coherent function
every indeterminate signal routes through: it sets
`stayAwakeStateLoaded = false` (which makes `idleEnabled` false
immediately via its own existing binding), cancels any in-flight idle
cycle and armed retry, and - critically - never infers `stayAwake` either
way. "Unknown" is a distinct state from "marker absent"; a probe exit `2`
(or any other unexpected exit) and a probe/writer `Process` that fails to
start both revoke trust through this same path, rather than the previous
behavior of silently doing nothing on exit `2` and having no handling at
all for a failed-to-start `Process`. Recovery is symmetric: a later probe
that actually resolves `0` or `1` restores trust exactly as it does at
startup. `test/security-idle-qml-behavior.sh` proves the revocation and
recovery cycle against the real generated `Service.qml`, including the
case where the idle monitor was genuinely idle at the moment trust was
lost - the fake `IdleMonitor` was extended to model the pinned ABI's own
real coupling (disabling the monitor destroys its live notification, so
`isIdle` falls back to false while disabled), so recovery never
auto-resumes a stale cycle or reuses an exhausted attempt budget; only the
next genuine idle transition starts a fresh one.

Static evidence against the pinned Quickshell `Process` source
(`src/io/process.{hpp,cpp}`) - extending
`security-idle-quickshell-contract` - shows the two ABI transitions this
remediation depends on. A normal finish (`onFinished`) clears the process
handle and emits `exited(exitCode, exitStatus)` before `runningChanged()`.
A process that fails to start (`onErrorOccurred(QProcess::FailedToStart)`)
emits *only* `runningChanged()` - `exited()` is never reachable from that
path at all. There is no QML `onError` signal to catch this case; the
service instead pairs an explicit per-operation `*AwaitingResult` property
(`lockAwaitingResult`, `stayAwakeProbeAwaitingResult`,
`stayAwakeWriterAwaitingResult`) with the real `onRunningChanged` handler,
which schedules exactly one `Qt.callLater` reconciliation when `running`
becomes false while still awaiting a result. The awaiting-result flag is
cleared synchronously inside the ordinary `onExited` handler, so if a
normal exit's own `runningChanged()` fires (in either order relative to
`exited()`) before the deferred reconciliation runs, the reconciliation's
own guard (`!process.running && stillAwaitingResult`) finds the flag
already cleared and does nothing - a normal exit can never be
misclassified as a failed start, regardless of signal ordering.
`test/security-idle-qml-behavior.sh`'s fakes deliberately update the
`running` property before emitting `exited(...)`, exercising exactly the
ordering that would expose a race if the guard were missing.

A lock `Process` that fails to start has already consumed its attempt (the
attempt counter increments in `requestLock()` before `Process.running` is
ever set), so it is treated exactly like `IdlePolicy`'s
`TRANSIENT_ERROR`: the same bounded, non-repeating retry, never refunded,
never a fourth attempt. A 100-iteration synthetic `FailedToStart` stress
sequence in the QML behavior test still caps at exactly 3 actual attempts,
mirroring `security-idle-policy`'s own stress matrix for ordinary exit
failures. A probe or writer `Process` that fails to start revokes trust
through the same `markStayAwakeStateUnknown` path an indeterminate exit
code does; a writer failure while persisting either "idle enable" or
"idle disable" leaves `stayAwakeStateLoaded = false` until a later probe
actually confirms the state, so automatic lock-on-idle can never become
optimistically active from an unconfirmed write. Exactly one coalesced
pending desired-state request - never zero, never a loop - is attempted
after a failed write, preserving the pre-existing latest-request-wins
serialization invariant.

Cancelling an idle cycle (activity, stay-awake, or a trust revocation)
never kills an already-running lock `Process`; the pinned Layer-3 lock IPC
is allowed to complete on its own, and its eventual result is processed
normally against whatever state exists by then - a stale `ACCEPTED`/
`TERMINAL_UNAVAILABLE` is simply a no-op once the cycle has already ended,
and a stale retry request is denied by the same `cycleActive` guard every
other retry decision already uses. Layer 6 never signals or otherwise
interrupts an in-flight lock request.

`scripts/scan-idle-executable-surface` gains a fourth zero-tolerance
rejection alongside `exec`/`execDetached`/`run`:
`Process.startDetached()`, the pinned ABI's real, parameterless,
Q_INVOKABLE method that launches whatever `command` already holds
completely untracked - no `running` transition, no `exited()` ever
possible. Even wrapping an already-allowlisted argv (for example
`p.startDetached()` on a `Process` whose `command` is the exact
`["omanixy-shell", "lock", "lock"]` allowlist entry) is rejected outright,
the same defense-in-depth lesson Layer 5's remediation drew for `exec`/
`execDetached`/`run`: an allowlisted argv is not itself proof of a safe
execution path if a different, untracked API can still launch it.

Finally, `IdleModel.js`'s `secondsFromConfig` gains an upper bound of
`2147483` seconds - `floor(INT_MAX / 1000)`, the largest whole-second
value that survives the pinned Quickshell backend's own
`static_cast<int>(timeout * 1000)` conversion
(`src/wayland/idle_notify/monitor.cpp`) before the `quint32` cast. This
ceiling is derived from that pinned arithmetic range, not an Omanixy
policy preference; any configured value past it falls back to the pinned
300-second default exactly like any other invalid input, preserving the
existing fail-safe behavior rather than silently clamping to the boundary.

`security-idle-package-invariant` closes the one remaining structural
gap: a direct Nix evaluation of `packages/omanixy-shell`'s own
`idleRequiresLockValid` assertion, forced to `.drvPath` with a
hand-constructed `{ idle = true; lock = false; }` security attrset that
never goes through `programs.omanixy.security.idle` or the Home Manager
assertion matrix at all - proving the package-level invariant holds for
any caller, not only ones that reach it through Home Manager.

### Scope

This layer promotes `security.idle` from `blocked`/`blocked` to its
already-declared target of `adapted`/`experimental`, and no other
`security.*` ledger entry; `security.notification-daemon` and
`security.recovery` remain `blocked`.
`experimental`, not `supported`, because every proof in this layer is
hermetic and fake-backend: no real nested Wayland idle transition against
a live `ext-idle-notify-v1` compositor, no real inhibitor actually
suppressing an idle transition, no real activity or lock-on-idle against a
live session, no monitor hotplug/seat change, no suspend/resume while a
cycle or lock request is in flight, no Quickshell crash/restart during an
active idle cycle, and no real declarative-conflict scenario (an actual
running `hypridle`/`swayidle` alongside the Quattro idle owner) has been
exercised.
These remain the ledger's `required_before_promotion` items for this
entry, and are the layer 8 recovery/support gate's responsibility, not a
new follow-up issue.
Omanixy still owns no suspend-on-idle, pre-suspend locking, notification
daemon, or recovery surface, and adds no new systemd unit; the native lock
this layer requests continues to run in-process inside the existing
`omanixy-shell` user service exactly as layer 3 left it.

## Layer 7 implementation note

`4-07-security-notifications` implements the `security.notification-daemon`
ledger entry only, as
`programs.omanixy.security.notifications.daemon.enable` in the Home Manager
module (`modules/home/default.nix`).
Disabled by default, and kept structurally independent of
`programs.omanixy.features` (specifically the existing
`"notification"` client presentation feature) in both directions, matching
the independent-dimension model this ADR already records.
Like layer 6, this layer introduces no new PAM service or system capability
at all - claiming a session D-Bus name is a session-only concern, so there
is no NixOS-side option and no `osConfig` handshake of any kind.

### Bounded ownership split: D-Bus name claim, popup presentation, DND, and bounded history - nothing else

The pinned notification plugin does several things this layer does not want
as one bundle: own `org.freedesktop.Notifications`, present popups, track
DND, persist bounded local history, execute a sender-supplied
`omarchy-exec` shell command hint on click, and fall back to focusing the
sending application's compositor window when no live `default` action
exists.
Layer 7 owns exactly the first four - D-Bus ownership (optional, explicit),
popup presentation, DND, and bounded local history/popup persistence - and
deliberately omits the last two outright, permanently:

- **No `omarchy-exec` execution.** The pinned source reads a
  `hints["omarchy-exec"]` string into a persisted `exec` role, and later
  runs it via `Util.execDetached(command)` when a popup with no live
  `default` action is clicked. This is a real execution path from
  untrusted notification content (any application on the session bus can
  set arbitrary hints) into a shell command, made worse by persistence:
  the command survives shell restarts and can be replayed from disk. The
  adapted `NotificationLogic.js` and `Service.qml` structurally exclude the
  `exec` role from every schema they produce (snapshot, history, popup,
  replacement) - not merely "never called", but never present as a field
  at all - and `Util.execDetached` does not appear anywhere in the adapted
  source. A notification carrying `hints["omarchy-exec"]` still arrives as
  ordinary untrusted data; the daemon simply never reads that hint for any
  purpose.
- **No compositor-focus fallback.** FDO notification ownership does not
  require notification-driven compositor focus mutation. A click with no
  live `default` action now simply dismisses the toast;
  `omarchy-hyprland-focus-app` is not packaged, invoked, or referenced
  anywhere in the adapted source.

Everything else the pinned source does - live tracked notifications,
`replaces_id` update semantics, popup snapshots and expiration,
critical/non-expiring behavior, DND and DND history capture, the 10-entry
history limit, cross-restart popup persistence with restored-row generation
separation, image persistence, clear/dismiss operations, popup placement,
and passive/no-keyboard-focus popup surfaces - is preserved.

### Home Manager option and the daemon-conflict handshake

`security.notifications.daemon.enable` follows the same shape as
`security.idle.enable`: a long-form description documenting session
ownership, independence, and the conflict/unknown-owner boundary, plus a
resolved-state assertion pattern - except there is no prerequisite
assertion at all (unlike idle's `security.lock.enable` requirement),
because claiming a D-Bus name has no dependency on any other Omanixy
security capability.
Four known-conflict assertions - one each for `services.mako.enable`,
`services.dunst.enable`, `services.swaync.enable`, and
`services.fnott.enable` - mirror layer 5/6's own conflict-assertion
pattern exactly: `!cfg.security.notifications.daemon.enable ||
!(config.services.X.enable or false)`, each message ending "Omanixy will
not stop or kill the other daemon for you."
Omanixy does not stop, mask, kill, or otherwise mutate any of the four
known daemons, and does not attempt to detect a daemon it has no
declarative option for; an already-running, undeclared external daemon is
left entirely to the pinned Quickshell `NotificationServer`'s own bounded,
diagnostic registration-conflict behavior (see below), never fought over.

### Pinned Quickshell `NotificationServer` ABI: registration, conflict, and event-driven retry

Static source evidence against `server.cpp`/`server.hpp`/`qml.cpp` proves
the properties the ledger and this ADR rely on: the constructor connects to
the session bus, registers the object at exactly
`/org/freedesktop/Notifications`, watches exactly
`org.freedesktop.Notifications` for unregistration, and calls
`tryRegister()` once; `tryRegister()` calls `registerService(...)` - the
only registration primitive used, with no "replace existing owner" flag -
logs a bounded, one-shot diagnostic on failure, and commits only to
retrying "if the active service is unregistered"; `onServiceUnregistered`
does exactly one thing, call `tryRegister()` again, with no
timer/polling/loop construct anywhere in the registration path; `Notify()`
reuses the existing `idMap` object on a nonzero `replacesId`; and
`keepOnReload` is immutable once the server has gone live.
Omanixy never kills, replaces, or masks another daemon to make its own
daemon win - a live D-Bus collision with a known or unknown external
daemon, and the reverse (an external daemon's disappearance triggering this
daemon's own event-driven re-registration), are real-session behaviors this
ADR does not claim have been exercised; both are `required_before_promotion`
Layer-8 gates.

### Executable surface scanning: literal executable, literal verb, data everywhere else

Unlike lock's bounded-allowlist model (which allowlists exact, complete
argv arrays) or polkit's zero-tolerance model (no `Process` at all), the
adapted notification daemon's commands always carry genuine dynamic data
after a literal executable and verb - a stem, a JSON payload, an image
role, a source path.
`scripts/scan-notification-executable-surface` proves a narrower, ABI-
shaped invariant instead: position 0 must always be the literal string
`"omanixy-notification-state"`, position 1 must always be a literal string
from the fixed, reviewed verb set (`init`, `persist-popup`,
`persist-history`, `archive-popup`, `delete-popup`, `read-popups`,
`read-history`, `clear-history`, `sweep-images`), and every trailing
position may be literal or dynamic without further constraint, since the
adapter's own ABI defines those positions as opaque data it validates
itself at runtime.
As with every other audited plugin, `exec`/`execDetached`/`run`/
`startDetached` are rejected outright, anywhere, regardless of arguments -
the adapted source never calls any of them.

### The `omanixy-notification-state` compatibility adapter

Replacing the pinned source's `bash -c`/`bash -lc` file-state machinery
(`mkdir`, `awk`, `mv`, `rm`, `head`, `stat`, `timeout`, `sort`, one dynamic
`Process` job per mutation) is a single narrow, fixed-domain Omanixy-owned
helper (`packages/omanixy-shell/adapters/notification-state.bash`), reached
only through the fixed verb domain above.
It derives the state root internally from `HOME`
(`$HOME/.local/state/omarchy/notifications{,/history,/images}`, matching
the pinned compatibility path exactly) - no destination or root path is
ever supplied by QML.
A stem is accepted only in the exact generated identity format
(`^[0-9]+-[0-9]+$`, i.e. `<timestamp>-<originalId>`), which alone rules out
a leading slash, `..`, glob metacharacters, and an empty stem.
Image copying is bounded (5 MiB), requires an absolute, readable, regular
source file (a FIFO or device is rejected outright, not blocked on), writes
through an atomic temp-then-`mv`, and always writes beneath the internally-
derived images directory - there is no caller-selected destination, so no
symlink/traversal escape is structurally possible.
A failed or oversized image copy degrades to "no persisted image" and never
fails the surrounding `persist-popup`/`persist-history` call.
History trimming to 10 entries happens inside the adapter itself, keyed by
the same numeric-timestamp-prefixed filename sort the pinned source used.
Exit codes are a strict, documented 0/1/2 ABI (success / not-found-but-
valid / invalid-or-failure) - no backend-specific exit code ever leaks
through it.

### Serialized job queue and `Process` `FailedToStart` handling

The pinned popup-file queue (`popupFileQueue`/`enqueuePopupFileJob`/
`runNextPopupFileJob`/`popupFileProc`) is retained structurally unchanged -
still one shared, serialized `Process`, still a write-then-delete ordering
guarantee - with every command it now runs replaced by a call into the
adapter above.
Applying the layer-6 lesson: the pinned Quickshell `Process` ABI's
`onErrorOccurred(QProcess::FailedToStart)` only ever emits
`runningChanged()`, never `exited()`, so `popupFileProc`, `readHistoryProc`,
and `restorePopupsProc` each gained an explicit `*AwaitingResult` boolean
paired with a real `onRunningChanged` handler plus a single
`Qt.callLater` reconciliation function - a normal `onExited` clears the
flag synchronously first, so a real exit's own `runningChanged()` can never
be misclassified as a `FailedToStart`, regardless of signal ordering.
A failed popup-file job still advances the queue exactly once (via the same
`finishPopupFileJob` path a normal exit uses); a failed history read
degrades to an empty replay and still advances the queue; a failed popup
restore at startup simply restores nothing.
No operation retries autonomously, and no operation is left pending
indefinitely by a start failure.

### `shell.json` and managed-plugin ownership

Mirrors layers 3/5/6 exactly: `omarchy.notifications` is added to
`managedEnabledSecurityPlugins` only when the daemon is selected, forcing
`PluginRegistry.isEnabled("omarchy.notifications")` to `true` regardless of
`disabledPlugins`, and `setEnabled(..., false)` to fail/no-op with the
existing "managed by Omanixy/Nix configuration" diagnostic; a third-party
plugin manifest claiming the reserved `omarchy.notifications` id is
rejected by the real `PluginRegistry.rescan()` merge in favor of the real
first-party manifest.
Enabling or disabling the daemon never mutates `shell.json` under any
starting-state fixture (absent, canonical seed, user-re-enabled, store-
backed symlink, broken symlink) - byte-identical either way.

### Client/daemon and lower-layer closure independence

`security.notifications.daemon.enable` adds exactly one new compatibility
helper (`omanixy-notification-state`) and the notifications plugin tree to
the compatibility root; `declaredRuntimeInputs` is exact-equal to the
daemon-off build (no new package - the adapter rides entirely on the
coreutils/bash the core capability set already provides), and after
excluding the exact, named set of Omanixy-owned derivations expected to
change identity, every remaining external dependency store path is
byte-identical.
The notification-send client feature alone never packages the daemon
plugin tree; the daemon alone never packages the `omarchy-notification-send`
client helper; selecting both together yields exactly their union.
Enabling the daemon alongside every other experimental security capability
(lock, fingerprint, polkit, idle) changes nothing about their own generated
source byte content.

### Remediation: queue provenance, the full generated-QML matrix, and payload bounds

A follow-up pass to this same layer closes a set of hermetic audit gaps a
hostile review of the initial implementation found, without changing the
architecture this ADR already accepted.

The executable-surface scanner's queue-plumbing exemption was, at first,
a bare text match: any occurrence anywhere in the file of `command:
command` or `popupFileProc.command = job.command` was accepted, which
bounded neither how many times the exemption could appear nor proved the
dequeued value ever came from a reviewed literal command. The scanner now
requires the three canonical queue functions (`enqueuePopupFileJob`,
`enqueueHistoryRead`, `runNextPopupFileJob`) to match pinned, reviewed
text exactly once each - the same drift discipline the production patcher
itself uses - and only accepts the two queue-plumbing shapes when they
fall inside one of those three verified blocks. Every `popupFileQueue`
mutation must likewise fall inside one of those blocks.

A second hostile review found that the first version of the
`enqueuePopupFileJob` call-site proof, while requiring the bare
identifier `command` as the argument, traced that identifier back to its
file-global "nearest preceding construction" - a lexical-scope-blind
proof. A function parameter named `command` in an unrelated, attacker-
reachable function could shadow an entirely different, reviewed literal
constructed earlier in the file and be silently accepted, because the
scanner searched backward through the whole file rather than confining
itself to the calling function's own scope. The scanner now pins each of
the six executable producer functions (`persistPopupFile`,
`deletePopupFileFor`, `archivePopupFileFor`, `writeHistoryFile`,
`clearHistory`, `sweepOrphanImages`) as canonical reviewed blocks, exactly
like the three queue functions above, and accepts an `enqueuePopupFileJob`
call site only when it lies inside one of those six pinned ranges - the
one lexical scope where that call's literal `command` construction and
the call itself are proven together. The file-global nearest-preceding
search is gone entirely; there is no longer any path by which a call
outside a producer's own reviewed scope can be accepted, regardless of
parameter shadowing, destructuring, aliasing, nested functions, or
reassignment. A fourteen-case adversarial matrix
(test/security-notifications-executable-surface.sh) proves a second copy
of either queue-plumbing shape, an attacker-controlled call argument, a
dead literal shadowed by a dynamic reassignment, a duplicated or renamed
canonical block, a shadowing function parameter (with and without a
dynamic caller feeding it), a prior-function literal referenced with no
local of its own, a destructured local standing in for the parameter
shadow, a reviewed-looking producer body carrying an extra reassignment,
a parameter named `command` combined with an ambiguous local, and a
duplicated producer block are all rejected, alongside a baseline proving
the full six-producer/three-queue canonical skeleton itself is not a
false positive.

The generated-QML behavior proof now exercises the complete lettered
matrix rather than a subset: replacement identity and content, DND
persistence across a second real service instance sharing the same HOME,
dismiss/expiration archiving driven through the same functions the real
UI calls, a live hostile `omarchy-exec` click actually exercised through
`invokePopupDefault` (not only a structural schema assertion), history
replay built through the real queue/helper, and a corrupt/torn persisted
line skipped without losing either valid neighbor via the real
`restorePopups(raw)` function. A second exact-transform harness fakes
only the three state-persistence `Process` objects' signal/state surface -
every `onExited`/`onRunningChanged` handler, and every reconciliation
function they call (`finishPopupFileJob`,
`reconcilePopupFileJobFailedToStart`, `reconcileReadHistoryFailedToStart`,
`reconcileRestorePopupsFailedToStart`, `runNextPopupFileJob`), is the real
generated production code - and proves FailedToStart handling for all
three Processes, ordering-independent exactly-once completion under both
the pinned and a hostile-reversed `runningChanged`/`exited` ordering, and
a 100-job synthetic FailedToStart stress run that always drains the queue
to zero with no autonomous retry or runaway loop. This is hermetic
Layer-7 evidence, not a Layer-8 concern: Layer 8 owns live session
failure/recovery evidence, not missing offscreen coverage of Layer-7's
own state-machine code.

The `omanixy-notification-state` helper now enforces an explicit 64 KiB
bound on the serialized popup/history payload - independent of, and kept
well clear of, Linux's own separate `MAX_ARG_STRLEN` (32 pages = 128 KiB),
which the boundary tests deliberately stay under so an oversized rejection
proves this bound, not an incidental kernel `exec()` limit. An oversized
payload fails closed (exit 2, no partial JSON artifact); the shared queue
already advances after any non-`FailedToStart` failure exactly as it does
for any other rejected verb, so a bounded rejection never blocks later
notifications. Validation is now fully transactional: HOME, stem, payload
bound, and the complete role/source pair structure are all validated
before any image is copied, so an invalid or duplicate-role later pair in
the same call can never leave an earlier, valid pair's image orphaned with
no corresponding JSON artifact.

### Scope

This layer promotes `security.notification-daemon` from `blocked`/`blocked`
to its already-declared target of `adapted`/`experimental`, and no other
`security.*` ledger entry; `security.recovery` remains `blocked`.
After this layer, the promoted `security.*` entries are exactly
`security.pam-password`, `security.lock`, `security.pam-fingerprint`,
`security.polkit-agent`, `security.idle`, and
`security.notification-daemon`.
`experimental`, not `supported`, because every proof in this layer is
hermetic: no real ownership of `org.freedesktop.Notifications` on a live
session bus, no real `notify-send` delivery, no real replacement-id/close/
action round-trip or DND behavior against a live client, no history/image
persistence proven over a real shell process restart, no real collision
with a known or unknown external daemon, no real external-owner-
disappearance-then-reregistration, and no session D-Bus disappearance/
monitor-hotplug/notification-burst behavior has been exercised.
These remain the ledger's `required_before_promotion` items for this
entry, and are the layer 8 recovery/support gate's responsibility, not a
new follow-up issue.
Omanixy still owns no recovery surface and adds no new systemd unit; the
adapted daemon continues to run in-process inside the existing
`omanixy-shell` user service, and D-Bus ownership when selected belongs to
the Quickshell `NotificationServer` inside that same process - there is no
second lifecycle supervisor.

## Layer 8 implementation note

`4-08-security-recovery` implements the `security.recovery` ledger entry
and is the final promotion gate for issue #4. It is not a new runtime
feature layer: it owns complete failure/recovery validation, nested/live
evidence, lifecycle hardening only where a real test exposed a defect, and
the final compatibility/support ledger cleanup. It adds no
`programs.omanixy.security.recovery` option, no recovery daemon or
dispatcher, and no new systemd unit; recovery behavior remains owned by the
services Layers 2-7 already selected and the existing `omanixy-shell`
service lifecycle.

### First live test topology in this repo

Every prior layer's evidence was either a static pinned-source audit,
hermetic Nix-evaluation/build-sandbox assertions, or an offscreen Quickshell
run with specific native objects (`IdleMonitor`, `WlSessionLock`,
`PanelWindow`, the native `PolkitAgent`/`NotificationServer` listener)
test-doubled - real rungs 4-5 of the Promotion gate ladder (nested
compositor, live manual/hardware evidence) had never been attempted. Layer 8
introduces `pkgs.testers.runNixOSTest`-based checks: real booted NixOS VMs,
built from the actual `nixosModules.default`/`homeManagerModules.default`
this flake ships, with a disposable VM-only test user and a disposable
fixture password that has no value outside that VM. This host has KVM and
the `nixos-test` Nix system feature, so these checks build and run locally
exactly as `nix flake check` would run them elsewhere with the same
features.

### Nested-compositor environment limitation: lock, idle, suspend/resume

Quickshell's `PamContext`, the native `PolkitAgent` object, and
`NotificationServer` do not require a live Wayland connection - only their
own presentation surfaces (`WlSessionLockSurface`, `PanelWindow`) do, and
Quickshell's QPA platform can be `offscreen` for all three. `WlSessionLock`
and `IdleMonitor`, by contrast, are Wayland-protocol objects that fail to
construct without a live compositor. Layer 8 investigated two independent
topologies to provide that compositor, both genuinely attempted, both
recorded with exact evidence rather than assumed.

The first attempt ran the pinned Hyprland 0.55.4 headless inside the VM
directly: Aquamarine (Hyprland's backend abstraction) mandates its headless
backend at startup, but that backend's `drmFD()` is hard-coded to `-1` and
Aquamarine requires a DRM-capable implementation to supply the shared GBM
allocator. With the VM's virtio-gpu render node present
(`/dev/dri/renderD128`) and the `vgem` kernel module loaded, `CBackend::
start()` still aborted before Hyprland reached a usable state; Hyprland's
own diagnostic log is written to a runtime-directory file that was never
flushed before its `SIGABRT` crash handler ran, so the exact downstream
allocator failure could not be captured either.

Before accepting that as final, Layer 8 also investigated a second
topology per issue #4's Section 24: nesting the same pinned Hyprland inside
a test-owned headless Weston 15.0.1, entirely as disposable scratch test
infrastructure (never added to this repo or to production). Aquamarine's
Wayland backend was first confirmed to genuinely exist at this exact pin
(`aquamarine/src/backend/Wayland.cpp`'s `CWaylandBackend::start()` calls
`wl_display_connect` and binds `wl_seat`/`xdg_wm_base`/`wl_compositor`/
`wl_shm`/`zwp_linux_dmabuf_v1`, with its own `drmFD()` independent of the
headless backend's hard-coded `-1`), then a real `pkgs.testers.
runNixOSTest` scratch VM started Weston headless, confirmed its Wayland
socket was reachable, and started the pinned Hyprland against it with
`WAYLAND_DISPLAY` pointed at that socket. Hyprland's backend-selection
logic did genuinely attempt the Wayland path this time - further than the
first attempt ever reached - but crashed with a fully captured, exact
Wayland protocol error: `wl_registry#2: error 0: invalid version for global
wl_compositor (1): expected at most 5, got 6`. Aquamarine 0.13.0 (bundled
with Hyprland 0.55.4) hard-binds `wl_compositor` interface version 6 via
`wl_registry_bind` with no clamp to what the outer compositor actually
advertises, and Weston 15.0.1 only advertises version 5 - a real,
independent Wayland core-protocol version mismatch between this exact
Aquamarine/Weston pairing, unrelated to the first attempt's DRM-allocator
failure, and this time captured in full rather than lost before a crash
handler ran.

Both are limitations of this KVM/QEMU host and these exact pinned versions,
not a defect in the audited lock, idle, or polkit-agent modules, and both
are recorded honestly rather than worked around: `security.lock`,
`security.idle`, and `security.polkit-agent` each carry the
nested-compositor items that depend on it under `required_before_supported`
(not `required_before_promotion` - all three entries already reached their
`adapted`/`experimental` target at their own layer), and
`upstream/security-recovery-matrix.yaml` records the specific cases
(`recovery.lock-nested-compositor`, `recovery.idle-nested-compositor`,
`recovery.polkit-nested-compositor`, `recovery.notifications-monitor-
hotplug`, `recovery.suspend-resume`) as `unsupported-environment` with both
attempts' exact reasoning in `attempted_evidence`, not `passed`. The
existing offscreen fake-`WlSessionLock`/fake-`IdleMonitor` evidence from
Layers 3 and 6 remains the available evidence for the lock and idle logic
itself; only live nested-compositor protocol evidence is unavailable here.

### PAM live conversation and the no-`pam_faillock` decision

`test/security-recovery-pam-vm.nix` drives a minimal QML harness
instantiating the same pinned `Quickshell.Services.Pam.PamContext` type the
production lock plugin uses, `config: "omarchy-lock-password"`, against the
real generated `/etc/pam.d/omarchy-lock-password` service in a booted VM -
not the full production lock QML tree, which also instantiates
`WlSessionLock` and would hit the same nested-compositor limitation. This
gives real evidence for the exact PAM ABI the lock depends on, independent
of the lock's own Wayland-bound presentation. It proves: a correct fixture
password authenticates; a wrong password fails without installing any
lockout state; at least 20 consecutive wrong attempts leave the session
still unauthenticated, the harness alive, log growth bounded, and a
subsequent correct password still able to authenticate; cancelling an
in-flight conversation aborts it distinctly from a failure; and with the
PAM service absent, PAM start fails distinctly from an authentication
failure, with no fallback to any other authentication path. The repeated-
failure result is the live proof behind Layer 2's decision to omit
`pam_faillock`: a lock-screen lockout policy remains a deliberate v0.1
omission, confirmed under real load, not a gap.

The same file also drives `omanixy-shell.service` in the VM with no Wayland
compositor present at all - a genuine, not synthetic, failure condition -
and observes the unit's real `Restart=on-failure`/`RestartSec=2s`/
`StartLimitBurst=5`/`StartLimitIntervalSec=60s` bound the failure to a
finite restart count rather than looping forever, and that
`systemctl reset-failed` plus a fresh start is accepted afterward (it fails
again for the same Wayland-absence reason, which is expected - the point is
proving the bound, not a live compositor).

### Fingerprint no-device and daemon-unavailable behavior

The same harness enables `programs.omanixy.security.pam.fingerprint.enable`
with no fingerprint reader present in the VM and proves the fingerprint PAM
path fails closed while password authentication remains available -
fingerprint never replaces password. Enrolled physical hardware and a real,
non-fixture TOD driver remain unavailable in this environment and stay
under `required_before_supported`, exactly as Layer 4 already anticipated;
this is not a blocker for the `experimental` target.

### Polkit real registration, authentication, and recovery

`test/security-recovery-polkit-vm.nix` drives a minimal harness
instantiating the pinned `PolkitAgent { path: "/org/omarchy/PolkitAgent" }`
object (no `PanelWindow`) against a real, running `polkitd` in a booted VM.
It proves: real registration succeeds; a real authentication request
against a test-only polkit action succeeds for the correct fixture password
and fails for a wrong one; user- and daemon-initiated cancellation both
close the flow without a stale state; registering against an
already-registered independent agent fails diagnostically and boundedly
without killing, stopping, or masking that agent (the pinned Quickshell ABI
has no event-driven re-registration on a competitor's departure the way the
notification daemon does - Layer 8 confirms that documented behavior rather
than inventing a retry loop); and `polkitd` restarting mid-request does not
hang the requester forever, with a fresh request succeeding once `polkitd`
returns - notably, even the same pre-restart harness process could complete
a fresh request afterward, suggesting the underlying D-Bus agent-listener
layer reconnects transparently on the bus name reappearing, a lower layer
than the no-retry registration policy the collision case documents, and
both that same-harness reconnect and a fresh-harness reconnect are asserted,
not just one printed and the other merely documented. It additionally
proves a finite, bounded real stress run (20 consecutive wrong-password
authentication cycles) with an exactly-one-process invariant and a
generous, stimulus-proportional event-log bound that stops growing once the
stress stops (`recovery.polkit-stress-finite`), and, from
`test/security-recovery-cross-feature-vm.nix`, that killing the shell
process mid-authentication against the real agent - the one live-process
gap the original required_before_supported list called out - leaves the
stranded `pkcheck` client bounded and a fresh process re-registering and
authenticating cleanly (`recovery.polkit-crash-midauth`). Live evidence
against a real Wayland session for the agent's own `PanelWindow`
presentation remains unavailable for the same nested-compositor reason as
lock and idle (`recovery.polkit-nested-compositor`), and a larger,
hundreds-of-cycles stress run beyond the finite 20-cycle one just proven
stays under `required_before_supported`.

### Notifications real D-Bus ownership and collision behavior

`test/security-recovery-notifications-vm.nix` drives a minimal harness
instantiating the pinned `Quickshell.Services.Notifications.NotificationServer`
type (no `PanelWindow`) against a real session bus in a booted VM. It
proves: `org.freedesktop.Notifications` gets a real owner and a real,
independent client's notification is delivered end to end; a replacement id
updates the same identity with no duplicate row; a default action fires
exactly once; `CloseNotification` round-trips; DND suppresses popups per the
real daemon's own history policy and persists across a restart; an unknown
independent process that claims the name first is never killed or replaced,
and once it releases the name the daemon claims it event-driven with no
restart required (the distinction from polkit's registration behavior,
confirmed live here); and a finite notification burst leaves the daemon
alive with bounded persisted state and a bounded, non-growing log volume,
asserted rather than merely printed. It additionally proves
notification-daemon-specific session D-Bus disappearance/recovery
(`recovery.notifications-session-bus-lifecycle`): genuinely destroying this
test user's real login session and D-Bus user-session bus - stopping the
owning transient unit from outside with lingering disabled, confirmed by
the user manager reaching `SubState=dead`, never simulated by sleeping -
and then establishing a fresh session lets a fresh daemon instance claim
`org.freedesktop.Notifications` and deliver again.

A collision specifically with a by-name known daemon (mako/dunst/swaync/
fnott actually running) was not attempted live: those are wlr-layer-shell
or X11 daemons whose own core service loop depends on the same live
Wayland session this layer's nested-compositor investigation already found
unavailable (see "Nested-compositor environment limitation" above), so a
live attempt was judged unlikely to add evidence beyond that
already-established dependency; it stays under `required_before_supported`
as `recovery.notifications-known-daemon-collision`, with that reasoning
recorded rather than assumed. Monitor hotplug with popups visible on a live
compositor (`recovery.notifications-monitor-hotplug`) remains unavailable
for the same nested-compositor reason as lock, idle, and polkit's
presentation.

### Cross-feature boot and crash recovery

`test/security-recovery-cross-feature-vm.nix` selects PAM, the polkit agent,
and the notification daemon together in one booted VM (fingerprint hardware
is naturally absent; lock/idle are excluded because they depend on the same
unavailable nested compositor) and proves the shell boots with no ownership
conflicts, each surface independently reachable, and no extra PAM/D-Bus
daemon spawned. It then establishes real simultaneous state on all three
surfaces at once - an in-flight PAM conversation, an in-flight polkit
authentication request, and a live notification with a pending default
action - and `SIGKILL`s the shell process; the stranded polkit request does
not hang forever (`polkitd`'s own fallback closes it boundedly), and a
fresh shell process (standing in for the systemd-bounded restart the PAM
test's own scenario 6 already proves directly against the real unit)
registers cleanly with no stale "already registered" conflict, restores
the pre-crash notification as data-only with no action resurrected, and
succeeds at a fresh PAM conversation, a fresh polkit authentication, and a
fresh notification delivery.

### Ledger promotion-semantics cleanup

Every already-promoted `security.*` entry (Layers 2-7) previously carried a
`required_before_promotion` list even though it had already reached its
declared target - conflating "still needed to reach the target this layer
promotes to" with "still needed for some hypothetical future move to
`supported`". Layer 8 makes this coherent: `required_before_promotion` is
now empty or absent on every promoted entry, and a `required_before_supported`
list carries only genuine hardware- or environment-specific breadth (real
fingerprint hardware, a real TOD driver, live nested-compositor validation,
real lid hardware) - never a reason to withhold the `experimental` target,
and never silently reported as passed. `test/security-contracts.sh` and the
new `test/security-recovery-contract.sh` enforce both halves of this rule.

### Final support-state decisions

No `security.*` entry reaches `support: supported` after this layer; the
target for every entry, including `security.recovery` itself, remains
`adapted`/`experimental`. Specifically, and unchanged from their originating
layers: `pam_faillock` is not adopted (confirmed under real repeated-failure
load in this layer, not merely decided); `pam_systemd_home` is not adopted,
the v0.1 backend is ordinary shadow-backed Unix accounts via `pam_unix`
only; Omanixy does not own system suspend/sleep policy - no
`omarchy-system-sleep-monitor`, `omarchy-sleep-lock.service`,
`systemd-inhibit` listener, or automatic pre-suspend lock owner is
introduced by this or any layer, by design, not omission, and
`test/security-contracts.sh` bans that vocabulary from `modules/home`; no
laptop lid/clamshell policy is introduced, real lid hardware validation
stays `required_before_supported`; and third-party QML plugins execute
unsandboxed inside the same shell process as every security-sensitive
surface, which remains documented rather than hidden and is one reason
every native security integration stays experimental rather than supported.

### Scope

This layer promotes `security.recovery` from `blocked`/`blocked` to its
already-declared target of `adapted`/`experimental`, and re-states (with
`required_before_promotion` cleared and `required_before_supported`
populated where genuinely outstanding) the six entries Layers 2-7 already
promoted: `security.pam-password`, `security.lock`,
`security.pam-fingerprint`, `security.polkit-agent`, `security.idle`, and
`security.notification-daemon`. After this layer, all seven `security.*`
ledger entries are promoted to their declared target and no entry remains
`blocked`. `experimental`, not `supported`, for `security.recovery` and for
every entry it depends on, because live nested-compositor evidence for the
native lock and idle surfaces, enrolled fingerprint hardware, a real TOD
driver, and real lid hardware all remain genuinely unavailable in this
environment and are recorded as such rather than faked; every case this
layer could exercise against a real backend in a booted VM - PAM, polkit,
and the notification daemon - passed. `programs.omanixy.security.*` options
all remain default `false`. Every `security.*` entry remains `maturity:
audited`. Issue #4 remains open until this layer's pull request merges.
