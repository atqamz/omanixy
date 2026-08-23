# Releases

## Scope

Omanixy releases describe one reviewed Omanixy public API and support contract.

The Omanixy version is independent from Omarchy, Quattro, Quickshell, nixpkgs, and CI-tool versions.
Each release records the tested upstream pair and reviewed compatibility posture.
Release Please owns the Release PR, version calculation, changelog/version updates, SemVer tag, and GitHub Release.
No package registry, binary archive, install script, or release-asset publication is part of this contract.

Consumers can use a release directly with `github:atqamz/omanixy/vX.Y.Z`.

## SemVer policy

Omanixy uses SemVer with a pre-1.0 development line.

While the current major version is zero:

- `fix:` and `perf:` are patch-level;
- `feat:` is minor-level;
- a breaking change is next-minor because `bump-minor-pre-major` is enabled;
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
The pinned Release Please runtime uses `initial-version: 0.1.0` for the untagged first release.
This is a bootstrap guard, not a public `v0.1.0` release and not a permanent `release-as` override.

`ce7d3d8b53bec61585ca9efa377fdb3ae6763499` is the bootstrap boundary.
The next commit, `c756f85dc2ad546fa2cfbad1fdf3b51913bc6723`, is the first pinned Quattro runtime implementation included in release history.
The first generated candidate is expected to be `v0.1.0`.
The first Release PR remains draft until `atqamz/omanixy#6` proves standalone public usability and release readiness is explicitly approved.

## Conventional Commits

Normal pull requests should be squash-merged.
The final squash title is the semantic mainline commit consumed by Release Please.

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

CI permits release-owned files to change in two cases only:

1. the one-time bootstrap where all three files are absent from the base and all three are introduced together;
2. a same-repository pending Release PR authored by `github-actions[bot]`, carrying `autorelease: pending`, whose complete PR diff is exactly those three paths.

A label alone is not authorization.
A bot-authored PR that changes any fourth path is rejected.
Human migration edits remain possible because they modify `CHANGELOG.md` inside the already-authorized Release PR.

No runtime QML, Nix module option, flake metadata, README version, or package metadata mirrors the release version.

## Main CI provenance

CI runs for pull requests targeting `main` and pushes to `main`.
It uses read-only repository permissions plus pull-request read access needed to prove mainline provenance.

A push CI run succeeds only when its exact SHA is the `merge_commit_sha` of exactly one merged pull request targeting `main`.
This prevents an ordinary direct push from becoming a successful release-triggering CI run even while repository branch rules are still being finalized.
It is defense in depth, not a substitute for branch protection, because a rejected direct push has already changed the branch.

CI runs formatting, `just check`, all-system flake evaluation, source-comment policy, release contract checks, release-context selftests, actionlint, and the release-owned-file checks.
Nix helper packages referenced as `nixpkgs#...` use `--inputs-from .`, so they resolve through the repository's locked `nixpkgs` input instead of the runner's mutable registry state.

## Privileged release trust boundary

The release workflow has write permission and therefore never executes executable code from a pending Release PR.

The workflow first checks out the successful push SHA into `trusted-main` with checkout credentials disabled.
It proves that SHA is the exact merged-PR commit and still equals live `main`.
Only files from this validated checkout may provide executable release logic or the Nix input graph.

A pending Release PR is treated as untrusted data even though Release Please created it.
The workflow:

1. finds at most one same-repository, `github-actions[bot]`-authored, `autorelease: pending` PR;
2. re-fetches that PR through the API and verifies its base SHA, repository, author, label, branch, and exact head SHA;
3. checks out the verified head SHA, not the mutable branch name, into a separate `release-pr` directory with credentials disabled;
4. requires the complete candidate diff against the validated main SHA to be exactly the three release-owned files;
5. installs the pinned Nix runtime without passing the repository token to the Nix action;
6. runs `trusted-main/scripts/release-context` while the working directory is `release-pr`;
7. allows that trusted script to change only `CHANGELOG.md`;
8. rechecks live `main` and the remote Release PR branch SHA before committing;
9. authenticates only immediately before a non-force push.

If the Release PR branch moves between verification and push, the explicit remote-head check or the non-fast-forward push rejects the mutation.

## Separate publish and maintenance paths

Release Please is invoked in two distinct modes.

The publish invocation uses `skip-github-pull-request: true` and is eligible only when the validated current main commit is itself proven to be a merged Release PR:

- exact `merge_commit_sha` provenance;
- author `github-actions[bot]`;
- `autorelease: pending` or already-tagged release provenance;
- commit changes exactly the three release-owned files.

Before publishing, the workflow derives the expected tag from validated `version.txt` and checks whether an exact GitHub Release already exists.
A newly published release must report the validated main SHA and expected `vX.Y.Z` tag.
An already-existing release is accepted only when its `target_commitish` is the validated SHA; an exact partial-success state may have its pending/tagged labels reconciled without recreating the release.

The maintenance invocation uses `skip-github-release: true`.
It may create or update the pending Release PR after any validated current-main merge, but it cannot create a tag or GitHub Release.
This separation prevents an ordinary main merge from entering the publication path merely because Release Please also needs to maintain a candidate PR.

## Compatibility context

`scripts/release-context` reads `upstream/omarchy.yaml` and `upstream/porting-matrix.yaml` from the candidate data tree.
Because the candidate file boundary permits only the three release-owned paths, those upstream inputs are necessarily identical to validated main.

The tool requires the validated Omarchy Quattro and Quickshell pair, renders their exact revisions, summarizes compatibility classifications and support states, and links the full ledger.
It is idempotent and owns exactly one `Upstream` and one `Compatibility` section in the candidate release entry.
The final changelog therefore contains reviewed compatibility context before the Release PR is merged.

## Workflow credentials

Release automation is repository-secretless.
Release Please uses GitHub's ephemeral repository-scoped `GITHUB_TOKEN` with explicit `contents: write`, `pull-requests: write`, and `issues: write` permissions.
No PAT, GitHub App credential, or custom release secret is required.

Checkout credentials are disabled for both trusted-main and Release PR checkouts.
The pinned Determinate Nix action receives an explicit empty `github-token`, so the write-capable repository token is not delegated to the Nix installer action.
The token is exposed to controlled `gh` commands only where GitHub API mutation or authentication is required.

GitHub suppresses most recursive workflow events created by `GITHUB_TOKEN`, but pull-request `opened`, `synchronize`, and `reopened` events created by workflow automation produce approval-required workflow runs.
A maintainer approves those runs before Release PR CI executes.
Only CI for the current Release PR head counts; any generated update, compatibility-context commit, or human migration edit requires fresh validation.

The repository must allow GitHub Actions to create pull requests with `GITHUB_TOKEN` in its Actions workflow-permission setting.

## Repository governance

The workflow does not replace branch governance.
Before issue `atqamz/omanixy#5` is complete, repository rules for `main` must mechanically require ordinary changes to arrive through a pull request and require the actual release-quality CI check before merge.
Ordinary humans and generic automation must not be able to write directly to `main`.
Force-push and branch deletion must remain prohibited.
The release workflow token must not be a general branch-protection bypass.

The rule must be verified behaviorally:

```text
direct normal write to main -> rejected
PR with missing required CI -> cannot merge
PR with required CI passing -> merge allowed according to policy
force push -> rejected
branch deletion -> rejected
```

Repository rules are GitHub repository state rather than version-controlled workflow state.
Until those rules are configured and the behavior above is verified, #5 remains open even if this branch's code and CI are green.

## Failure recovery

If main CI fails, the release workflow does not run.
If the validated main revision is stale, privileged release mutations are skipped or rejected.
If the pending Release PR identity, exact head SHA, or three-file boundary changes, context mutation stops.
If live main or the candidate branch moves during context work, the push is rejected.
If a GitHub Release already exists for a candidate, it is accepted only when its exact target SHA matches the validated main commit.
If publication returns a different SHA or tag, the workflow fails.
If Release PR CI is pending, unapproved, stale, or failed, the candidate is not validated for merge.
The workflow has no unrestricted manual-dispatch recovery path.

## Supply-chain boundary

Third-party actions are pinned to immutable commit SHAs:

```text
actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1
DeterminateSystems/determinate-nix-action@527f17dd63d2d60d3e5552934bc84b9a33a14d11
googleapis/release-please-action@45996ed1f6d02564a971a2fa1b5860e934307cf7
```

The Determinate action commit is its `v3.22.2` release and pins a consistent Determinate Nix `v3.22.2` installation.
The Release Please action commit is its `v5.0.0` release; its bundled Release Please dependency line is `17.6.0`.
The manifest schema points to the exact signed Release Please `17.6.0` commit `712fcf01effd08d7b0e7b1fd3861f2cb388bc8d1` rather than a mutable branch or tag.
The release contract test locks all of these identities.

GitHub jobs use the fixed `ubuntu-24.04` runner line instead of `ubuntu-latest`.
The hosted runner image can still receive updates within that line, so the workflow does not claim bit-for-bit host hermeticity.
Repository Nix dependencies and helper package resolution are lockfile-bound, while external GitHub Actions and the Determinate Nix release are explicitly version-pinned as described above.

No npm, PyPI, crates.io, Cachix, Nixpkgs, Nix registry, Homebrew, AUR, binary archive, or install-script publication exists here.
