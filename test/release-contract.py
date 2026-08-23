#!/usr/bin/env python3
import json
import re
import shlex
import sys
from pathlib import Path

import yaml


BOOTSTRAP_SHA = "ce7d3d8b53bec61585ca9efa377fdb3ae6763499"
SEMVER = re.compile(
    r"^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)"
    r"(?:-[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?"
    r"(?:\+[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?$"
)


def load_json(path):
    return json.loads(path.read_text(encoding="utf-8"))


def workflow_trigger(workflow):
    return workflow.get("on", workflow.get(True))


def workflow_job(workflow, name):
    return workflow["jobs"][name]


def workflow_steps(workflow, job_name):
    return {step["name"]: step for step in workflow_job(workflow, job_name)["steps"] if "name" in step}


def workflow_all_steps(workflow, job_name):
    return workflow_job(workflow, job_name)["steps"]


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
    return any(argv[-len(expected):] == expected for argv in run_argvs(step))


def all_strings(value):
    if isinstance(value, dict):
        for item in value.values():
            yield from all_strings(item)
    elif isinstance(value, list):
        for item in value:
            yield from all_strings(item)
    elif isinstance(value, str):
        yield value


def assert_release_files(root):
    config = load_json(root / "release-please-config.json")
    manifest = load_json(root / ".release-please-manifest.json")
    version = (root / "version.txt").read_text(encoding="utf-8")
    changelog = (root / "CHANGELOG.md").read_text(encoding="utf-8")

    assert config["$schema"] == "https://raw.githubusercontent.com/googleapis/release-please/main/schemas/config.json"
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


def assert_workflows(root):
    ci_path = root / ".github/workflows/ci.yaml"
    release_path = root / ".github/workflows/release-please.yaml"
    ci = yaml.safe_load(ci_path.read_text(encoding="utf-8"))
    release = yaml.safe_load(release_path.read_text(encoding="utf-8"))
    ci_on = workflow_trigger(ci)
    release_on = workflow_trigger(release)

    assert ci["name"] == "CI"
    assert ci_on["pull_request"]["branches"] == ["main"]
    assert ci_on["push"]["branches"] == ["main"]
    assert ci["permissions"] == {"contents": "read"}

    assert release["name"] == "Release Please"
    assert release_on["workflow_run"]["workflows"] == ["CI"]
    assert release_on["workflow_run"]["types"] == ["completed"]
    assert release_on["workflow_run"]["branches"] == ["main"]
    assert release["permissions"] == {"contents": "read"}
    assert release["concurrency"] == {
        "group": "release-main",
        "cancel-in-progress": False,
    }
    ci_steps = workflow_steps(ci, "validate")
    assert ci_steps["Format"]["run"].strip() == "nix fmt\ngit diff --exit-code"
    assert ci_steps["Canonical checks"]["run"].strip() == "nix shell nixpkgs#just -c just check"
    assert ci_steps["All systems evaluation"]["run"].strip() == "nix flake check --show-trace --print-build-logs --all-systems --no-build"
    assert ci_steps["Release-owned files"]["if"] == "github.event_name == 'pull_request'"
    assert has_command_suffix(ci_steps["Release-owned files"], ("scripts/release-context", "--check"))

    release_job = workflow_job(release, "release")
    assert release_job["if"] == "github.event.workflow_run.conclusion == 'success' && github.event.workflow_run.event == 'push' && github.event.workflow_run.head_branch == 'main'"
    release_steps = workflow_steps(release, "release")
    release_all_steps = workflow_all_steps(release, "release")
    assert release_steps["Require release credential"]["env"] == {
        "RELEASE_PLEASE_TOKEN": "${{ secrets.RELEASE_PLEASE_TOKEN }}"
    }
    assert release_steps["Run Release Please"]["with"]["token"] == "${{ secrets.RELEASE_PLEASE_TOKEN }}"
    assert release_steps["Write release context"]["run"].strip().splitlines()[-1] == 'git push origin "HEAD:${{ steps.release-pr.outputs.branch }}"'
    assert has_command_suffix(release_steps["Write release context"], ("scripts/release-context", "--write"))
    assert has_command_suffix(release_steps["Write release context"], ("scripts/release-context", "--check"))
    release_runs = [step for step in release_steps.values() if "run" in step]
    forbidden_commands = {
        ("git", "tag"),
        ("gh", "release"),
        ("npm", "publish"),
        ("twine", "upload"),
        ("cargo", "publish"),
        ("cachix", "push"),
        ("nix", "copy"),
    }
    assert all(
        tuple(argv[:2]) not in forbidden_commands
        for step in release_runs
        for argv in run_argvs(step)
    )
    assert all("github.event.pull_request.actor" not in value for value in all_strings(release))
    assert all("github.token" not in value for value in all_strings(release))
    assert all("secrets.GITHUB_TOKEN" not in value for value in all_strings(release))

    checkouts = [step for step in release_all_steps if step.get("uses") == "actions/checkout@v7"]
    assert checkouts[0]["with"]["ref"] == "${{ github.event.workflow_run.head_sha }}"
    assert checkouts[1]["with"]["ref"] == "${{ steps.release-pr.outputs.branch }}"

    release_action = release_steps["Run Release Please"]
    assert release_action["uses"] == "googleapis/release-please-action@v5"
    assert release_action["with"]["target-branch"] == "main"

    uses = {
        step.get("uses")
        for workflow in (ci, release)
        for job in workflow["jobs"].values()
        for step in job["steps"]
    }
    assert "actions/checkout@v7" in uses
    assert "DeterminateSystems/nix-installer-action@v22" in uses
    assert "googleapis/release-please-action@v5" in uses


def main():
    root = Path(sys.argv[1] if len(sys.argv) > 1 else ".").resolve()
    assert_release_files(root)
    assert_workflows(root)


if __name__ == "__main__":
    main()
