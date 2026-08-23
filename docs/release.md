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

The pinned Release Please runtime uses `initial-version: 0.1.0` for the untagged first release because the manifest baseline is not itself a published release.

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

CI allows `.release-please-manifest.json`, `version.txt`, or `CHANGELOG.md` to change only for the one-time bootstrap where all three files are absent from the base revision, or for a same-repository pending Release PR authored by `github-actions[bot]` and carrying the `autorelease: pending` label.
A human may edit migration guidance on that pending Release PR without changing the PR's automation provenance.
A label alone is not sufficient to authorize a normal PR to mutate release-owned files.

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
the candidate must be same-repository, github-actions[bot]-authored, and autorelease: pending
        |
        v
live main and the pending Release PR base are revalidated against that CI SHA
        |
        v
the pending Release PR is checked out
        |
        v
Nix is installed for release-context --write and --check
        |
        v
live main is revalidated before release-context mutation and before its push
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

CI runs formatting, `just check`, all-system flake evaluation, source-comment policy, release contract checks, release-context selftests, actionlint, and release-owned-file provenance and context checks when those files change.

Release Please runs only from a successful `CI` `workflow_run` for a push whose SHA is checked against live `main` immediately before the action is invoked.
At that mutation boundary, the workflow skips Release Please when the live SHA differs.
After Release Please runs, the workflow requires both live `main` and the pending Release PR's base SHA to still equal the validated SHA before any compatibility-context work continues.
The workflow rechecks live `main` before context mutation and immediately before pushing a context commit.
These checks do not provide an atomic compare-and-swap with GitHub branch movement, but they close stale windows before each release-controlled mutation while the upstream action targets symbolic `main`.

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

## Repository governance

The release workflow does not replace branch governance.
Before this release contract is considered ready, repository rules for `main` must mechanically require ordinary changes to arrive through a pull request and require the actual release-quality CI check before merge.
Ordinary humans and generic automation must not be able to push or write repository contents directly to `main`.
Force-push and branch deletion must remain prohibited.
The release workflow's `GITHUB_TOKEN` must not be configured as a general branch-protection bypass.

The rule must be verified behaviorally rather than inferred from a `protected: true` flag:

```text
direct normal write to main -> rejected
PR with missing required CI -> cannot merge
PR with required CI passing -> merge allowed according to policy
force push -> rejected
```

Repository rules are GitHub repository state rather than version-controlled workflow state.
Until those rules are configured and the behavior above is verified, issue `atqamz/omanixy#5` remains open even if this branch's code and CI are green.

## Failure recovery

If CI fails on `main`, the Release Please workflow does not run.

If the successfully validated main revision is stale before Release Please, Release Please is skipped.

If `main` advances after Release Please runs, or the pending Release PR is no longer based on the validated SHA, pending-candidate identity verification fails before context mutation.

If `main` advances during context work, the live-main recheck fails before the context commit is pushed.

If the Release Please API fails, the workflow is red and must be rerun after the transient or repository-permission problem is corrected.

If Release PR CI is awaiting approval, the candidate is not validated yet.

If Release PR CI fails, the draft must not be merged.

If a Release PR head changes after a green run, the previous CI evidence is stale and does not authorize the new head.

If release context is stale, malformed, duplicated, or missing migration guidance, Release PR CI fails until the human-curated entry is corrected.

If tag or GitHub Release creation fails, the workflow remains red and no alternate version, tag, or release is invented manually.

The workflow has no unrestricted manual dispatch recovery path.

The next successful validated `main` CI run updates the existing pending Release PR.

## Supply-chain and publication boundary

All third-party workflow actions are pinned to immutable commit SHAs rather than mutable major tags.

The reviewed pins are:

```text
actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1
DeterminateSystems/nix-installer-action@ef8a148080ab6020fd15196c2084a2eea5ff2d25
googleapis/release-please-action@45996ed1f6d02564a971a2fa1b5860e934307cf7
```

The Release Please action pin is the `v5.0.0` release commit.
That action release updated its bundled `release-please` dependency line to `17.6.0`, and Omanixy's manifest schema is pinned to `release-please/v17.6.0` rather than mutable `main`.
The release contract test locks the exact action SHAs and schema URL so the configuration contract reviewed in CI cannot silently drift away from the workflow runtime.

The release action runs on Node 24.

Immutable action refs, required permissions, workflow identities, and the release configuration contract are checked by repository tests and actionlint.

No npm, PyPI, crates.io, Cachix, Nixpkgs, Nix registry, Homebrew, AUR, binary archive, or install-script publication exists here.
