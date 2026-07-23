# ADR 0001: Agent Workflow

## Decision

Use `AGENTS.md` as the canonical collaboration contract.

Task files and the porting matrix provide repository-backed work state.
Deterministic commands handle formatting and verification; agents decide
completion and perform authorized commits.

## Rationale

This keeps workflow portable across terminal-capable agents without copying
project rules into tool-specific configuration files.
