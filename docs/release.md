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

Release Please owns `version.txt`, `.release-please-manifest.json`, and release entries in `CHANGELOG.md` after bootstrap.

Normal feature, fix, and documentation pull requests must not casually edit those files.

The only intentional human-curated release-file change is migration guidance inside the draft Release PR.

No runtime QML, Nix module option, flake metadata, README version, or package metadata mirrors the release version.

There is no runtime version command or version label in this release system.

## Compatibility context

The `scripts/release-context` tool reads `upstream/omarchy.yaml` and `upstream/porting-matrix.yaml` on every invocation.

It requires the validated Omarchy Quattro and Quickshell pair, renders their exact revisions, summarizes compatibility classifications and support states, and links to the full ledger.

The normal flow is:

```text
successful main CI
        |
        v
Release Please creates or updates a draft Release PR
        |
        v
release-context --write and --check update the candidate changelog
        |
        v
ordinary CI validates the Release PR
        |
        v
human reviews context and migration guidance
        |
        v
human marks the draft ready and merges when release readiness is approved
```

The context writer is idempotent and owns exactly one `Upstream` and one `Compatibility` section in the candidate entry.

The final changelog entry already contains the context before the Release PR is merged, so the GitHub Release body inherits the reviewed information.

## Workflow and credentials

CI runs on pull requests targeting `main` and pushes to `main` with `contents: read`.

CI runs formatting, `just check`, all-system flake evaluation, source-comment policy, release contract checks, release-context selftests, actionlint, and the release-owned-file context check when those files change.

Release Please runs only from a successful `CI` `workflow_run` for a push to the current `main` SHA.

The release workflow has a single global `release-main` concurrency group with cancellation disabled.

The workflow's built-in `GITHUB_TOKEN` is read-only.

Release writes use the repository secret `RELEASE_PLEASE_TOKEN` and never fall back to `GITHUB_TOKEN` or a developer's local CLI token.

The required credential is a fine-grained personal access token limited to `atqamz/omanixy`.

Its required repository permissions are `Contents: Read and write`, `Pull requests: Read and write`, and `Issues: Read and write`.

Metadata read is implicit.

No Actions, Administration, Workflows, Secrets, Packages, Codespaces, organization, or classic broad `repo` permission is required by the current workflow.

The repository secret must be provisioned before merging this infrastructure change.

The release workflow fails closed when the secret is missing.

The external token is required because GitHub's built-in token suppresses most follow-up workflow events and can leave automated pull-request workflows approval-gated.

Using the external token lets a Release PR trigger the same ordinary CI as a human PR.

No actor condition skips validation for generated Release PRs.

## Failure recovery

If CI fails on `main`, the Release Please workflow does not run.

If the Release Please API fails, the workflow is red and must be rerun after the transient or permission problem is corrected.

If Release PR CI fails, the draft must not be merged.

If release context is stale, malformed, duplicated, or missing migration guidance, Release PR CI fails until the human-curated entry is corrected.

If tag or GitHub Release creation fails, the workflow remains red and no alternate version, tag, or release is invented manually.

The workflow has no unrestricted manual dispatch recovery path.

The next successful validated `main` CI run updates the existing pending Release PR.

## Supply-chain and publication boundary

The introduced actions are `actions/checkout@v7`, `DeterminateSystems/nix-installer-action@v22`, and `googleapis/release-please-action@v5`.

The release action currently runs on Node 24 and uses the current manifest configuration contract.

Action majors and required permissions are checked by repository actionlint and the release contract test.

Release Please alone owns the Release PR, version files, changelog, tag, and GitHub Release.

No npm, PyPI, crates.io, Cachix, Nixpkgs, Nix registry, Homebrew, AUR, binary archive, or install-script publication exists here.
