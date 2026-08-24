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
RELEASE_FILES = [".release-please-manifest.json", "CHANGELOG.md", "version.txt"]
SEMVER_IDENTIFIER = r"(?:0|[1-9][0-9]*|[0-9]*[A-Za-z-][0-9A-Za-z-]*)"
SEMVER = re.compile(
    rf"^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)"
    rf"(?:-{SEMVER_IDENTIFIER}(?:\.{SEMVER_IDENTIFIER})*)?"
    r"(?:\+[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?$"
)
IMMUTABLE_ACTION = re.compile(r"^[^@]+@[0-9a-f]{40}$")


def load_json(path):
    return json.loads(path.read_text(encoding="utf-8"))


def trigger(workflow):
    return workflow.get("on", workflow.get(True))


def ordered_steps(workflow, job="release"):
    return workflow["jobs"][job]["steps"]


def named_steps(workflow, job="release"):
    return {
        step["name"]: step
        for step in ordered_steps(workflow, job)
        if "name" in step
    }


def index_of(ordered, named, name):
    return ordered.index(named[name])


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


def assert_contains_all(text, snippets):
    for snippet in snippets:
        assert snippet in text, snippet


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
    assert {
        item["type"]: (item["section"], item.get("hidden", False))
        for item in config["changelog-sections"]
    } == expected_sections

    assert version_text == version + "\n"
    assert SEMVER.fullmatch(version)
    assert manifest == {".": version}
    assert changelog.startswith("# Changelog\n")
    if version == "0.0.0":
        assert changelog == "# Changelog\n"


def assert_release_context(root):
    source = (root / "scripts/release-context").read_text(encoding="utf-8")
    assert_contains_all(
        source,
        (
            'group.add_argument("--write"',
            'group.add_argument("--check"',
            'group.add_argument("--release-notes"',
            'group.add_argument("--render-pr-body"',
            "RELEASE_PR_HEADER",
            "RELEASE_PR_FOOTER",
            "candidate_entry(",
            "render_release_pr_body(",
            'sys.stdout.write(candidate_entry(changelog, version) + "\\n")',
            "sys.stdout.write(render_release_pr_body(changelog, version))",
        ),
    )
    assert "\nimport yaml\n" not in source
    assert "import yaml" in source


def assert_regular_release_files_guard(source, ref_expression):
    assert f'git ls-tree {ref_expression} -- "$path"' in source
    assert 'test "$(awk \'{print $1}\' <<< "$tree_entry")" = 100644' in source
    assert 'test "$(awk \'{print $2}\' <<< "$tree_entry")" = blob' in source
    for path in RELEASE_FILES:
        assert path in source


def assert_ci(ci):
    ci_on = trigger(ci)
    assert ci["name"] == "CI"
    assert ci_on["pull_request"]["branches"] == ["main"]
    assert ci_on["push"]["branches"] == ["main"]
    assert ci["permissions"] == {"contents": "read", "pull-requests": "read"}

    job = ci["jobs"]["validate"]
    assert job["runs-on"] == "ubuntu-24.04"
    ordered = ordered_steps(ci, "validate")
    named = named_steps(ci, "validate")

    checkout = ordered[0]
    assert checkout["uses"] == CHECKOUT_ACTION
    assert checkout["with"] == {"fetch-depth": 0, "persist-credentials": False}

    provenance = named["Verify main PR provenance"]
    assert provenance["if"] == "github.event_name == 'push'"
    assert_contains_all(
        provenance["run"],
        (
            '.merge_commit_sha == $sha',
            'test "$merged_pr_count" = "1"',
        ),
    )

    nix_steps = [step for step in ordered if step.get("uses") == NIX_ACTION]
    assert len(nix_steps) == 1
    assert nix_steps[0]["with"]["github-token"] == ""

    assert named["Canonical checks"]["run"].strip() == "nix shell --inputs-from . nixpkgs#just -c just check"
    assert named["All systems evaluation"]["run"].strip() == "nix flake check --show-trace --print-build-logs --all-systems --no-build"

    owned = named["Release-owned files"]
    assert owned["if"] == "github.event_name == 'pull_request'"
    assert owned["env"] == {
        "BASE_SHA": "${{ github.event.pull_request.base.sha }}",
        "HEAD_SHA": "${{ github.event.pull_request.head.sha }}",
        "HEAD_REPOSITORY": "${{ github.event.pull_request.head.repo.full_name }}",
        "PR_AUTHOR": "${{ github.event.pull_request.user.login }}",
        "PR_TITLE": "${{ github.event.pull_request.title }}",
        "PENDING_RELEASE": "${{ contains(github.event.pull_request.labels.*.name, 'autorelease: pending') }}",
    }
    source = owned["run"]
    assert_contains_all(
        source,
        (
            'git cat-file -e "$BASE_SHA:$path"',
            'git cat-file -e "$HEAD_SHA:$path"',
            'test "$HEAD_REPOSITORY" = "$GITHUB_REPOSITORY"',
            'test "$PR_AUTHOR" = "github-actions[bot]"',
            'test "$PENDING_RELEASE" = true',
            'expected_title="chore(main): release $(cat version.txt)"',
            'test "$PR_TITLE" = "$expected_title"',
            'test "$actual_release_files" = "$expected_release_files"',
            "nix build --inputs-from .",
            "nix shell --inputs-from .",
            "scripts/release-context --check",
        ),
    )
    assert_regular_release_files_guard(source, '"$HEAD_SHA"')


def assert_release_artifact_shape(step):
    source = step["run"]
    assert_contains_all(
        source,
        (
            "--release-notes",
            "git/ref/tags/$tag",
            "'.target_commitish'",
            "'.name'",
            "'.body'",
            "'.draft'",
            "'.prerelease'",
            ' = "$expected_notes"',
        ),
    )


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
    assert release["concurrency"] == {"group": "release-main", "cancel-in-progress": False}
    assert "${{ secrets." not in release_text
    assert "RELEASE_PLEASE_TOKEN" not in release_text

    job = release["jobs"]["release"]
    assert job["runs-on"] == "ubuntu-24.04"
    assert job["if"] == "github.event.workflow_run.conclusion == 'success' && github.event.workflow_run.event == 'push' && github.event.workflow_run.head_branch == 'main'"

    ordered = ordered_steps(release)
    named = named_steps(release)
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
    assert provenance["id"] == "merged-pr"
    assert provenance["working-directory"] == "trusted-main"
    source = provenance["run"]
    assert_contains_all(
        source,
        (
            '.merge_commit_sha == $sha',
            'test "$(jq length <<< "$matches")" = "1"',
            '[ "$author" = "github-actions[bot]" ]',
            'test "$actual_release_files" = "$expected_release_files"',
            'expected_title="chore(main): release $(cat version.txt)"',
            'test "$title" = "$expected_title"',
            "release_commit=true",
        ),
    )
    assert_regular_release_files_guard(source, '"$EXPECTED_SHA"')

    release_state = named["Inspect merged release state"]
    assert release_state["if"] == initial_current + " && steps.merged-pr.outputs.release_commit == 'true'"
    assert_contains_all(
        release_state["run"],
        (
            'test "$(jq -r \' .object.type\' <<< "$tag_json")" = commit'.replace("' .", "'."),
            'test "$(jq -r \' .object.sha\' <<< "$tag_json")" = "$EXPECTED_SHA"'.replace("' .", "'."),
            'test "$target" = "$EXPECTED_SHA"',
            'test "$tag_target" = "$EXPECTED_SHA"',
            'test "$name" = "$tag"',
            'test "$body" = "$expected_notes"',
            'test "$draft" = false',
            'test "$prerelease" = false',
        ),
    )

    canonical = named["Canonicalize merged Release PR body"]
    assert "--render-pr-body" in canonical["run"]
    assert "--method PATCH" in canonical["run"]
    assert 'test "$actual_body" = "$expected_body"' in canonical["run"]

    publish = named["Publish merged Release PR"]
    assert publish["uses"] == RELEASE_PLEASE_ACTION
    assert publish["with"]["skip-github-pull-request"] is True
    assert "steps.merged-pr.outputs.release_commit == 'true'" in publish["if"]
    assert "steps.merged-pr.outputs.pending == 'true'" in publish["if"]
    assert "steps.release-state.outputs.exists != 'true'" in publish["if"]

    published = named["Verify published release identity"]
    assert_contains_all(
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
        ),
    )
    assert 'test "$current_sha" = "$EXPECTED_SHA"' not in published["run"]

    tagged = named["Verify tagged release identity"]
    assert_release_artifact_shape(tagged)

    maintenance = named["Recheck current main for maintenance"]
    assert maintenance["id"] == "maintenance-main"
    assert maintenance["if"] == initial_current
    assert maintenance["working-directory"] == "trusted-main"
    assert_contains_all(
        maintenance["run"],
        (
            'current_sha="$(git ls-remote --refs origin refs/heads/main | cut -f1)"',
            'if [ "$current_sha" = "$EXPECTED_SHA" ]',
            "printf 'current=true\\n'",
            "printf 'current=false\\n'",
        ),
    )

    maintain = named["Maintain Release PR"]
    assert maintain["uses"] == RELEASE_PLEASE_ACTION
    assert maintain["if"] == maintenance_current
    assert maintain["with"]["skip-github-release"] is True
    assert index_of(ordered, named, "Recheck current main for maintenance") < index_of(ordered, named, "Maintain Release PR")

    query = named["Find pending Release PR"]
    assert query["if"] == maintenance_current
    assert_contains_all(
        query["run"],
        (
            '--label "autorelease: pending"',
            "--limit 100",
            "headRepository.nameWithOwner == $repo",
            '.author.login == "github-actions[bot]"',
        ),
    )

    identity = named["Verify pending Release PR identity"]
    assert identity["if"] == candidate
    assert_contains_all(
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
    assert boundary["if"] == candidate
    assert_contains_all(
        boundary["run"],
        (
            'git diff --name-only "$EXPECTED_SHA...HEAD"',
            'test "$actual_release_files" = "$expected_release_files"',
            'expected_title="chore(main): release $(cat version.txt)"',
            'test "$actual_title" = "$expected_title"',
        ),
    )
    assert_regular_release_files_guard(boundary["run"], "HEAD")

    nix_steps = [step for step in ordered if step.get("uses") == NIX_ACTION]
    assert len(nix_steps) == 1
    assert nix_steps[0]["if"] == candidate
    assert nix_steps[0]["with"]["github-token"] == ""

    writer = named["Write release context"]
    assert writer["if"] == candidate
    writer_source = writer["run"]
    assert_contains_all(
        writer_source,
        (
            'nix build --inputs-from "$TRUSTED_ROOT"',
            'nix shell --inputs-from "$TRUSTED_ROOT"',
            'python3 "$TRUSTED_ROOT/scripts/release-context" --write',
            'python3 "$TRUSTED_ROOT/scripts/release-context" --check',
            'python3 "$TRUSTED_ROOT/scripts/release-context" --render-pr-body',
            'test "$remote_candidate_sha" = "$candidate_sha"',
            "gh auth setup-git",
            'git push origin "HEAD:refs/heads/$RELEASE_BRANCH"',
            "--method PATCH",
            'test "$actual_body" = "$expected_body"',
        ),
    )
    assert "python3 scripts/release-context" not in writer_source

    assert index_of(ordered, named, "Canonicalize merged Release PR body") < index_of(ordered, named, "Publish merged Release PR")
    assert index_of(ordered, named, "Publish merged Release PR") < index_of(ordered, named, "Verify published release identity")
    assert index_of(ordered, named, "Maintain Release PR") < index_of(ordered, named, "Verify pending Release PR identity")
    assert index_of(ordered, named, "Verify pending Release PR identity") < ordered.index(candidate_checkout)
    assert ordered.index(candidate_checkout) < index_of(ordered, named, "Verify Release PR file boundary")
    assert index_of(ordered, named, "Verify Release PR file boundary") < index_of(ordered, named, "Write release context")

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
    assert_ci(ci)
    assert_release_workflow(release, release_text)
    assert_immutable_actions(ci, release)


if __name__ == "__main__":
    main()
