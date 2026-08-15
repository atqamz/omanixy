# ADR 0001: Agent Workflow

## Status

Superseded in part by
[ADR 0003: GitHub Issue Workflow](0003-github-issue-workflow.md).
The original decision about `AGENTS.md` and deterministic verification remains
in force.

## Decision

Use `AGENTS.md` as the canonical collaboration contract.

The original bootstrap workflow also used local task files and the porting
matrix as repository-backed work state.
The local task-file portion is superseded by ADR 0003.
Deterministic commands handle formatting and verification; agents decide
completion and perform authorized commits.

## Rationale

This keeps workflow portable across terminal-capable agents without copying
project rules into tool-specific configuration files.
