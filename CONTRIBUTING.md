# Contributing

Choose or work from a GitHub Issue, then read `AGENTS.md` before working.
Keep one primary issue per focused branch and pull request where practical.

Use a draft pull request during implementation and link it to the issue.
Run `just fmt` and `just check` before requesting review.
Keep the compatibility ledger truthful and current when the issue changes
compatibility state.

Normal pull requests should be squash-merged.

The final squash title is the semantic commit consumed by Release Please.

Use titles such as `fix(audio): preserve selected default sink`,
`feat(network): add NetworkManager Wi-Fi controls`,
`feat(config)!: redesign shell plugin configuration`, and
`chore(ci): refresh action pin`.

Do not use fixup, WIP, or review-remediation subjects as the final mainline
semantic unit when the squash title can describe the actual change.

Release-owned files are `version.txt`, `.release-please-manifest.json`, and
Release Please entries in `CHANGELOG.md`.

Do not manually bump those files in normal feature or fix pull requests.

Breaking public changes require a `BREAKING CHANGE:` explanation and a usable
`### Migration` section in the draft Release PR.

Upstream pin changes follow Omanixy impact rather than upstream version
numbers.

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
