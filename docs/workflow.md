# Workflow

Use lifecycle `SELECT -> BRIEF -> WORK -> CHECKPOINT -> VERIFY -> COMMIT -> CLOSE`.

The human implements meaningful work.

The peer reviews repository state, challenges assumptions, runs verification,
and performs approved repetitive operations.

`finish task <id>` may create one local commit.

`ship task <id>` is required before pushing or opening a pull request.
