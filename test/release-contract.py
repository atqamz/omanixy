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
NIX_INSTALLER_ACTION = "DeterminateSystems/nix-installer-action@ef8a148080ab6020fd15196c2084a2eea5ff2d25"
RELEASE_PLEASE_ACTION = "googleapis/release-please-action@45996ed1f6d02564a971a2fa1b5860e934307cf7"
SEMVER = re.compile(
    r"^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)"
    r"(?:-[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?"
    r"(?:\+[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?$"
)
IMMUTABLE_ACTION = re.compile(r"^[^@]+@[0-9a-f]{40}$")


def load_json(path):
    return json.loads(path.read_text(encoding="utf-8"))


def trigger(workflow):
    return workflow.get("on", workflow.get(True))


def steps(workflow, job):
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
    assert ci["permissions"] == {"contents": "read"}

    ci_steps = steps(ci, "validate")
    assert ci_steps["Format"]["run"].strip() == "nix fmt\ngit diff --exit-code"
    assert ci_steps["Canonical checks"]["run"].strip() == "nix shell nixpkgs#just -c just check"
    assert ci_steps["All systems evaluation"]["run"].strip() == "nix flake check --show-trace --print-build-logs --all-systems --no-build"

    owned = ci_steps["Release-owned files"]
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
    ):
        assert text in source
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
    assert job["if"] == "github.event.workflow_run.conclusion == 'success' && github.event.workflow_run.event == 'push' && github.event.workflow_run.head_branch == 'main'"
    named = steps(release, "release")
    ordered = all_steps(release, "release")
    current = "steps.main-identity.outputs.current == 'true'"
    candidate = current + " && steps.release-pr.outputs.found == 'true'"

    provenance = named["Verify merged PR provenance"]
    assert provenance["env"] == {
        "EXPECTED_SHA": "${{ github.event.workflow_run.head_sha }}",
        "GH_TOKEN": "${{ github.token }}",
    }
    assert 'commits/$EXPECTED_SHA/pulls' in provenance["run"]
    assert '.base.ref == "main"' in provenance["run"]
    assert '.merged_at != null' in provenance["run"]
    assert 'test "$merged_pr_count" = "1"' in provenance["run"]
    assert ordered.index(named["Verify validated main revision"]) < ordered.index(provenance)
    assert ordered.index(provenance) < ordered.index(named["Verify current main identity"])

    assert named["Run Release Please"]["if"] == current
    assert named["Run Release Please"]["uses"] == RELEASE_PLEASE_ACTION
    assert named["Run Release Please"]["with"]["target-branch"] == "main"
    assert "token" not in named["Run Release Please"]["with"]

    query = named["Find pending Release PR"]["run"]
    assert named["Find pending Release PR"]["if"] == current
    assert "headRepository.nameWithOwner == env.GITHUB_REPOSITORY" in query
    assert '.author.login == "github-actions[bot]"' in query
    assert "autorelease: pending" in query
    assert "isDraft == true" not in query

    identity = named["Verify pending Release PR identity"]
    assert identity["if"] == candidate
    assert identity["env"] == {
        "EXPECTED_SHA": "${{ github.event.workflow_run.head_sha }}",
        "GH_TOKEN": "${{ github.token }}",
        "RELEASE_PR_NUMBER": "${{ steps.release-pr.outputs.number }}",
    }
    assert "--jq '.base.sha'" in identity["run"]
    assert 'test "$current_sha" = "$EXPECTED_SHA"' in identity["run"]
    assert 'test "$base_sha" = "$EXPECTED_SHA"' in identity["run"]

    writer = named["Write release context"]
    assert writer["if"] == candidate
    assert writer["env"] == {
        "EXPECTED_SHA": "${{ github.event.workflow_run.head_sha }}"
    }
    assert has_suffix(writer, ("scripts/release-context", "--write"))
    assert has_suffix(writer, ("scripts/release-context", "--check"))
    assert writer["run"].count('test "$current_sha" = "$EXPECTED_SHA"') >= 2
    assert writer["run"].strip().splitlines()[-1] == 'git push origin "HEAD:${{ steps.release-pr.outputs.branch }}"'

    checkout_steps = [item for item in ordered if item.get("uses") == CHECKOUT_ACTION]
    assert len(checkout_steps) == 2
    assert checkout_steps[0]["with"]["ref"] == "${{ github.event.workflow_run.head_sha }}"
    assert checkout_steps[1]["if"] == candidate
    assert checkout_steps[1]["with"]["ref"] == "${{ steps.release-pr.outputs.branch }}"
    assert ordered.index(identity) < ordered.index(checkout_steps[1])

    nix_steps = [item for item in ordered if item.get("uses") == NIX_INSTALLER_ACTION]
    assert len(nix_steps) == 1
    assert nix_steps[0]["if"] == candidate
    assert ordered.index(nix_steps[0]) == ordered.index(checkout_steps[1]) + 1

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
    uses = {
        step["uses"]
        for workflow in (ci, release)
        for job in workflow["jobs"].values()
        for step in job["steps"]
        if "uses" in step
    }
    assert uses == {CHECKOUT_ACTION, NIX_INSTALLER_ACTION, RELEASE_PLEASE_ACTION}
    assert all(IMMUTABLE_ACTION.fullmatch(action) for action in uses)


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
