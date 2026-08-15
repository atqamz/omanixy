# ADR 0003: GitHub Issue Workflow

## Status

Accepted.

## Context

The bootstrap workflow created repository-local task files so agents could
share work state without depending on conversation memory.

The project now has detailed GitHub Issues that already contain objectives,
scope, dependencies, acceptance criteria, and discussion.
Maintaining both systems creates two work-state authorities that can drift.

The repository still needs durable product knowledge, architectural decisions,
compatibility state, and a strong operating contract.
Those are different from the lifecycle state of an implementation task.

## Decision

Use GitHub Issues and pull requests as the sole work-tracking system:

```text
GitHub Issues
    canonical work definition

GitHub PRs
    implementation and review state

AGENTS.md
    canonical repository and agent operating contract

docs and ADRs
    durable product and architectural knowledge

upstream/porting-matrix.yaml
    durable compatibility state

Git history
    historical implementation record
```

Remove the repository-local task ledger and its task-context tooling.
Contributors and agents read the actual GitHub Issue when executing issue
work, use a branch and draft pull request for implementation, and link the
pull request to the issue.

Do not replace the task ledger with an issue cache, synchronization script,
YAML work registry, branch registry, or custom task command.
The compatibility matrix remains a compatibility ledger, not a work tracker.

## Positive consequences

- There is one source of truth for work.
- Issue and task-file synchronization is eliminated.
- Repository ceremony is reduced.
- Native issue and pull request linkage carries identity and state.
- Discussion and review history stay with the work.
- Stale local status is removed.
- Automation can use GitHub's native lifecycle.

## Negative consequences

- Active issue bodies are not fully available from a disconnected checkout.
- Work definition depends on GitHub availability.

This tradeoff is acceptable because durable architectural and product decisions
remain in the repository.
Closing an issue does not erase the ADRs, architecture docs, compatibility
metadata, or Git history that preserve what was decided and implemented.

## Supersedes

This ADR supersedes only the local task-file work-state portion of
[ADR 0001: Agent Workflow](0001-agent-workflow.md).
It does not supersede the use of `AGENTS.md` as the operating contract or the
repository's deterministic formatting and verification commands.
