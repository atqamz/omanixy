# ADR 0006: Zero Narrative Source Prose

## Status

Accepted.

## Context

The repository accumulated substantial narrative comments and docstrings
across Nix, Python, shell, JS/QML, and YAML during the Quattro port and the
issue #4 security hardening.
Much of that prose duplicates identifiers, test names, ADRs, and the
compatibility ledger, and it drifts out of sync with the code it describes
because nothing enforces it.
`just fmt` and `just check` audit formatting and behavior, not comment
content, so the accumulation was never caught by existing tooling.
No prior policy states what comment surface is acceptable, so a future
change could keep growing narrative prose in any file without review having
a rule to point at.

## Decision

Maintained source, tests, build tooling, and repository automation contain
no human-authored narrative comments or documentation strings.
A comment is retained only when its exact syntax is consumed by a tool or
interpreter and removing it would change machine behavior, such as a
`# shellcheck disable=SCxxxx` directive stripped of its explanatory trailer,
never for explanation of intent.
Durable rationale moves to `docs/`, an ADR, the compatibility ledger, or a
test name, not an inline comment.
The directive allowlist starts empty and only admits an exact grammar proven
both present in the tree and consumed by a tool this project's validation
actually runs; there is no generic suppression syntax.
Classification is structural and contextual, never by directory glob, so
there is no `test/**` or `fixtures/**` exemption.
Comment-like characters inside an ordinary string or data literal are not
source comments and are not touched.
An unsupported or unrecognized maintained-source language fails the checker
closed with an actionable error rather than being silently skipped.

## Ownership

`scripts/check-source-comments` is the single source of truth for the
policy: a Python `tokenize`/`ast` scanner plus custom lexers for shell, Nix,
JS/QML, YAML, and TOML, wired into `nix flake check` as
`checks.<system>.source-comment-policy`.
Nix strings that embed executable code are scanned recursively as their own
source file, closing the embedded-code escape hatch that a string-only scan
would leave open.
A one-time tool, `scripts/check-comment-sweep-equivalence`, and a refresh of
the compatibility ledger's `adapterHash` anchor the initial repository sweep
as behavior-preserving; neither becomes a second permanent checker.
The checker, its selftest, and the equivalence tool follow the same
contribution and review path as any other repository tooling; this decision
creates no dedicated maintainer role.

## Enforcement

`nix build .#checks.<system>.source-comment-policy` is the canonical local
invocation, and `nix flake check` runs it as part of `just check`.
The checker's own source and its selftest are held to the same zero-comment
bar they enforce, self-documenting through function and variable names only.
The repository has no separate CI workflow; `nix flake check` is the
enforcement surface.
A change that reintroduces narrative prose fails the check and blocks
review like any other `just check` failure.

## Tradeoff

Comment volume can no longer silently drift from the code it once
described, and durable rationale is forced into versioned documentation
instead of an inline aside.
The checker adds no new Nix closure dependency: it is Python stdlib
(`tokenize`, `ast`) plus small, adversarially tested custom lexers, per the
project's existing preference for a narrow lexer over a new parser
dependency.
A small, fixed set of machine-consumed directives, such as the shellcheck
disables, must be preserved bare, which can make an isolated line harder to
read without its former trailer.
A contributor who would have narrated an unusual line inline must instead
extend a test name, an ADR, or `docs/`, which is a heavier motion for a
one-line note.
The equivalence tool exists only to prove the initial sweep changed no
executable semantics; it is not retained as a second permanent enforcement
path.
