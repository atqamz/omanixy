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
