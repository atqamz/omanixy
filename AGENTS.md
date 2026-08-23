# Omanixy Agent Contract

## Project

Omanixy is the Nix-native integration layer for the Omarchy Quattro desktop
shell.

Omarchy owns presentation.
NixOS owns the operating system.
Omanixy owns the boundary.

The target architecture consumes a reviewed and pinned upstream Quattro shell
rather than broadly reimplementing its presentation in Nix.
Issue #2 selected and validated the concrete Quattro and Quickshell runtime
pair.
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
- An explicit request to implement authorizes changes within the stated scope.
- Commit only when explicitly authorized.
- Push and pull request creation only when explicitly authorized.
- Never assume permission to force-push, rebase, amend, delete, reset,
  discard changes, or perform other destructive Git operations.

## Source Of Truth

Before working, read:

1. `AGENTS.md`
2. The active GitHub Issue
3. `docs/architecture.md`
4. `docs/porting-principles.md`
5. `upstream/omarchy.yaml`
6. Relevant entries in `upstream/porting-matrix.yaml`
7. Relevant implementation and test files

Read the actual GitHub Issue when executing issue work.
Do not duplicate the issue body into a repository file or create a second work
database.
If an execution brief and the GitHub Issue conflict, stop and resolve the
conflict before changing files.

## GitHub Workflow

GitHub Issues define work, including objectives, scope, dependencies,
acceptance criteria, and discussion.
GitHub pull requests carry implementation state, review, verification, and
discussion.
ADRs and repository documentation preserve durable product knowledge.
`upstream/porting-matrix.yaml` preserves durable compatibility state.
Git history preserves the historical implementation record.

Use one primary issue per focused branch and pull request where practical.
Use a draft pull request during implementation and link it to its issue with a
closing keyword when appropriate.
Do not add a local issue cache, work registry, issue synchronization script, or
second issue identity system.

An issue may depend on another issue, but GitHub remains the work lifecycle
authority.

## Peer Workflow

When mentoring or supervising:

- Give one meaningful checkpoint at a time.
- Explain why the checkpoint matters.
- Let the human implement it.
- Review actual repository state rather than assuming completion.
- Do not modify or commit implementation changes unless explicitly requested.

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

Use an `Upstream: basecamp/omarchy@<revision>` footer where source provenance
is technically useful.
Use GitHub pull request linkage for issue identity rather than a mandatory
commit footer.

## Verification

The canonical verification command is `just check`.

Formatting is performed with `just fmt`.

Narrower checks are encouraged during development, but `just check` must pass
before committing.

## Release rules

- Release semantics follow `docs/release.md`.
- The final squash title is the release-significant Conventional Commit.
- Do not manually edit version-managed files outside bootstrap or a Release PR.
- Do not manually create release tags or GitHub Releases.
- Breaking public changes require usable migration notes.
- `v1.0.0` requires an explicit project stability decision.

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
- Upstream upgrades are dedicated GitHub issues with their own review and
  commits.
- Issue #2 selected and validated the concrete Quattro and Quickshell runtime
  pair.
- Issue #3 owns the contract audit and compatibility ledger.
- A narrow adapter is preferred over a downstream presentation fork.
- Universe is a downstream consumer and must never become a public module
  dependency.

## Source Comments

Do not add narrative source comments or docstrings.
Express behavior through code and test names.
Put durable rationale in `docs/` or an ADR.
Preserve only checker-recognized machine directives (see CONTRIBUTING.md).
Run the source-comment-policy check before publishing changes.
