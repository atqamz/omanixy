# OMX-001 - Initialize the agent operating contract

Status: done

## Objective

Establish repository-level workflow that lets different AI agents mentor,
supervise, review, verify, and commit Omanixy work consistently.

## Motivation

Keep project knowledge and work state in version-controlled files instead of
agent-specific conversation memory.

## Dependencies

- None.

## Relevant upstream files

- None.

## Expected Omanixy files

- `AGENTS.md`
- Repository workflow, documentation, scripts, and hooks.

## Acceptance criteria

- `AGENTS.md` defines authority and safety boundaries.
- Omanixy upstream revision is recorded.
- Porting matrix schema exists.
- `just fmt` and `just check` exist.
- Git hooks are stored in the repository.
- Tool-specific instructions refer to `AGENTS.md`.
- No agent-specific model or CLI is required by the workflow.

## Verification

- `just fmt`
- `just check`

## Status

Bootstrap files are present and verified.
