#!/usr/bin/env python3
import json
import re
import shlex
import sys
from pathlib import Path

import yaml


BOOTSTRAP_SHA = "ce7d3d8b53bec61585ca9efa377fdb3ae6763499"
RELEASE_PLEASE_SCHEMA = "https://raw.githubusercontent.com/googleapis/release-please/v17.6.0/schemas/config.json"
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


def workflow_trigger(workflow):
    return workflow.get("on", workflow.get(True))


def workflow_job(workflow, name):
    return workflow["jobs"][name]


def workflow_steps(workflow, name):
    return {
        step["name"]: step
        for step in workflow_job(workflow, name)["steps"]
        if "name" in step
    }


def workflow_all_steps(workflow, name):
    return workflow_job(workflow, name)["steps"]


def run_argvs(step):
    commands = []
    for line in step.get("run", "").splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        try:
            argv = shlex.split(stripped)
        except ValueError:
            continue
        if argv:
            commands.append(argv)
    return commands


def has_command_suffix(step, suffix):
    expected = list(suffix)
    return any(argv[-len(expected) :] == expected for argv in run_argvs(step))


def pending_release_prs(pull_requests, repository):
    matches = []
    for pull_request in pull_requests:
        head_repository = pull_request.get("headRepository") or {}
        author = pull_request.get("author") or {}
        labels = {label["name"] for label in pull_request.get("labels", [])}
        if (
            pull_request.get("state") == "OPEN"
            and pull_request.get("baseRefName") == "main"
            and head_repository.get("nameWithOwner") == repository
            and author.get("login") == "github-actions[bot]"
            and "autorelease: pending" in labels
        ):
            matches.append(pull_request)
    assert len(matches) <= 1
    return matches


def assert_pending_release_pr_identity():
    repository = "atqamz/omanixy"

    def pull_request(
        pending=True,
        base="main",
        head_repository=repository,
        author="github-actions[bot]",
    ):
        return {
            "state": "OPEN",
            "baseRefName": base,
            "headRepository": {"nameWithOwner": head_repository},
            "author": {"login": author},
            "labels": [{"name": "autorelease: pending"}] if pending else [],
        }

    assert len(pending_release_prs([pull_request()], repository)) == 1
    assert pending_release_prs([pull_request(pending=False)], repository) == []
    assert pending_release_prs([pull_request(base="develop")], repository) == []
    assert pending_release_prs([pull_request(head_repository="someone/else")], repository) == []
    assert pending_release_prs([pull_request(author="atqamz")], repository) == []
    try:
        pending_release_prs([pull_request(), pull_request()], repository)
    except AssertionError:
        pass
    else:
        raise AssertionError("duplicate pending Release PRs must fail closed")


def assert_release_files(root):
    config = load_json(root / "release-please-config.json")
    manifest = load_json(root / ".release-please-manifest.json")
    version = (root / "version.txt").read_text(encoding="utf-8")
    changelog = (root / "CHANGELOG.md").read_text(encoding="utf-8")

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
    assert all("release-as" not in package for package in config["packages"].values())
    assert manifest == {".": version.strip()}
    assert version == version.strip() + "\n"
    assert SEMVER.fullmatch(version.strip())
    assert changelog.startswith("# Changelog\n")
    if version.strip() == "0.0.0":
        assert changelog == "# Changelog\n"
    else:
        assert re.search(
            rf"^## (?:\[)?v?{re.escape(version.strip())}(?:\])?(?:\([^)]*\))?(?:\s|$)",
            changelog,
            re.MULTILINE,
        )

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


def assert_release_owned_file_gate(step):
    assert step["if"] == "github.event_name == 'pull_request'"
    assert step["env"] == {
        "BASE_SHA": "${{ github.event.pull_request.base.sha }}",
        "HEAD_SHA": "${{ github.event.pull_request.head.sha }}",
        "HEAD_REPOSITORY": "${{ github.event.pull_request.head.repo.full_name }}",
        "PR_AUTHOR": "${{ github.event.pull_request.user.login }}",
        "PENDING_RELEASE": "${{ contains(github.event.pull_request.labels.*.name, 'autorelease: pending') }}",
    }
    source = step["run"]
    for required in (
        'git cat-file -e "$BASE_SHA:$path"',
        'git cat-file -e "$HEAD_SHA:$path"',
        'test "$HEAD_REPOSITORY" = "$GITHUB_REPOSITORY"',
        'test "$PR_AUTHOR" = "github-actions[bot]"',
        'test "$PENDING_RELEASE" = true',
    ):
        assert required in source
    assert has_command_suffix(step, ("scripts/release-context", "--check"))


def assert_workflows(root):
    ci = yaml.safe_load((root / ".github/workflows/ci.yaml").read_text(encoding="utf-8"))
    release_text = (root / ".github/workflows/release-please.yaml").read_text(encoding="utf-8")
    release = yaml.safe_load(release_text)
    ci_on = workflow_trigger(ci)
    release_on = workflow_trigger(release)

    assert ci["name"] == "CI"
    assert ci_on["pull_request"]["branches"] == ["main"]
    assert ci_on["push"]["branches"] == ["main"]
    assert ci["permissions"] == {"contents": "read"}

    ci_steps = workflow_steps(ci, "validate")
    assert ci_steps["Format"]["run"].strip() == "nix fmt\ngit diff --exit-code"
    assert ci_steps["Canonical checks"]["run"].strip() == "nix shell nixpkgs#just -c just check"
    assert ci_steps["All systems evaluation"]["run"].strip() == "nix flake check --show-trace --print-build-logs --all-systems --no-build"
    assert_release_owned_file_gate(ci_steps["Release-owned files"])

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

    release_job = workflow_job(release, "release")
    assert release_job["if"] == "github.event.workflow_run.conclusion == 'success' && github.event.workflow_run.event == 'push' && github.event.workflow_run.head_branch == 'main'"
    release_steps = workflow_steps(release, "release")
    release_all_steps = workflow_all_steps(release, "release")
    indices = {
        step["name"]: index
        for index, step in enumerate(release_all_steps)
        if "name" in step
    }

    current_condition = "steps.main-identity.outputs.current == 'true'"
    release_pr_condition = current_condition + " && steps.release-pr.outputs.found == 'true'"

    assert release_steps["Run Release Please"]["if"] == current_condition
    assert release_steps["Run Release Please"]["uses"] == RELEASE_PLEASE_ACTION
    assert release_steps["Run Release Please"]["with"]["target-branch"] == "main"
    assert "token" not in release_steps["Run Release Please"]["with"]
    assert indices["Run Release Please"] == indices["Verify current main identity"] + 1

    pending_query = release_steps["Find pending Release PR"]["run"]
    assert release_steps["Find pending Release PR"]["if"] == current_condition
    assert "headRepository.nameWithOwner == env.GITHUB_REPOSITORY" in pending_query
    assert '.author.login == "github-actions[bot]"' in pending_query
    assert "autorelease: pending" in pending_query
    assert "isDraft == true" not in pending_query

    identity = release_steps["Verify pending Release PR identity"]
    assert identity["if"] == release_pr_condition
    assert identity["env"] == {
        "EXPECTED_SHA": "${{ github.event.workflow_run.head_sha }}",
        "GH_TOKEN": "${{ github.token }}",
        "RELEASE_PR_NUMBER": "${{ steps.release-pr.outputs.number }}",
    }
    identity_source = identity["run"]
    assert "--jq '.base.sha'" in identity_source
    assert 'test "$current_sha" = "$EXPECTED_SHA"' in identity_source
    assert 'test "$base_sha" = "$EXPECTED_SHA"' in identity_source

    write_context = release_steps["Write release context"]
    assert write_context["if"] == release_pr_condition
    assert write_context["env"] == {
        "EXPECTED_SHA": "${{ github.event.workflow_run.head_sha }}"
    }
    assert has_command_suffix(write_context, ("scripts/release-context", "--write"))
    assert has_command_suffix(write_context, ("scripts/release-context", "--check"))
    assert write_context["run"].count('test "$current_sha" = "$EXPECTED_SHA"') >= 2
    assert write_context["run"].strip().splitlines()[-1] == 'git push origin "HEAD:${{ steps.release-pr.outputs.branch }}"'

    checkouts = [step for step in release_all_steps if step.get("uses") == CHECKOUT_ACTION]
    assert len(checkouts) == 2
    assert checkouts[0]["with"]["ref"] == "${{ github.event.workflow_run.head_sha }}"
    assert checkouts[1]["with"]["ref"] == "${{ steps.release-pr.outputs.branch }}"
    assert checkouts[1]["if"] == release_pr_condition
    assert indices["Verify pending Release PR identity"] < release_all_steps.index(checkouts[1])

    nix_steps = [step for step in release_all_steps if step.get("uses") == NIX_INSTALLER_ACTION]
    assert len(nix_steps) == 1
    assert nix_steps[0]["if"] == release_pr_condition
    assert release_all_steps.index(nix_steps[0]) == release_all_steps.index(checkouts[1]) + 1

    forbidden_commands = {
        ("git", "tag"),
        ("gh", "release"),
        ("npm", "publish"),
        ("twine", "upload"),
        ("cargo", "publish"),
        ("cachix", "push"),
        ("nix", "copy"),
    }
    release_runs = [step for step in release_steps.values() if "run" in step]
    assert all(
        tuple(argv[:2]) not in forbidden_commands
        for step in release_runs
        for argv in run_argvs(step)
    )

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
    assert_release_files(root)
    assert_workflows(root)
    assert_pending_release_pr_identity()


if __name__ == "__main__":
    main()
