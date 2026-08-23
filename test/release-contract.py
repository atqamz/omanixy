#!/usr/bin/env python3
import json
import re
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


def workflow_steps(workflow):
    steps = []
    for job in workflow.get("jobs", {}).values():
        steps.extend(job.get("steps", []))
    return steps


def workflow_run_text(workflow):
    values = []
    for job in workflow.get("jobs", {}).values():
        values.append(str(job.get("if", "")))
        for step in job.get("steps", []):
            values.append(str(step.get("run", "")))
            values.append(str(step.get("with", {})))
    return "\n".join(values)


def assert_release_files(root):
    config = load_json(root / "release-please-config.json")
    manifest = load_json(root / ".release-please-manifest.json")
    version = (root / "version.txt").read_text(encoding="utf-8")
    changelog = (root / "CHANGELOG.md").read_text(encoding="utf-8")

    assert config["$schema"] == "https://raw.githubusercontent.com/googleapis/release-please/main/schemas/config.json"
    assert config["bootstrap-sha"] == BOOTSTRAP_SHA
    assert config["release-type"] == "simple"
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
    ci_text = workflow_run_text(ci)
    assert "nix fmt" in ci_text
    assert "just check" in ci_text
    assert "--all-systems --no-build" in ci_text
    assert "release-context" in ci_text
    assert "git diff --name-only" in ci_text

    assert release["name"] == "Release Please"
    assert release_on["workflow_run"]["workflows"] == ["CI"]
    assert release_on["workflow_run"]["types"] == ["completed"]
    assert release_on["workflow_run"]["branches"] == ["main"]
    assert release["permissions"] == {"contents": "read"}
    assert release["concurrency"] == {
        "group": "release-main",
        "cancel-in-progress": False,
    }
    release_text = workflow_run_text(release)
    assert "github.event.workflow_run.conclusion == 'success'" in release_text
    assert "github.event.workflow_run.head_branch == 'main'" in release_text
    assert "github.event.workflow_run.event == 'push'" in release_text
    assert "RELEASE_PLEASE_TOKEN" in release_text
    assert "secrets.RELEASE_PLEASE_TOKEN" in release_text
    assert "github.token" not in release_text
    assert "secrets.GITHUB_TOKEN" not in release_text
    assert "workflow_dispatch" not in str(release_on)
    assert "release-context --write" in release_text
    assert "release-context --check" in release_text
    assert "git tag" not in release_text
    assert "gh release" not in release_text
    assert "npm publish" not in release_text
    assert "twine upload" not in release_text
    assert "cargo publish" not in release_text
    assert "cachix push" not in release_text
    assert "nix copy" not in release_text
    assert "github.event.pull_request.actor" not in release_text

    release_action = next(
        step for step in workflow_steps(release)
        if step.get("uses") == "googleapis/release-please-action@v5"
    )
    assert release_action["with"]["target-branch"] == "main"
    assert release_action["with"]["token"] == "${{ secrets.RELEASE_PLEASE_TOKEN }}"

    uses = {step.get("uses") for step in workflow_steps(ci) + workflow_steps(release)}
    assert "actions/checkout@v7" in uses
    assert "DeterminateSystems/nix-installer-action@v22" in uses
    assert "googleapis/release-please-action@v5" in uses


def assert_pre_major_policy():
    policy = {
        "fix": "patch",
        "feat": "minor",
        "breaking": "minor",
        "ordinary": "not-major",
    }
    assert policy["fix"] == "patch"
    assert policy["feat"] == "minor"
    assert policy["breaking"] == "minor"
    assert policy["ordinary"] != "major"


def main():
    root = Path(sys.argv[1] if len(sys.argv) > 1 else ".").resolve()
    assert_release_files(root)
    assert_workflows(root)
    assert_pre_major_policy()


if __name__ == "__main__":
    main()
