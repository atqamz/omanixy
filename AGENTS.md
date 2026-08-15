# Omanixy Agent Contract

## Project

Omanixy is the Nix-native integration layer for the Omarchy Quattro desktop
shell.

Omarchy owns presentation.
NixOS owns the operating system.
Omanixy owns the boundary.

The target architecture consumes a reviewed and pinned upstream Quattro shell
rather than broadly reimplementing its presentation in Nix.
Issue #2 owns selecting and validating the concrete Quattro and Quickshell
runtime pair.
It provides generic, composable NixOS and Home Manager integration for public
consumers.

The repository remains named `omanixy`.
Use `omanixy-shell` only for runtime or service terminology, such as
`omanixy-shell.service`.

## Authority

- The human is the implementer and final decision-maker.
- The AI coordinates, teaches, reviews, verifies, documents, and performs
  approved repetitive operations.
- Default role is peer. The AI must challenge decisions and review actual
  repository state without taking over implementation.
- Never assume permission to push, force-push, rebase, amend, delete, reset,
  discard changes, or commit.
- `finish task <id>` grants permission to create one commit containing only
  the completed task.
- `ship task <id>` grants permission to push that completed work.

## Source Of Truth

Before working, read:

1. `AGENTS.md`
2. The active task under `tasks/`
3. `docs/architecture.md`
4. `docs/porting-principles.md`
5. `upstream/omarchy.yaml`
6. Relevant entries in `upstream/porting-matrix.yaml`

Do not rely on conversation memory when repository documentation answers the
question.

## Task Workflow

Every task must contain objective, motivation, dependencies, relevant
upstream files, expected Omanixy files, acceptance criteria, verification
commands, and status.

Valid statuses are `proposed`, `ready`, `in-progress`, `blocked`, `review`,
and `done`.

Only one primary task may be active per working tree.

## Peer Workflow

When mentoring or supervising:

- Give one meaningful checkpoint at a time.
- Explain why the checkpoint matters.
- Let the human implement it.
- Review actual repository state rather than assuming completion.
- Do not modify or commit implementation changes unless explicitly requested.

## Finish Task Workflow

When the human says `finish task <id>`:

1. Read the task and acceptance criteria.
2. Inspect `git status --porcelain=v1`.
3. Run `just fmt` and `just check`.
4. Stop if required checks fail.
5. Identify files belonging to the task.
6. Stage explicit task-related paths only.
7. Inspect `git diff --cached`.
8. Generate a Conventional Commit message from the staged snapshot.
9. Commit without bypassing hooks.
10. Report the commit hash, checks performed, and remaining changes.

## Git Safety

Never use `git reset --hard`, `git clean -fd`, `git checkout --`, destructive
`git restore`, `git rebase`, `git commit --amend`, force push, or
`git commit --no-verify` without explicit permission.

Never stage secrets, credentials, generated build results, or unrelated files.
Prefer explicit paths over `git add -A`.

## Commit Format

Use `<type>(<scope>): <summary>`.

Allowed types: `feat`, `fix`, `refactor`, `docs`, `test`, `build`, `ci`,
`chore`, and `perf`.

Use `Task: OMX-###` and `Upstream: basecamp/omarchy@<revision>` footers where
applicable.

## Verification

The canonical verification command is `just check`.

Formatting is performed with `just fmt`.

Narrower checks are encouraged during development, but `just check` must pass
before committing.

## NixOS Module Principles

- Use `lib.mkDefault` for opinionated defaults users should override.
- Expose options instead of requiring users to copy internal modules.
- Keep modules independently importable where practical.
- Avoid modifying unrelated user configuration.
- Keep public modules independent of Universe, personal paths, and
  machine-specific policy.
- Keep user/session integration in Home Manager and privileged/system
  capability integration in the NixOS module.
- Do not broadly reimplement upstream Quattro QML or the complete Omarchy
  Hyprland configuration.
- Inspect upstream contracts rather than copying incidental scripts.
- Document behavior that is `exact`, `adapted`, `omitted`, or `blocked`.
- Mark each porting-matrix item `exact`, `adapted`, `omitted`, or `blocked`.

## Upstream Policy

- Never port from an unpinned upstream branch.
- Every port references the pinned release and revision.
- Never silently copy behavior from a newer Omarchy version.
- Upstream upgrades are dedicated tasks with their own review and commits.
- Issue #2 selects and validates the concrete Quattro and Quickshell runtime
  pair.
- Issue #3 owns the contract audit and compatibility ledger.
- A narrow adapter is preferred over a downstream presentation fork.
- Universe is a downstream consumer and must never become a public module
  dependency.
