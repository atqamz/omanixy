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
SEMVER_IDENTIFIER = r"(?:0|[1-9][0-9]*|[0-9]*[A-Za-z-][0-9A-Za-z-]*)"
SEMVER = re.compile(
    rf"^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)"
    rf"(?:-{SEMVER_IDENTIFIER}(?:\.{SEMVER_IDENTIFIER})*)?"
    r"(?:\+[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?$"
)
IMMUTABLE_ACTION = re.compile(r"^[^@]+@[0-9a-f]{40}$")
RELEASE_FILES = [".release-please-manifest.json", "CHANGELOG.md", "version.txt"]


def load_json(path):
    return json.loads(path.read_text(encoding="utf-8"))


def trigger(workflow):
    return workflow.get("on", workflow.get(True))


def named_steps(workflow, job):
    return {
        step["name"]: step
        for step in workflow["jobs"][job]["steps"]
        if "name" in step
    }


def all_steps(workflow, job):
    return workflow["jobs"][job]["steps"]


def command_argvs(step):
    commands = []
    for line in step.get("run", "").splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            argv = shlex.split(line)
        except ValueError:
            continue
        if argv:
            commands.append(argv)
    return commands


def has_suffix(step, suffix):
    suffix = list(suffix)
    return any(argv[-len(suffix) :] == suffix for argv in command_argvs(step))


def assert_release_files(root):
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
    assert "release-as" not in config
    assert all("release-as" not in item for item in config["packages"].values())
    assert version_text == version + "\n"
    assert SEMVER.fullmatch(version)
    assert manifest == {".": version}
    assert changelog.startswith("# Changelog\n")
    if version == "0.0.0":
        assert changelog == "# Changelog\n"

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
    sections = {
        item["type"]: (item["section"], item.get("hidden", False))
        for item in config["changelog-sections"]
    }
    assert sections == expected_sections


def assert_ci(ci):
    ci_on = trigger(ci)
    assert ci["name"] == "CI"
    assert ci_on["pull_request"]["branches"] == ["main"]
    assert ci_on["push"]["branches"] == ["main"]
    assert ci["permissions"] == {"contents": "read", "pull-requests": "read"}

    job = ci["jobs"]["validate"]
    assert job["runs-on"] == "ubuntu-24.04"
    ordered = all_steps(ci, "validate")
    named = named_steps(ci, "validate")

    checkout = ordered[0]
    assert checkout["uses"] == CHECKOUT_ACTION
    assert checkout["with"]["fetch-depth"] == 0
    assert checkout["with"]["persist-credentials"] is False

    provenance = named["Verify main PR provenance"]
    assert provenance["if"] == "github.event_name == 'push'"
    assert '.merge_commit_sha == $sha' in provenance["run"]
    assert 'test "$merged_pr_count" = "1"' in provenance["run"]

    nix_steps = [step for step in ordered if step.get("uses") == NIX_ACTION]
    assert len(nix_steps) == 1
    assert nix_steps[0]["with"]["github-token"] == ""

    assert named["Format"]["run"].strip() == "nix fmt\ngit diff --exit-code"
    assert named["Canonical checks"]["run"].strip() == "nix shell --inputs-from . nixpkgs#just -c just check"
    assert named["All systems evaluation"]["run"].strip() == "nix flake check --show-trace --print-build-logs --all-systems --no-build"

    owned = named["Release-owned files"]
    assert owned["if"] == "github.event_name == 'pull_request'"
    assert owned["env"] == {
        "BASE_SHA": "${{ github.event.pull_request.base.sha }}",
        "HEAD_SHA": "${{ github.event.pull_request.head.sha }}",
        "HEAD_REPOSITORY": "${{ github.event.pull_request.head.repo.full_name }}",
        "PR_AUTHOR": "${{ github.event.pull_request.user.login }}",
        "PENDING_RELEASE": "${{ contains(github.event.pull_request.labels.*.name, 'autorelease: pending') }}",
    }
    source = owned["run"]
    for text in (
        'git cat-file -e "$BASE_SHA:$path"',
        'git cat-file -e "$HEAD_SHA:$path"',
        'test "$HEAD_REPOSITORY" = "$GITHUB_REPOSITORY"',
        'test "$PR_AUTHOR" = "github-actions[bot]"',
        'test "$PENDING_RELEASE" = true',
        'test "$actual_release_files" = "$expected_release_files"',
        "nix build --inputs-from .",
        "nix shell --inputs-from .",
    ):
        assert text in source
    for path in RELEASE_FILES:
        assert path in source
    assert has_suffix(owned, ("scripts/release-context", "--check"))


def assert_release_workflow(release, release_text):
    release_on = trigger(release)
    assert release["name"] == "Release Please"
    assert release_on["workflow_run"]["workflows"] == ["CI"]
    assert release_on["workflow_run"]["types"] == ["completed"]
    assert release_on["workflow_run"]["branches"] == ["main"]
    assert release["permissions"] == {
        "contents": "write",
        "pull-requests": "write",
        "issues": "write",
    }
    assert release["concurrency"] == {
        "group": "release-main",
        "cancel-in-progress": False,
    }
    assert "${{ secrets." not in release_text
    assert "RELEASE_PLEASE_TOKEN" not in release_text

    job = release["jobs"]["release"]
    assert job["runs-on"] == "ubuntu-24.04"
    assert job["if"] == "github.event.workflow_run.conclusion == 'success' && github.event.workflow_run.event == 'push' && github.event.workflow_run.head_branch == 'main'"
    named = named_steps(release, "release")
    ordered = all_steps(release, "release")
    current = "steps.main-identity.outputs.current == 'true'"
    candidate = current + " && steps.release-pr.outputs.found == 'true'"

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
    assert provenance["id"] == "merged-pr"
    assert provenance["working-directory"] == "trusted-main"
    provenance_source = provenance["run"]
    for text in (
        '.merge_commit_sha == $sha',
        'test "$(jq length <<< "$matches")" = "1"',
        '$author" = "github-actions[bot]"',
        'git diff-tree --no-commit-id --name-only -r "$EXPECTED_SHA"',
        'test "$actual_release_files" = "$expected_release_files"',
        "release_commit=true",
    ):
        assert text in provenance_source
    for path in RELEASE_FILES:
        assert path in provenance_source

    publish = named["Publish merged Release PR"]
    maintain = named["Maintain Release PR"]
    assert publish["uses"] == RELEASE_PLEASE_ACTION
    assert publish["with"]["skip-github-pull-request"] is True
    assert "steps.merged-pr.outputs.release_commit == 'true'" in publish["if"]
    assert "steps.merged-pr.outputs.pending == 'true'" in publish["if"]
    assert "steps.release-state.outputs.exists != 'true'" in publish["if"]
    assert maintain["uses"] == RELEASE_PLEASE_ACTION
    assert maintain["if"] == current
    assert maintain["with"]["skip-github-release"] is True
    assert ordered.index(publish) < ordered.index(maintain)

    release_state = named["Inspect merged release state"]
    assert release_state["working-directory"] == "trusted-main"
    assert 'test "$target" = "$EXPECTED_SHA"' in release_state["run"]
    published = named["Verify published release identity"]
    assert published["working-directory"] == "trusted-main"
    for text in (
        'test "$RELEASE_CREATED" = true',
        'test "$RELEASE_SHA" = "$EXPECTED_SHA"',
        'test "$RELEASE_TAG" = "v$(cat version.txt)"',
        'test "$current_sha" = "$EXPECTED_SHA"',
    ):
        assert text in published["run"]

    query = named["Find pending Release PR"]
    assert query["if"] == current
    assert '--label "autorelease: pending"' in query["run"]
    assert "--limit 100" in query["run"]
    assert "headRepository.nameWithOwner == $repo" in query["run"]
    assert '.author.login == "github-actions[bot]"' in query["run"]

    identity = named["Verify pending Release PR identity"]
    assert identity["id"] == "candidate-identity"
    assert identity["if"] == candidate
    assert identity["working-directory"] == "trusted-main"
    identity_source = identity["run"]
    for text in (
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
        "printf 'head_sha=%s\\n'",
    ):
        assert text in identity_source

    assert candidate_checkout["if"] == candidate
    assert candidate_checkout["with"] == {
        "ref": "${{ steps.candidate-identity.outputs.head_sha }}",
        "fetch-depth": 0,
        "path": "release-pr",
        "persist-credentials": False,
    }

    boundary = named["Verify Release PR file boundary"]
    assert boundary["if"] == candidate
    assert boundary["working-directory"] == "release-pr"
    assert 'git diff --name-only "$EXPECTED_SHA...HEAD"' in boundary["run"]
    assert 'test "$actual_release_files" = "$expected_release_files"' in boundary["run"]
    for path in RELEASE_FILES:
        assert path in boundary["run"]

    nix_steps = [step for step in ordered if step.get("uses") == NIX_ACTION]
    assert len(nix_steps) == 1
    assert nix_steps[0]["if"] == candidate
    assert nix_steps[0]["with"]["github-token"] == ""

    writer = named["Write release context"]
    assert writer["if"] == candidate
    assert writer["working-directory"] == "release-pr"
    assert writer["env"] == {
        "EXPECTED_SHA": "${{ github.event.workflow_run.head_sha }}",
        "TRUSTED_ROOT": "${{ github.workspace }}/trusted-main",
        "RELEASE_BRANCH": "${{ steps.release-pr.outputs.branch }}",
        "GH_TOKEN": "${{ github.token }}",
    }
    source = writer["run"]
    assert source.count('test "$current_sha" = "$EXPECTED_SHA"') >= 2
    assert "nix build --inputs-from \"$TRUSTED_ROOT\"" in source
    assert "nix shell --inputs-from \"$TRUSTED_ROOT\"" in source
    assert 'python3 "$TRUSTED_ROOT/scripts/release-context" --write' in source
    assert 'python3 "$TRUSTED_ROOT/scripts/release-context" --check' in source
    assert 'python3 scripts/release-context' not in source
    assert 'test "$remote_candidate_sha" = "$candidate_sha"' in source
    assert "gh auth setup-git" in source
    assert 'git push origin "HEAD:refs/heads/$RELEASE_BRANCH"' in source
    assert "${{ steps.release-pr.outputs.branch }}" not in source

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
    assert_release_files(root)
    assert_ci(ci)
    assert_release_workflow(release, release_text)
    assert_immutable_actions(ci, release)


if __name__ == "__main__":
    main()
