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


def workflow_job(workflow, name):
    return workflow["jobs"][name]


def workflow_steps(workflow, job_name):
    return {step["name"]: step for step in workflow_job(workflow, job_name)["steps"] if "name" in step}


def workflow_all_steps(workflow, job_name):
    return workflow_job(workflow, job_name)["steps"]


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
    assert ci_steps["Release-owned files"]["if"] == "github.event_name == 'pull_request'"

    release_job = workflow_job(release, "release")
    assert release_job["if"] == "github.event.workflow_run.conclusion == 'success' && github.event.workflow_run.event == 'push' && github.event.workflow_run.head_branch == 'main'"
    release_steps = workflow_steps(release, "release")
    release_all_steps = workflow_all_steps(release, "release")
    assert release_steps["Require release credential"]["env"] == {
        "RELEASE_PLEASE_TOKEN": "${{ secrets.RELEASE_PLEASE_TOKEN }}"
    }
    assert release_steps["Run Release Please"]["with"]["token"] == "${{ secrets.RELEASE_PLEASE_TOKEN }}"

    checkouts = [step for step in release_all_steps if step.get("uses") == "actions/checkout@v7"]
    assert checkouts[0]["with"]["ref"] == "${{ github.event.workflow_run.head_sha }}"
    assert checkouts[1]["with"]["ref"] == "${{ steps.release-pr.outputs.branch }}"

    release_action = release_steps["Run Release Please"]
    assert release_action["uses"] == "googleapis/release-please-action@v5"
    assert release_action["with"]["target-branch"] == "main"
    assert release_action["with"]["skip-github-release"] is True

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
