#!/usr/bin/env bash
set -euo pipefail

ci=.github/workflows/ci.yaml
release=.github/workflows/release-please.yaml

grep -Fq 'HEAD_REPOSITORY: ${{ github.event.pull_request.head.repo.full_name }}' "$ci"
grep -Fq "PENDING_RELEASE: \${{ contains(github.event.pull_request.labels.*.name, 'autorelease: pending') }}" "$ci"
grep -Fq 'git cat-file -e "$BASE_SHA:$path"' "$ci"
grep -Fq 'test "$HEAD_REPOSITORY" = "$GITHUB_REPOSITORY"' "$ci"
grep -Fq 'test "$PENDING_RELEASE" = true' "$ci"
grep -Fq 'Verify pending Release PR identity' "$release"
grep -Fq 'gh api "repos/$GITHUB_REPOSITORY/pulls/$RELEASE_PR_NUMBER" --jq '\''.base.sha'\''' "$release"
test "$(grep -Fc 'test "$current_sha" = "$EXPECTED_SHA"' "$release")" -ge 3
