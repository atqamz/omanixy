# ADR 0008: Release publication uses manifest mode

## Status

Accepted.

## Context

Earlier release documentation deliberately avoided Release Please manifest mode during publication because manifest mode reads `release-please-config.json` and `.release-please-manifest.json` from the live target branch. The intent was to reduce live-configuration exposure after a release commit had already been validated.

That design was not viable with the pinned `googleapis/release-please-action`. Omanixy configures the root package as `package-name: omanixy`, while the action exposes no separate `component` or `package-name` input for publication. Without `config-file`, publication cannot identify the same configured component as the Release PR. Manifest mode is therefore required for a component-configured release.

The live-configuration concern is also not a new trust boundary created by manifest mode. The release workflow is triggered by `workflow_run`, so GitHub executes the workflow definition from the default branch. Inline action inputs in the old design were already live-`main` configuration. Manifest mode moves component/versioning configuration into the repository configuration and manifest files read from that same target branch; it does not turn the pending Release PR into executable trust.

## Decision

Publication uses the repository manifest configuration:

```text
config-file: release-please-config.json
manifest-file: .release-please-manifest.json
target-branch: main
skip-github-pull-request: true
```

Release identity remains pinned to the validated release commit by workflow guards outside Release Please. `Verify published release identity` derives the expected version, tag, target SHA, and release notes from the trusted release commit and rejects any published artifact whose tag, target, name, or body differs. A live configuration change that causes Release Please to publish a different release identity therefore fails closed instead of becoming accepted release state.

The maintenance invocation uses the same configuration and manifest but keeps `skip-github-release: true`; publication and maintenance differ only in which side effect is disabled.

## Consequences

- The previous non-manifest publication design is retired rather than treated as an intentional security property.
- Component identity has one configuration source for maintenance and publication.
- Live `main` remains part of workflow configuration, as it already was for `workflow_run` execution.
- The validated commit, not mutable manifest configuration alone, remains the authority for the accepted release artifact.
