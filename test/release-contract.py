#!/usr/bin/env python3
import json
import re
import shlex
import sys
from pathlib import Path

import yaml


BOOTSTRAP_SHA = "ce7d3d8b53bec61585ca9efa377fdb3ae6763499"
RELEASE_PLEASE_SCHEMA = "https://raw.githubusercontent.com/googleapis/release-please/712fcf01effd08d7b0e7b1fd3861f2cb388bc8d1/schemas/config.json"
CHECKOUT_ACTION = "actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1"
NIX_ACTION = "DeterminateSystems/determinate-nix-action@527f17dd63d2d60d3e5552934bc84b9a33a14d11"
RELEASE_PLEASE_ACTION = "googleapis/release-please-action@45996ed1f6d02564a971a2fa1b5860e934307cf7"
RELEASE_FILES = (".release-please-manifest.json", "CHANGELOG.md", "version.txt")
RELEASE_VERSION = re.compile(r"^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$")
IMMUTABLE_ACTION = re.compile(r"^[^@]+@[0-9a-f]{40}$")
RELEASE_AUTHOR = "github-actions:bot"
RELEASE_AUTHOR_LOGINS = ("github-actions[bot]", "app/github-actions")


def load_json(path):
    return json.loads(path.read_text(encoding="utf-8"))


def trigger(workflow):
    return workflow.get("on", workflow.get(True))


def steps(workflow, job):
    return workflow["jobs"][job]["steps"]


def named_steps(workflow, job):
    return {step["name"]: step for step in steps(workflow, job) if "name" in step}


def contains_all(text, snippets):
    for snippet in snippets:
        assert snippet in text, snippet


def command_argvs(step):
    result = []
    for raw in step.get("run", "").splitlines():
        raw = raw.strip()
        if not raw:
            continue
        try:
            argv = shlex.split(raw)
        except ValueError:
            continue
        if argv:
            result.append(argv)
    return result


def normalize_release_author(login):
    if login in RELEASE_AUTHOR_LOGINS:
        return RELEASE_AUTHOR
    return login


def release_author_matches(pr):
    return normalize_release_author(pr["author"]["login"]) == RELEASE_AUTHOR


def assert_release_author_identity():
    assert release_author_matches({"author": {"login": "github-actions[bot]"}})
    assert release_author_matches({"author": {"login": "app/github-actions"}})
    assert not release_author_matches({"author": {"login": "human"}})
    assert not release_author_matches({"author": {"login": "app/third-party"}})
    assert not release_author_matches({"author": {"login": "github-actions"}})


def assert_regular_files(source, ref):
    assert f'git ls-tree {ref} -- "$path"' in source
    assert 'test "$(awk \'{print $1}\' <<< "$tree_entry")" = 100644' in source
    assert 'test "$(awk \'{print $2}\' <<< "$tree_entry")" = blob' in source
    for path in RELEASE_FILES:
        assert path in source


def assert_release_config(root):
    config = load_json(root / "release-please-config.json")
    manifest = load_json(root / ".release-please-manifest.json")
    version_text = (root / "version.txt").read_text(encoding="utf-8")
    changelog = (root / "CHANGELOG.md").read_text(encoding="utf-8")
    version = version_text.strip()

    assert config["$schema"] == RELEASE_PLEASE_SCHEMA
    assert config["bootstrap-sha"] == BOOTSTRAP_SHA
    assert config["release-type"] == "simple"
    assert config["version-file"] == "version.txt"
    assert config["bump-minor-pre-major"] is True
    assert config["bump-patch-for-minor-pre-major"] is False
    assert config["initial-version"] == "0.1.0"
    assert config["include-component-in-tag"] is False
    assert config["include-v-in-tag"] is True
    assert config["draft-pull-request"] is True
    assert config["packages"] == {".": {"package-name": "omanixy"}}

    for forbidden in (
        "release-as",
        "pull-request-title-pattern",
        "pull-request-header",
        "pull-request-footer",
        "draft",
        "prerelease",
        "force-tag-creation",
    ):
        assert forbidden not in config
        assert all(forbidden not in package for package in config["packages"].values())

    expected_sections = {
        "feat": ("Features", False),
        "fix": ("Bug Fixes", False),
        "perf": ("Performance Improvements", False),
        "revert": ("Reverts", False),
        "docs": ("Documentation", True),
        "test": ("Tests", True),
        "build": ("Build System", True),
        "ci": ("Continuous Integration", True),
        "chore": ("Maintenance", True),
        "refactor": ("Refactoring", False),
    }
    actual_sections = {
        item["type"]: (item["section"], item.get("hidden", False))
        for item in config["changelog-sections"]
    }
    assert actual_sections == expected_sections
    assert version_text == version + "\n"
    assert RELEASE_VERSION.fullmatch(version)
    assert manifest == {".": version}
    assert changelog.startswith("# Changelog\n")
    if version == "0.0.0":
        assert changelog == "# Changelog\n"


def assert_release_context(root):
    source = (root / "scripts/release-context").read_text(encoding="utf-8")
    contains_all(
        source,
        (
            "RELEASE_VERSION_PATTERN",
            "version.txt is not a single X.Y.Z SemVer release line",
            'group.add_argument("--write"',
            'group.add_argument("--check"',
            'group.add_argument("--release-notes"',
            'group.add_argument("--render-pr-body"',
            'RELEASE_PR_HEADER = ":robot: I have created a release *beep* *boop*"',
            '"This PR was generated with [Release Please](https://github.com/googleapis/release-please). "',
            '"See [documentation](https://github.com/googleapis/release-please#release-please)."',
            'return f"{RELEASE_PR_HEADER}\\n---\\n\\n\\n{notes}\\n\\n---\\n{RELEASE_PR_FOOTER}\\n"',
            "candidate_entry(",
            "render_release_pr_body(",
            'f"v{version}/upstream/porting-matrix.yaml"',
        ),
    )
    assert "SEMVER_IDENTIFIER" not in source
    assert "\nimport yaml\n" not in source
    assert "import yaml" in source


def assert_ci(ci):
    ci_on = trigger(ci)
    assert ci["name"] == "CI"
    assert ci_on["pull_request"]["branches"] == ["main"]
    assert ci_on["push"]["branches"] == ["main"]
    assert ci["permissions"] == {"contents": "read", "pull-requests": "read"}
    job = ci["jobs"]["validate"]
    assert job["runs-on"] == "ubuntu-24.04"
    ordered = steps(ci, "validate")
    named = named_steps(ci, "validate")
    assert ordered[0]["uses"] == CHECKOUT_ACTION
    assert ordered[0]["with"] == {"fetch-depth": 0, "persist-credentials": False}

    provenance = named["Verify main PR provenance"]
    assert provenance["if"] == "github.event_name == 'push'"
    contains_all(provenance["run"], (".merge_commit_sha == $sha", 'test "$merged_pr_count" = "1"'))

    nix_steps = [step for step in ordered if step.get("uses") == NIX_ACTION]
    assert len(nix_steps) == 1
    assert nix_steps[0]["with"]["github-token"] == ""
    assert named["Format"]["run"].strip() == "nix fmt\ngit diff --exit-code"
    assert named["Canonical checks"]["run"].strip() == "nix shell --inputs-from . nixpkgs#just -c just check"
    assert named["All systems evaluation"]["run"].strip() == "nix flake check --show-trace --print-build-logs --all-systems --no-build"

    owned = named["Release-owned files"]
    assert owned["if"] == "github.event_name == 'pull_request'"
    source = owned["run"]
    contains_all(
        source,
        (
            'test "$HEAD_REPOSITORY" = "$GITHUB_REPOSITORY"',
            'test "$PR_AUTHOR" = "github-actions[bot]"',
            'test "$PENDING_RELEASE" = true',
            'expected_title="chore(main): release $(cat version.txt)"',
            'test "$PR_TITLE" = "$expected_title"',
            'test "$actual_release_files" = "$expected_release_files"',
            "scripts/release-context --check",
        ),
    )
    assert_regular_files(source, '"$HEAD_SHA"')


def assert_release_workflow(release, release_text):
    release_on = trigger(release)
    assert release["name"] == "Release Please"
    assert release_on["workflow_run"] == {"workflows": ["CI"], "types": ["completed"], "branches": ["main"]}
    assert release["permissions"] == {"contents": "write", "pull-requests": "write", "issues": "write"}
    assert release["concurrency"] == {"group": "release-main", "cancel-in-progress": False}
    assert "${{ secrets." not in release_text
    assert "RELEASE_PLEASE_TOKEN" not in release_text

    job = release["jobs"]["release"]
    assert job["runs-on"] == "ubuntu-24.04"
    assert job["if"] == "github.event.workflow_run.conclusion == 'success' && github.event.workflow_run.event == 'push' && github.event.workflow_run.head_branch == 'main'"
    ordered = steps(release, "release")
    named = named_steps(release, "release")
    initial_current = "steps.main-identity.outputs.current == 'true'"
    maintenance_current = "steps.maintenance-main.outputs.current == 'true'"
    candidate = maintenance_current + " && steps.release-pr.outputs.found == 'true'"

    checkouts = [step for step in ordered if step.get("uses") == CHECKOUT_ACTION]
    assert len(checkouts) == 2
    trusted_checkout, candidate_checkout = checkouts
    assert trusted_checkout["with"] == {
        "ref": "${{ github.event.workflow_run.head_sha }}",
        "fetch-depth": 0,
        "path": "trusted-main",
        "persist-credentials": False,
    }

    provenance = named["Verify merged PR provenance"]
    source = provenance["run"]
    contains_all(
        source,
        (
            ".merge_commit_sha == $sha",
            'test "$(jq length <<< "$matches")" = "1"',
            '[ "$author" = "github-actions[bot]" ]',
            'parent_count="$(git rev-list --parents -n 1 "$EXPECTED_SHA"',
            'test "$parent_count" = 1',
            'git diff --name-only "$EXPECTED_SHA^1" "$EXPECTED_SHA"',
            'test "$actual_release_files" = "$expected_release_files"',
            'expected_title="chore(main): release $(cat version.txt)"',
            'test "$title" = "$expected_title"',
        ),
    )
    assert_regular_files(source, '"$EXPECTED_SHA"')

    release_state = named["Inspect merged release state"]
    contains_all(
        release_state["run"],
        (
            "--release-notes",
            "git/ref/tags/$tag",
            "'.object.type'",
            "'.object.sha'",
            'test "$target" = "$EXPECTED_SHA"',
            'test "$tag_target" = "$EXPECTED_SHA"',
            'test "$name" = "$tag"',
            'test "$body" = "$expected_notes"',
            'test "$draft" = false',
            'test "$prerelease" = false',
        ),
    )

    exclusive = named["Verify exclusive publish candidate"]
    contains_all(
        exclusive["run"],
        (
            'test "$current_sha" = "$EXPECTED_SHA"',
            "--state merged",
            "--base main",
            '--label "autorelease: pending"',
            "--limit 200",
            'test "$(jq length <<< "$pending_prs")" = 1',
            "def normalized_author:",
            'if . == "github-actions[bot]" or . == "app/github-actions"',
            ".[0].author.login | normalized_author",
            '"github-actions:bot"',
        ),
    )

    canonical = named["Canonicalize merged Release PR body"]
    assert canonical["run"].count('test "$current_sha" = "$EXPECTED_SHA"') >= 2
    contains_all(canonical["run"], ("--render-pr-body", "--method PATCH", 'test "$actual_body" = "$expected_body"'))

    preconditions = named["Verify publish preconditions"]
    contains_all(
        preconditions["run"],
        (
            'test "$current_sha" = "$EXPECTED_SHA"',
            "'.merged_at'",
            "'.merge_commit_sha'",
            'test "$(jq -r \'.user.login\' <<< "$pr_json")" = "github-actions[bot]"',
            'test "$(jq -r \'.title\' <<< "$pr_json")" = "$expected_title"',
            'test "$(jq -r \'.body\' <<< "$pr_json")" = "$expected_body"',
            'select(. == "autorelease: pending")',
            'select(. == "autorelease: tagged")',
            "--state merged",
            'test "$(jq length <<< "$pending_prs")" = 1',
        ),
    )

    publish = named["Publish merged Release PR"]
    assert publish["uses"] == RELEASE_PLEASE_ACTION
    assert publish["with"] == {
        "release-type": "simple",
        "include-component-in-tag": False,
        "target-branch": "main",
        "skip-github-pull-request": True,
    }
    assert "config-file" not in publish["with"]
    assert "manifest-file" not in publish["with"]

    published = named["Verify published release identity"]
    contains_all(
        published["run"],
        (
            'test "$RELEASE_CREATED" = true',
            'test "$RELEASE_SHA" = "$EXPECTED_SHA"',
            'test "$RELEASE_TAG" = "$tag"',
            'test "$RELEASE_BODY" = "$expected_notes"',
            "git/ref/tags/$tag",
            "'.target_commitish'",
            "'.body'",
            "'.draft'",
            "'.prerelease'",
            'select(. == "autorelease: pending")',
            'select(. == "autorelease: tagged")',
        ),
    )

    tagged = named["Verify tagged release identity"]
    contains_all(
        tagged["run"],
        (
            "--release-notes",
            "git/ref/tags/$tag",
            'test "$(jq -r \'.target_commitish\' <<< "$release_json")" = "$EXPECTED_SHA"',
            'select(. == "autorelease: pending")',
            'select(. == "autorelease: tagged")',
        ),
    )

    maintenance = named["Recheck current main for maintenance"]
    assert maintenance["if"] == initial_current
    contains_all(maintenance["run"], ('current_sha="$(git ls-remote --refs origin refs/heads/main | cut -f1)"', 'if [ "$current_sha" = "$EXPECTED_SHA" ]'))

    maintain = named["Maintain Release PR"]
    assert maintain["uses"] == RELEASE_PLEASE_ACTION
    assert maintain["if"] == maintenance_current
    assert maintain["with"] == {
        "config-file": "release-please-config.json",
        "manifest-file": ".release-please-manifest.json",
        "target-branch": "main",
        "skip-github-release": True,
    }

    query = named["Find pending Release PR"]
    contains_all(
        query["run"],
        (
            '--label "autorelease: pending"',
            "--limit 100",
            "headRepository.nameWithOwner == $repo",
            "def normalized_author:",
            'if . == "github-actions[bot]" or . == "app/github-actions"',
            '((.author.login | normalized_author) == "github-actions:bot")',
        ),
    )

    identity = named["Verify pending Release PR identity"]
    assert identity["if"] == candidate
    contains_all(
        identity["run"],
        (
            "'.base.sha'",
            "'.head.sha'",
            "'.head.repo.full_name'",
            "'.head.ref'",
            "'.user.login'",
            'test "$base_sha" = "$EXPECTED_SHA"',
            'test "$head_repo" = "$GITHUB_REPOSITORY"',
            'test "$head_ref" = "$RELEASE_BRANCH"',
            'test "$author" = "github-actions[bot]"',
            'test "$pending" = true',
        ),
    )

    assert candidate_checkout["if"] == candidate
    assert candidate_checkout["with"] == {
        "ref": "${{ steps.candidate-identity.outputs.head_sha }}",
        "fetch-depth": 0,
        "path": "release-pr",
        "persist-credentials": False,
    }

    boundary = named["Verify Release PR file boundary"]
    contains_all(
        boundary["run"],
        (
            'git diff --name-only "$EXPECTED_SHA...HEAD"',
            'test "$actual_release_files" = "$expected_release_files"',
            'expected_title="chore(main): release $(cat version.txt)"',
            'test "$actual_title" = "$expected_title"',
        ),
    )
    assert_regular_files(boundary["run"], "HEAD")

    nix_steps = [step for step in ordered if step.get("uses") == NIX_ACTION]
    assert len(nix_steps) == 1
    assert nix_steps[0]["if"] == candidate
    assert nix_steps[0]["with"]["github-token"] == ""

    writer = named["Write release context"]
    assert writer["if"] == candidate
    writer_source = writer["run"]
    contains_all(
        writer_source,
        (
            'nix build --inputs-from "$TRUSTED_ROOT"',
            'nix shell --inputs-from "$TRUSTED_ROOT"',
            'python3 "$TRUSTED_ROOT/scripts/release-context" --write',
            'python3 "$TRUSTED_ROOT/scripts/release-context" --render-pr-body',
            'python3 "$TRUSTED_ROOT/scripts/release-context" --check',
            'test "$remote_candidate_sha" = "$candidate_sha"',
            'test "$pr_head_sha" = "$candidate_sha"',
            'git push origin "HEAD:refs/heads/$RELEASE_BRANCH"',
            "--method PATCH",
            'test "$actual_body" = "$expected_body"',
        ),
    )
    assert writer_source.count('test "$current_sha" = "$EXPECTED_SHA"') >= 2
    assert writer_source.count('test "$remote_candidate_sha" = "$candidate_sha"') >= 2
    assert writer_source.count('test "$pr_head_sha" = "$candidate_sha"') >= 2
    assert writer_source.index("--write") < writer_source.index('git push origin')
    assert writer_source.index('git push origin') < writer_source.index("--render-pr-body")
    assert writer_source.index("--render-pr-body") < writer_source.index("--method PATCH")
    assert writer_source.index("--method PATCH") < writer_source.rindex("--check")
    assert "python3 scripts/release-context" not in writer_source

    order = {step["name"]: i for i, step in enumerate(ordered) if "name" in step}
    assert order["Inspect merged release state"] < order["Verify exclusive publish candidate"]
    assert order["Verify exclusive publish candidate"] < order["Canonicalize merged Release PR body"]
    assert order["Canonicalize merged Release PR body"] < order["Verify publish preconditions"]
    assert order["Verify publish preconditions"] < order["Publish merged Release PR"]
    assert order["Publish merged Release PR"] < order["Verify published release identity"]
    assert order["Recheck current main for maintenance"] < order["Maintain Release PR"]
    assert order["Maintain Release PR"] < order["Verify pending Release PR identity"]
    assert order["Verify Release PR file boundary"] < order["Write release context"]

    forbidden = {
        ("git", "tag"),
        ("gh", "release"),
        ("npm", "publish"),
        ("twine", "upload"),
        ("cargo", "publish"),
        ("cachix", "push"),
        ("nix", "copy"),
    }
    assert all(
        tuple(argv[:2]) not in forbidden
        for step in named.values()
        if "run" in step
        for argv in command_argvs(step)
    )


def assert_immutable_actions(ci, release):
    uses = [
        step["uses"]
        for workflow in (ci, release)
        for job in workflow["jobs"].values()
        for step in job["steps"]
        if "uses" in step
    ]
    assert set(uses) == {CHECKOUT_ACTION, NIX_ACTION, RELEASE_PLEASE_ACTION}
    assert all(IMMUTABLE_ACTION.fullmatch(action) for action in uses)
    assert uses.count(RELEASE_PLEASE_ACTION) == 2


def main():
    root = Path(sys.argv[1] if len(sys.argv) > 1 else ".").resolve()
    ci = yaml.safe_load((root / ".github/workflows/ci.yaml").read_text(encoding="utf-8"))
    release_text = (root / ".github/workflows/release-please.yaml").read_text(encoding="utf-8")
    release = yaml.safe_load(release_text)
    assert_release_config(root)
    assert_release_context(root)
    assert_release_author_identity()
    assert_ci(ci)
    assert_release_workflow(release, release_text)
    assert_immutable_actions(ci, release)


if __name__ == "__main__":
    main()
