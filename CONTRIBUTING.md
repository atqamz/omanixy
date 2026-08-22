# Contributing

Choose or work from a GitHub Issue, then read `AGENTS.md` before working.
Keep one primary issue per focused branch and pull request where practical.

Use a draft pull request during implementation and link it to the issue.
Run `just fmt` and `just check` before requesting review.
Keep the compatibility ledger truthful and current when the issue changes
compatibility state.

Add matrix entries only after the supported upstream contract has been
audited.
Commit, push, and pull request actions require explicit authorization.

## Source Comment Policy

Maintained source, tests, build tooling, and repository automation contain
no human-authored narrative comments or documentation strings.
Comments are allowed only when their exact syntax is consumed by a
tool/interpreter and removing them would change machine behavior.
Durable rationale belongs in documentation or ADRs, not inline comments.

Comment-like characters inside ordinary string/data literals are not
source comments.
Executable code embedded inside Nix strings is scanned the same as any
other source file.

Run `nix build .#checks.<system>.source-comment-policy` before requesting
review on any change touching source files.
