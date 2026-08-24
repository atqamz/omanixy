# Releases

## Scope

Omanixy releases describe one reviewed Omanixy public API and support contract.

The Omanixy version is independent from Omarchy, Quattro, Quickshell, nixpkgs, and CI-tool versions.
Each release records the tested upstream pair and reviewed compatibility posture.
Release Please owns the Release PR, version calculation, generated changelog/version state, SemVer tag, and GitHub Release.
No package registry, binary archive, install script, or release-asset publication is part of this contract.

Consumers can use a release directly with `github:atqamz/omanixy/vX.Y.Z`.

## SemVer policy

Omanixy uses SemVer with a pre-1.0 development line.

While the current major version is zero:

- `fix:` and `perf:` are patch-level;
- `feat:` is minor-level;
- breaking changes are next-minor because `bump-minor-pre-major` is enabled;
- `bump-patch-for-minor-pre-major` is disabled;
- `revert:` and configured visible `refactor:` changes are patch-level unless they carry a stronger semantic signal;
- `docs`, `test`, `build`, `ci`, and `chore` are hidden and do not independently justify a release.

No ordinary Conventional Commit can produce `1.0.0` while the current version is `0.x.y`.
`v1.0.0` requires an explicit project stability decision and a `Release-As: 1.0.0` commit footer or the current equivalent Release Please mechanism.
Permanent `release-as` configuration is prohibited.

Upstream version numbers never mechanically determine Omanixy SemVer.
A compatible pin correction can be `fix(upstream): update the tested Quattro revision`; a new public capability can be `feat(upstream): support the new panel`; an incompatible public configuration change uses a breaking Conventional Commit and migration guidance.

## Bootstrap and first release

Omanixy has no public `v0.0.0` release.
The manifest and `version.txt` value `0.0.0` are the pre-first-release baseline.
When no published release exists, the pinned Release Please strategy falls back to `initial-version: 0.1.0`.
This is a bootstrap guard, not a public `v0.1.0` release and not a permanent `release-as` override.

`ce7d3d8b53bec61585ca9efa377fdb3ae6763499` is the bootstrap history boundary.
The next commit, `c756f85dc2ad546fa2cfbad1fdf3b51913bc6723`, is the first pinned Quattro runtime implementation included in release history.
The first generated candidate is expected to be `0.1.0` with tag `v0.1.0`.
The first Release PR remains draft until `atqamz/omanixy#6` proves standalone public usability and release readiness is explicitly approved.

## Conventional Commits and merge shape

Normal pull requests should be squash-merged so the final title is the semantic mainline commit consumed by Release Please.
The repository currently enables squash merge and disables merge-commit and rebase merge methods.

Examples:

```text
fix(audio): preserve selected default sink
feat(network): add NetworkManager Wi-Fi controls
feat(config)!: redesign shell plugin configuration
chore(ci): refresh action pin
```

Fixup, WIP, and review-remediation subjects should not become the final mainline semantic unit.
Any `!` marker or `BREAKING CHANGE:` footer describes a breaking public contract regardless of commit type.

## Migration notes

An intentional breaking public API change requires usable `### Migration` guidance in the candidate release entry.
The release-context checker rejects an absent, empty, or placeholder migration section for a candidate containing breaking notes.
It does not infer migration instructions from source code.
Non-breaking candidates may omit the section or use an explicit `None.` statement.

## Release-owned files

The machine-maintained release files are exactly:

```text
.release-please-manifest.json
CHANGELOG.md
version.txt
```

Release Please owns version calculation and generated release-note state.
`scripts/release-context` owns only the deterministic `Upstream` and `Compatibility` sections.
Humans own reviewed `Migration` guidance inside a pending Release PR.

CI permits release-owned files to change only for:

1. the one-time bootstrap where all three files are absent from the base and all three are introduced together; or
2. a same-repository pending Release PR authored by `github-actions[bot]`, carrying `autorelease: pending`, with a complete PR diff of exactly those three paths and the expected `chore(main): release X.Y.Z` title.

Each release-owned path must be a normal `100644` Git blob.
A symlink, submodule, executable-mode replacement, label-only impersonation, bot-authored fourth file, or mismatched title fails closed.
Human migration edits remain possible because they modify `CHANGELOG.md` inside the already-authorized Release PR.

No runtime QML, Nix module option, flake metadata, README version, or package metadata mirrors the release version.

## Main CI provenance

CI runs for pull requests targeting `main` and pushes to `main`.
It uses read-only repository contents plus pull-request read access.

A push CI run succeeds only when its exact SHA is the `merge_commit_sha` of exactly one merged pull request targeting `main`.
This prevents an ordinary direct push from becoming a successful release-triggering CI run even while repository branch rules are still being finalized.
It is defense in depth, not branch protection: a rejected direct-push CI run happens after an incorrectly permitted branch write.

CI runs formatting, `just check`, all-system flake evaluation, source-comment policy, release contract checks, release-context selftests, actionlint, and release-owned-file validation.
Nix helper packages referenced as `nixpkgs#...` use `--inputs-from .`, so they resolve through the repository's locked `nixpkgs` input rather than the runner registry.

## Privileged release trust boundary

The release workflow has write permission and therefore never executes executable code from a pending Release PR.

The successful push SHA is checked out as `trusted-main` with checkout credentials disabled.
The workflow proves that SHA belongs to exactly one merged PR and checks live-main identity before entering the current-main mutation path.
Only this validated checkout may provide executable release logic, Release Please configuration, or the Nix input graph.

A pending Release PR is data, not executable trust.
The workflow:

1. finds at most one same-repository, `github-actions[bot]`-authored, `autorelease: pending` PR;
2. re-fetches and verifies its base SHA, repository, author, label, branch, and exact head SHA;
3. checks out the verified head SHA, not a mutable branch name, into `release-pr` with credentials disabled;
4. requires the complete candidate diff to be exactly the three release-owned normal Git blobs;
5. requires the title to match `version.txt`;
6. installs pinned Determinate Nix without giving that action the repository token;
7. executes only `trusted-main/scripts/release-context` while `release-pr` is the data working tree;
8. permits that tool to change only `CHANGELOG.md`;
9. rechecks live `main` and the remote candidate branch SHA before commit/push;
10. performs a non-force push and then synchronizes the candidate PR body from the exact candidate changelog entry.

If the candidate branch moves between verification and push, the explicit remote-head comparison or non-fast-forward push rejects the mutation.

## GitHub Release body contract

The pinned Release Please runtime does not reread final `CHANGELOG.md` when publishing a merged Release PR.
For a single component it derives the release version from the merged Release PR title and the release notes from the merged Release PR body.

Omanixy therefore treats the body as a derived publication representation rather than a second independently curated source.
`scripts/release-context --release-notes` renders the exact top candidate changelog entry, and `--render-pr-body` wraps that same entry in the Release Please body format.

Immediately before publication, the workflow:

1. verifies the merged Release PR title against trusted `version.txt`;
2. renders the canonical body from the trusted merged `CHANGELOG.md`;
3. updates the merged Release PR body to that exact value;
4. reads it back and requires byte-equivalent shell-string content before invoking Release Please.

This makes reviewed `Upstream`, `Compatibility`, and `Migration` content from `CHANGELOG.md` the canonical release-note data while still satisfying Release Please's actual merged-PR-body publication behavior.

## Separate publication and maintenance paths

Release Please is invoked in two distinct modes.

The publication invocation uses `skip-github-pull-request: true` and is eligible only when the validated main commit is itself a merged Release PR with:

- exact merged-PR SHA provenance;
- `github-actions[bot]` authorship;
- pending or already-tagged release label provenance;
- exactly the three normal release-owned blobs;
- a title matching validated `version.txt`.

Before publication, the workflow derives `vX.Y.Z` from trusted `version.txt`.
If that tag already exists, its ref must be a direct commit ref at the validated release SHA.
If a GitHub Release already exists, it is accepted only when all canonical properties match: target SHA, tag target SHA, release name, exact release-note body, non-draft state, and non-prerelease state.
A wrong pre-existing tag or release fails closed.

For a fresh publication, Release Please action outputs must report the expected release-created state, exact SHA, tag, and body.
The workflow then re-fetches GitHub state and re-verifies the same artifact properties independently.
A partial success where the exact release exists but labels were not reconciled is recoverable without inventing a new version or release.

The maintenance invocation uses `skip-github-release: true` and cannot create a tag or GitHub Release.
Before maintenance begins, live `main` is checked again against the validated SHA.
If `main` advanced while a valid release was being published, the published artifact remains valid and stale maintenance is skipped; the later main CI run owns the next maintenance cycle.

## Compatibility context

`scripts/release-context --write` and `--check` read `upstream/omarchy.yaml` and `upstream/porting-matrix.yaml` from the candidate working tree.
Because the Release PR may differ from validated main only in the three release-owned paths, those upstream inputs are necessarily the validated-main versions.

The tool requires the validated Omarchy Quattro and Quickshell pair, renders exact revisions, summarizes compatibility classifications and support states, and links the full ledger.
It is idempotent and owns exactly one `Upstream` and one `Compatibility` section in the top candidate entry.

The publication-only `--release-notes` and `--render-pr-body` modes require only the canonical release files; they do not load upstream YAML or PyYAML.
This keeps exact-release recovery independent from reinstalling compatibility-analysis dependencies after the release commit is already on `main`.

## Workflow credentials

Release automation is repository-secretless.
Release Please uses GitHub's ephemeral repository-scoped `GITHUB_TOKEN` with explicit `contents: write`, `pull-requests: write`, and `issues: write` permissions.
No PAT, GitHub App credential, or custom release secret is required.

Checkout credentials are disabled for both trusted-main and Release PR checkouts.
The pinned Determinate Nix action receives an explicit empty `github-token`, so the write-capable repository token is not delegated to the installer action.
The token is exposed to controlled GitHub CLI calls only where repository reads, body/label mutation, or the final candidate Git push requires it.

GitHub suppresses most recursive workflow events created by `GITHUB_TOKEN`, while pull-request `opened`, `synchronize`, and `reopened` events created by workflow automation produce approval-required workflow runs.
A maintainer approves those runs before Release PR CI executes.
Only CI for the current Release PR head counts; generated updates, compatibility-context commits, and human migration edits invalidate older validation evidence.

The repository must allow GitHub Actions to create pull requests with `GITHUB_TOKEN` in its Actions workflow-permission setting.

## Repository governance

Workflow hardening is not branch governance.
Issue `atqamz/omanixy#5` is not complete until repository rules for `main` mechanically require ordinary source changes through pull requests and require the actual release-quality CI check before merge.
Ordinary humans and generic automation must not be able to write directly to `main`.
Force-push and branch deletion must remain prohibited.
The release workflow token must not be a general branch-protection bypass.

Acceptance is behavioral:

```text
direct normal write to main -> rejected
PR with missing required CI -> cannot merge
PR with required CI passing -> merge allowed according to policy
force push -> rejected
branch deletion -> rejected
```

A `protected: true` API field alone is not evidence.
Repository rules are GitHub repository state rather than version-controlled workflow state, so #5 remains open until this behavior is configured and verified even if PR #22 itself is green.

## Failure recovery

If main CI fails, no privileged release run is eligible.
If the validated main revision is stale before maintenance, maintenance is skipped or rejected.
If pending Release PR identity, title, exact head SHA, normal-file shape, or three-file boundary changes, candidate mutation stops.
If live main or the candidate branch moves during context work, the candidate push is rejected.
If an expected tag already exists at another SHA or as an unexpected ref shape, publication fails.
If a GitHub Release exists but any canonical artifact property differs, publication recovery fails rather than accepting drift.
If fresh publication returns a different SHA, tag, or body, the workflow fails.
If publication succeeds while main advances, exact artifact verification still completes and stale maintenance is skipped.
If Release PR CI is pending, unapproved, stale, or failed, the candidate is not validated for merge.
The workflow has no unrestricted manual-dispatch recovery path.

## Supply-chain boundary

Third-party workflow actions use immutable commit SHAs:

```text
actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1
DeterminateSystems/determinate-nix-action@527f17dd63d2d60d3e5552934bc84b9a33a14d11
googleapis/release-please-action@45996ed1f6d02564a971a2fa1b5860e934307cf7
```

The Determinate action commit is its `v3.22.2` release and pins a consistent Determinate Nix `v3.22.2` installation.
The Release Please action commit is its `v5.0.0` release; that release uses the Release Please `17.6.x` dependency line reviewed here.
The manifest schema points to the exact signed Release Please `17.6.0` commit `712fcf01effd08d7b0e7b1fd3861f2cb388bc8d1` rather than a mutable branch or tag.
Repository contract tests lock these identities and publication boundaries.

GitHub jobs use `ubuntu-24.04` instead of `ubuntu-latest`.
The hosted runner image can still change within that line, so the workflow does not claim bit-for-bit host hermeticity.
Repository Nix dependencies and helper-package resolution are lockfile-bound; external actions and Determinate Nix are explicitly pinned as described above.

No npm, PyPI, crates.io, Cachix, Nixpkgs, Nix registry, Homebrew, AUR, binary archive, or install-script publication exists here.
