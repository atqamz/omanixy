# Releases

## Scope

Omanixy releases describe one reviewed Omanixy public API and support contract.

The version is independent from Omarchy, Quattro, Quickshell, and nixpkgs versions.

Each release records the exact tested upstream pair and the compatibility state that was reviewed with it.

Omanixy releases create a Release PR, update the version and changelog, create a SemVer tag, and create a GitHub Release.

No package registry, Nix registry, binary archive, install script, or release asset publication is part of this contract.

Consumers can use a release directly with `github:atqamz/omanixy/vX.Y.Z`.

## SemVer policy

Omanixy uses SemVer with a pre-1.0 development line.

While the current major version is zero, `fix:` and `perf:` changes are patch-level, `feat:` changes are minor-level, and breaking changes are next-minor changes.

`bump-minor-pre-major` is enabled and `bump-patch-for-minor-pre-major` is explicitly disabled.

No ordinary Conventional Commit can produce `1.0.0` while the current version is `0.x.y`.

`v1.0.0` requires an explicit project stability decision and a `Release-As: 1.0.0` commit footer or the current equivalent Release Please mechanism.

Permanent `release-as` configuration is prohibited because it would silently override Conventional Commit history.

Upstream version numbers never map mechanically to Omanixy SemVer.

For example, a compatible tested pin correction is `fix(upstream): update the tested Quattro revision`, a new public capability is `feat(upstream): support the new panel`, and an incompatible public configuration change is `feat(config)!: redesign the shell configuration` with migration guidance.

## Bootstrap and first release

Omanixy has no public `v0.0.0` release.

The manifest and `version.txt` value `0.0.0` are Release Please's pre-first-release baseline.

Current Release Please requires `initial-version: 0.1.0` for an untagged first release because a manifest baseline is not treated as the latest published release by the current strategy.

This is a first-candidate bootstrap guard, not a `release-as` override and not a public `v0.1.0` release.

`ce7d3d8b53bec61585ca9efa377fdb3ae6763499` is the bootstrap boundary because it is the architecture and workflow baseline.

The next commit, `c756f85dc2ad546fa2cfbad1fdf3b51913bc6723`, is the first pinned Quattro runtime implementation and is included in the first release history.

The boundary excludes earlier repository-bootstrap scaffolding while retaining runtime implementation, compatibility adapters, security layers, and relevant repository hardening.

The first generated candidate is expected to be `v0.1.0` with tag `v0.1.0`.

This issue does not merge the first Release PR, create a tag, or create a GitHub Release.

The first Release PR remains a draft until `atqamz/omanixy#6` proves standalone public usability and the project explicitly approves release readiness.

## Conventional Commits and changelog sections

Normal pull requests should be squash-merged.

The final squash title is the semantic mainline commit consumed by Release Please.

Use titles such as:

```text
fix(audio): preserve selected default sink
feat(network): add NetworkManager Wi-Fi controls
feat(config)!: redesign shell plugin configuration
chore(ci): refresh action pin
```

`feat` is visible and release-bearing at minor level.

`fix` is visible and release-bearing at patch level.

`perf` is visible and release-bearing at patch level under current Release Please semantics.

`revert` is visible.

`docs`, `test`, `build`, `ci`, and `chore` are hidden and do not independently justify a release.

Ordinary `refactor` changes do not independently justify a release, while breaking refactors retain visible breaking notes.

Any `!` marker or `BREAKING CHANGE:` footer describes a breaking public contract regardless of the commit type.

Fixup, WIP, and review-remediation commits should not become the final mainline semantic unit when squash merge can present the actual change.

## Migration notes

An intentional breaking public API change requires a usable `### Migration` section in the candidate release entry.

The release-context checker rejects an absent, empty, or placeholder migration section for a candidate containing breaking notes.

The checker does not infer migration instructions from source code.

Use a commit such as:

```text
feat(config)!: replace legacy shell configuration shape

BREAKING CHANGE: programs.omanixy.foo was replaced by programs.omanixy.bar.
Migration: move the option and preserve the documented default.
```

Non-breaking candidates may omit the section or use an explicit `None.` statement.

## Release-owned files

The release workflow owns release-file mutation.
Release Please owns version calculation, manifest and version updates, release-note generation, tags, and GitHub Releases.
The `scripts/release-context` tool owns only the deterministic `Upstream` and `Compatibility` sections.
Humans own reviewed `Migration` guidance.

Normal feature, fix, and documentation pull requests must not casually edit those files.

The intentional human-curated release-file change is migration guidance inside the pending Release PR.

No runtime QML, Nix module option, flake metadata, README version, or package metadata mirrors the release version.

There is no runtime version command or version label in this release system.

## Compatibility context

The `scripts/release-context` tool reads `upstream/omarchy.yaml` and `upstream/porting-matrix.yaml` on every invocation.

It requires the validated Omarchy Quattro and Quickshell pair, renders their exact revisions, summarizes compatibility classifications and support states, and links to the full ledger.

The normal flow is:

```text
successful main CI for the current main SHA
        |
        v
Release Please creates or updates a pending Release PR, initially as a draft
        |
        v
the pending Release PR is found and checked out
        |
        v
Nix is installed for release-context --write and --check
        |
        v
release-context --write and --check update the candidate changelog
        |
        v
GitHub creates approval-required CI for the current generated Release PR head
        |
        v
a maintainer approves workflows to run
        |
        v
ordinary CI validates that exact Release PR head
        |
        v
human reviews context and migration guidance and may mark the PR ready
        |
        v
later validated main changes update the same pending Release PR and its context
        |
        v
the new current head requires fresh approved CI before merge
        |
        v
human merges when release readiness is approved
```

The context writer is idempotent and owns exactly one `Upstream` and one `Compatibility` section in the candidate entry.

The final changelog entry already contains the context before the Release PR is merged, so the GitHub Release body inherits the reviewed information.

## Workflow and credentials

CI runs on pull requests targeting `main` and pushes to `main` with `contents: read`.

CI runs formatting, `just check`, all-system flake evaluation, source-comment policy, release contract checks, release-context selftests, actionlint, and the release-owned-file context check when those files change.

Release Please runs only from a successful `CI` `workflow_run` for a push whose SHA is checked against live `main` immediately before the action is invoked.
At that final mutation boundary, the workflow skips Release Please and all later release-context work when the live SHA differs.
This check does not provide an atomic compare-and-swap with GitHub branch movement.
It establishes the strongest practical stale-at-boundary guarantee available while the upstream action targets symbolic `main`.

The release workflow has a single global `release-main` concurrency group with cancellation disabled.

Release automation is repository-secretless.
The release workflow uses GitHub's ephemeral repository-scoped `GITHUB_TOKEN` with explicit `contents: write`, `pull-requests: write`, and `issues: write` permissions.
No personal access token, GitHub App credential, or custom release secret is required.

GitHub suppresses most recursive workflow events created by `GITHUB_TOKEN`, but `pull_request` `opened`, `synchronize`, and `reopened` events created by workflow automation produce approval-required workflow runs.
A maintainer with write access approves those runs from the Release PR before CI executes.
This explicit approval is part of the human release gate rather than a credential workaround.

Only CI for the current Release PR head counts as release validation.
Any Release Please update, compatibility-context commit, or human migration edit that changes the head invalidates older CI evidence and requires validation of the new head.
Draft state and CI approval are independent: a draft candidate may have green CI, and a ready candidate may not merge with stale, pending, unapproved, or failed CI.

The repository must allow GitHub Actions to create pull requests with `GITHUB_TOKEN` in its Actions workflow-permission setting.
That repository setting is not a secret and does not introduce token provisioning or rotation.
A separate credential may be introduced later only for a concrete capability that cannot be acceptably expressed with `GITHUB_TOKEN` and the existing human gate.

## Failure recovery

If CI fails on `main`, the Release Please workflow does not run.

If the successfully validated main revision is stale at the final mutation boundary, Release Please and all later release-context work are skipped.

If the Release Please API fails, the workflow is red and must be rerun after the transient or repository-permission problem is corrected.

If Release PR CI is awaiting approval, the candidate is not validated yet.

If Release PR CI fails, the draft must not be merged.

If a Release PR head changes after a green run, the previous CI evidence is stale and does not authorize the new head.

If release context is stale, malformed, duplicated, or missing migration guidance, Release PR CI fails until the human-curated entry is corrected.

If tag or GitHub Release creation fails, the workflow remains red and no alternate version, tag, or release is invented manually.

The workflow has no unrestricted manual dispatch recovery path.

The next successful validated `main` CI run updates the existing pending Release PR.

## Supply-chain and publication boundary

The introduced actions are `actions/checkout@v7`, `DeterminateSystems/nix-installer-action@v22`, and `googleapis/release-please-action@v5`.

The release action currently runs on Node 24 and uses the current manifest configuration contract.

Action majors and required permissions are checked by repository actionlint and the release contract test.

No npm, PyPI, crates.io, Cachix, Nixpkgs, Nix registry, Homebrew, AUR, binary archive, or install-script publication exists here.
