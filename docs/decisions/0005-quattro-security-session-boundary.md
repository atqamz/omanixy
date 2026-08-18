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

`security.pam.services.<name>.text` is typed `nullOr lines`, so ordinary
same-priority definitions merge by newline concatenation; an unrelated normal
module that also defined this service's `text` would silently extend the
authentication stack. This layer's `config` sets the service text via
`lib.mkForce`, so while the option is enabled Omanixy owns the entire text of
`omarchy-lock-password` atomically and a competing normal-priority definition
is discarded rather than merged.

`pam_unix.so` shells out to a setuid `unix_chkpwd` helper to read the shadow
database; nixpkgs's own `security/pam.nix` unconditionally registers
`security.wrappers.unix_chkpwd` (setuid root, sourced from the same pinned
`linux-pam` package) independent of which PAM services are enabled, so this
layer neither vendors nor duplicates that privileged helper.

A build fixture
(`pamPasswordAdversarialNixosConfiguration` in `flake.nix`, checked by
`security-pam-composition`) proves the generated file is byte-identical
whether or not such a competing definition is present. A consumer who wants a
different policy for this service must disable this option rather than add to
it; this layer adds no imperative conflict resolution and does not delete or
mutate any other file.

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
