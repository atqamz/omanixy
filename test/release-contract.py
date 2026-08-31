#!/usr/bin/env python3
import json
import os
import re
import shlex
import subprocess
import sys
import tempfile
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


def run_command(argv, cwd):
    result = subprocess.run(argv, cwd=cwd, text=True, capture_output=True, check=False)
    assert result.returncode == 0, result.stderr
    return result.stdout.strip()


def create_release_fixture():
    temporary = tempfile.TemporaryDirectory()
    root = Path(temporary.name)
    remote = root / "remote.git"
    repository = root / "repository"
    run_command(["git", "init", "--bare", str(remote)], root)
    run_command(["git", "init", "-b", "main", str(repository)], root)
    run_command(["git", "config", "user.name", "fixture"], repository)
    run_command(["git", "config", "user.email", "fixture@example.invalid"], repository)
    run_command(["git", "remote", "add", "origin", str(remote)], repository)

    (repository / ".release-please-manifest.json").write_text('{".": "0.0.0"}\n', encoding="utf-8")
    (repository / "CHANGELOG.md").write_text("# Changelog\n", encoding="utf-8")
    (repository / "version.txt").write_text("0.0.0\n", encoding="utf-8")
    run_command(["git", "add", *RELEASE_FILES], repository)
    run_command(["git", "commit", "-m", "chore: fixture baseline"], repository)
    parent_sha = run_command(["git", "rev-parse", "HEAD"], repository)

    (repository / ".release-please-manifest.json").write_text('{".": "0.1.0"}\n', encoding="utf-8")
    (repository / "CHANGELOG.md").write_text("# Changelog\n\n## 0.1.0\n\n* fixture\n", encoding="utf-8")
    (repository / "version.txt").write_text("0.1.0\n", encoding="utf-8")
    run_command(["git", "add", *RELEASE_FILES], repository)
    run_command(["git", "commit", "-m", "chore(main): release 0.1.0"], repository)
    release_sha = run_command(["git", "rev-parse", "HEAD"], repository)

    (repository / "main.txt").write_text("validated main\n", encoding="utf-8")
    run_command(["git", "add", "main.txt"], repository)
    run_command(["git", "commit", "-m", "fix: advance main"], repository)
    validated_sha = run_command(["git", "rev-parse", "HEAD"], repository)
    run_command(["git", "push", "origin", "HEAD:refs/heads/main"], repository)
    return temporary, root, remote, repository, parent_sha, release_sha, validated_sha


def write_gh_fixture(root, pending_prs, pr_json, associated_prs):
    fixture = root / "gh-fixture"
    fixture.mkdir(exist_ok=True)
    pending_path = fixture / "pending.json"
    pr_path = fixture / "pr.json"
    associated_path = fixture / "associated.json"
    pending_path.write_text(json.dumps(pending_prs), encoding="utf-8")
    pr_path.write_text(json.dumps(pr_json), encoding="utf-8")
    associated_path.write_text(json.dumps(associated_prs), encoding="utf-8")
    gh = fixture / "gh"
    gh.write_text(
        f"#!{sys.executable}\n"
        "import sys\n"
        "from pathlib import Path\n"
        f"pending = Path({str(pending_path)!r})\n"
        f"pr = Path({str(pr_path)!r})\n"
        f"associated = Path({str(associated_path)!r})\n"
        "if sys.argv[1:3] == ['pr', 'list']:\n"
        "    print(pending.read_text(encoding='utf-8'), end='')\n"
        "elif sys.argv[1] == 'api':\n"
        "    endpoint = sys.argv[2]\n"
        "    if '/pulls/' in endpoint:\n"
        "        print(pr.read_text(encoding='utf-8'), end='')\n"
        "    elif '/commits/' in endpoint and endpoint.endswith('/pulls'):\n"
        "        print(associated.read_text(encoding='utf-8'), end='')\n"
        "    else:\n"
        "        raise SystemExit(1)\n"
        "else:\n"
        "    raise SystemExit(1)\n",
        encoding="utf-8",
    )
    gh.chmod(0o755)
    return fixture


def run_workflow_script(source, cwd, environment):
    env = os.environ.copy()
    env.update(environment)
    return subprocess.run(
        ["bash", "-euo", "pipefail", "-c", source],
        cwd=cwd,
        env=env,
        text=True,
        capture_output=True,
        check=False,
    )


def output_values(path):
    return dict(line.split("=", 1) for line in path.read_text(encoding="utf-8").splitlines())


def release_pr_fixture(release_sha):
    return {
        "number": 57,
        "base": {"ref": "main", "repo": {"full_name": "atqamz/omanixy"}},
        "head": {"repo": {"full_name": "atqamz/omanixy"}},
        "merged_at": "2026-08-30T17:05:32Z",
        "merge_commit_sha": release_sha,
        "user": {"login": "github-actions[bot]"},
        "title": "chore(main): release 0.1.0",
        "labels": [{"name": "autorelease: pending"}],
    }


def assert_release_candidate_fixtures(source):
    temporary, root, _remote, repository, parent_sha, release_sha, validated_sha = create_release_fixture()
    try:
        pr_json = release_pr_fixture(release_sha)
        associated_prs = [
            {
                "number": 57,
                "base": {"ref": "main"},
                "merged_at": pr_json["merged_at"],
                "merge_commit_sha": release_sha,
            }
        ]
        fixture = write_gh_fixture(root, [{"number": 57}], pr_json, associated_prs)
        output = root / "candidate-output"
        result = run_workflow_script(
            source,
            repository,
            {
                "GITHUB_OUTPUT": str(output),
                "GITHUB_REPOSITORY": "atqamz/omanixy",
                "PATH": f"{fixture}:{os.environ['PATH']}",
                "VALIDATED_SHA": validated_sha,
            },
        )
        assert result.returncode == 0, (result.returncode, result.stdout, result.stderr)
        values = output_values(output)
        assert values == {
            "found": "true",
            "number": "57",
            "release_sha": release_sha,
            "release_commit": "true",
            "pending": "true",
        }, values

        output = root / "multiple-output"
        fixture = write_gh_fixture(root, [{"number": 57}, {"number": 58}], pr_json, associated_prs)
        result = run_workflow_script(
            source,
            repository,
            {
                "GITHUB_OUTPUT": str(output),
                "GITHUB_REPOSITORY": "atqamz/omanixy",
                "PATH": f"{fixture}:{os.environ['PATH']}",
                "VALIDATED_SHA": validated_sha,
            },
        )
        assert result.returncode != 0

        output = root / "author-output"
        wrong_author = {**pr_json, "user": {"login": "human"}}
        fixture = write_gh_fixture(root, [{"number": 57}], wrong_author, associated_prs)
        result = run_workflow_script(
            source,
            repository,
            {
                "GITHUB_OUTPUT": str(output),
                "GITHUB_REPOSITORY": "atqamz/omanixy",
                "PATH": f"{fixture}:{os.environ['PATH']}",
                "VALIDATED_SHA": validated_sha,
            },
        )
        assert result.returncode != 0

        output = root / "unvalidated-output"
        fixture = write_gh_fixture(root, [{"number": 57}], pr_json, associated_prs)
        result = run_workflow_script(
            source,
            repository,
            {
                "GITHUB_OUTPUT": str(output),
                "GITHUB_REPOSITORY": "atqamz/omanixy",
                "PATH": f"{fixture}:{os.environ['PATH']}",
                "VALIDATED_SHA": parent_sha,
            },
        )
        assert result.returncode == 0, (result.returncode, result.stdout, result.stderr)
        assert output_values(output) == {
            "found": "true",
            "number": "57",
            "release_sha": release_sha,
            "release_commit": "false",
            "pending": "true",
        }
    finally:
        temporary.cleanup()


def push_unrelated_main(root, remote):
    repository = root / "unrelated"
    run_command(["git", "init", "-b", "main", str(repository)], root)
    run_command(["git", "config", "user.name", "fixture"], repository)
    run_command(["git", "config", "user.email", "fixture@example.invalid"], repository)
    (repository / "unrelated.txt").write_text("unrelated main\n", encoding="utf-8")
    run_command(["git", "add", "unrelated.txt"], repository)
    run_command(["git", "commit", "-m", "fix: replace main"], repository)
    unrelated_sha = run_command(["git", "rev-parse", "HEAD"], repository)
    run_command(["git", "push", "--force", str(remote), "HEAD:refs/heads/main"], repository)
    return unrelated_sha


def assert_release_ancestry_fixtures(source):
    temporary, root, remote, repository, _parent_sha, release_sha, validated_sha = create_release_fixture()
    try:
        output = root / "stale-output"
        result = run_workflow_script(
            source,
            repository,
            {
                "GITHUB_OUTPUT": str(output),
                "RELEASE_COMMIT": "true",
                "RELEASE_SHA": release_sha,
                "VALIDATED_SHA": release_sha,
            },
        )
        assert result.returncode == 0, result.stderr
        assert output_values(output) == {
            "current": "false",
            "release_eligible": "true",
        }

        output = root / "current-output"
        result = run_workflow_script(
            source,
            repository,
            {
                "GITHUB_OUTPUT": str(output),
                "RELEASE_COMMIT": "false",
                "RELEASE_SHA": "",
                "VALIDATED_SHA": validated_sha,
            },
        )
        assert result.returncode == 0, result.stderr
        assert output_values(output) == {
            "current": "true",
            "release_eligible": "false",
        }

        push_unrelated_main(root, remote)
        output = root / "rejected-output"
        result = run_workflow_script(
            source,
            repository,
            {
                "GITHUB_OUTPUT": str(output),
                "RELEASE_COMMIT": "true",
                "RELEASE_SHA": release_sha,
                "VALIDATED_SHA": validated_sha,
            },
        )
        assert result.returncode != 0
    finally:
        temporary.cleanup()


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
    return config


def assert_release_please_invocation_agreement(publish, maintain, config):
    shared = {
        "config-file": "release-please-config.json",
        "manifest-file": ".release-please-manifest.json",
        "target-branch": "main",
    }
    assert publish["with"] == {
        **shared,
        "skip-github-pull-request": True,
    }
    assert maintain["with"] == {
        **shared,
        "skip-github-release": True,
    }
    config_options = {
        "release-type": config["release-type"],
        "include-component-in-tag": config["include-component-in-tag"],
    }
    for invocation in (publish["with"], maintain["with"]):
        assert set(config_options).isdisjoint(invocation)


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


def assert_release_workflow(release, release_text, config):
    release_on = trigger(release)
    assert release["name"] == "Release Please"
    assert release_on["workflow_run"] == {"workflows": ["CI"], "types": ["completed"], "branches": ["main"]}
    assert release["permissions"] == {"contents": "write", "pull-requests": "write", "issues": "write"}
    assert release["concurrency"] == {"group": "release-main", "cancel-in-progress": False}
    assert "${{ secrets." not in release_text
    assert "RELEASE_PLEASE_TOKEN" not in release_text
    assert "EXPECTED_SHA" not in release_text

    job = release["jobs"]["release"]
    assert job["runs-on"] == "ubuntu-24.04"
    assert job["if"] == "github.event.workflow_run.conclusion == 'success' && github.event.workflow_run.event == 'push' && github.event.workflow_run.head_branch == 'main'"
    ordered = steps(release, "release")
    named = named_steps(release, "release")
    initial_current = "steps.main-identity.outputs.current == 'true'"
    release_candidate = "steps.merged-pr.outputs.release_commit == 'true' && steps.main-identity.outputs.release_eligible == 'true'"
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

    provenance = named["Find merged Release PR"]
    source = provenance["run"]
    contains_all(
        source,
        (
            'gh pr list --repo "$GITHUB_REPOSITORY" --state merged --base main --label "autorelease: pending" --limit 200 --json number',
            'test "$pending_count" -le 1',
            'gh api "repos/$GITHUB_REPOSITORY/pulls/$release_pr_number"',
            'release_sha="$(jq -r \'.merge_commit_sha\' <<< "$pr_json")"',
            'gh api "repos/$GITHUB_REPOSITORY/commits/$release_sha/pulls"',
            ".merge_commit_sha == $sha",
            'test "$(jq length <<< "$matches")" = "1"',
            'test "$(jq -r \'.user.login\' <<< "$pr_json")" = "github-actions[bot]"',
            'parent_count="$(git rev-list --parents -n 1 "$release_sha"',
            'test "$parent_count" = 1',
            'git diff --name-only "$release_sha^1" "$release_sha"',
            'test "$actual_release_files" = "$expected_release_files"',
            'git show "$release_sha:version.txt"',
            'expected_title="chore(main): release $version"',
            'test "$title" = "$expected_title"',
            'git merge-base --is-ancestor "$release_sha" "$VALIDATED_SHA"',
            "release_sha=%s",
            "release_commit=%s",
        ),
    )
    assert_regular_files(source, '"$release_sha"')

    ancestry = named["Verify release candidate ancestry"]
    contains_all(
        ancestry["run"],
        (
            'current_sha="$(git ls-remote --refs origin refs/heads/main | cut -f1)"',
            'test -n "$current_sha"',
            'if [ "$current_sha" = "$VALIDATED_SHA" ]',
            'git fetch --no-tags origin "$current_sha"',
            'git merge-base --is-ancestor "$RELEASE_SHA" "$current_sha"',
            'release_eligible=true',
            'printf \'current=%s\\nrelease_eligible=%s\\n\'',
        ),
    )
    assert_release_candidate_fixtures(source)
    assert_release_ancestry_fixtures(ancestry["run"])

    checkout = named["Check out validated release commit"]
    assert checkout["if"] == release_candidate
    contains_all(checkout["run"], ('git checkout --detach "$RELEASE_SHA"', 'test "$(git rev-parse HEAD)" = "$RELEASE_SHA"'))

    release_state = named["Inspect merged release state"]
    contains_all(
        release_state["run"],
        (
            "--release-notes",
            "git/ref/tags/$tag",
            "'.object.type'",
            "'.object.sha'",
            'test "$target" = "$RELEASE_SHA"',
            'test "$tag_target" = "$RELEASE_SHA"',
            'test "$name" = "$tag"',
            'test "$body" = "$expected_notes"',
            'test "$draft" = false',
            'test "$prerelease" = false',
        ),
    )

    exclusive = named["Verify exclusive publish candidate"]
    assert exclusive["if"] == release_candidate + " && steps.merged-pr.outputs.pending == 'true'"
    contains_all(
        exclusive["run"],
        (
            'git merge-base --is-ancestor "$RELEASE_SHA" "$current_sha"',
            "--state merged",
            "--base main",
            '--label "autorelease: pending"',
            "--limit 200",
            'test "$(jq length <<< "$pending_prs")" = 1',
            'test "$(jq -r \'.[0].number\' <<< "$pending_prs")" = "$RELEASE_PR_NUMBER"',
        ),
    )

    canonical = named["Canonicalize merged Release PR body"]
    assert canonical["if"] == release_candidate + " && steps.merged-pr.outputs.pending == 'true' && steps.release-state.outputs.exists != 'true'"
    assert canonical["run"].count('git merge-base --is-ancestor "$RELEASE_SHA" "$current_sha"') >= 2
    contains_all(canonical["run"], ("--render-pr-body", "--method PATCH", 'test "$actual_body" = "$expected_body"'))

    preconditions = named["Verify publish preconditions"]
    assert preconditions["if"] == canonical["if"]
    contains_all(
        preconditions["run"],
        (
            'git merge-base --is-ancestor "$RELEASE_SHA" "$current_sha"',
            "'.merged_at'",
            "'.merge_commit_sha'",
            'test "$(jq -r \'.merge_commit_sha\' <<< "$pr_json")" = "$RELEASE_SHA"',
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

    published = named["Verify published release identity"]
    assert published["if"] == "steps.publish.outcome == 'success'"
    contains_all(
        published["run"],
        (
            'test "$RELEASE_CREATED" = true',
            'test "$PUBLISHED_SHA" = "$RELEASE_SHA"',
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
    assert tagged["if"] == release_candidate + " && steps.release-state.outputs.exists == 'true'"
    contains_all(
        tagged["run"],
        (
            "--release-notes",
            "git/ref/tags/$tag",
            'test "$(jq -r \'.target_commitish\' <<< "$release_json")" = "$RELEASE_SHA"',
            'select(. == "autorelease: pending")',
            'select(. == "autorelease: tagged")',
        ),
    )

    maintenance = named["Recheck current main for maintenance"]
    assert maintenance["if"] == initial_current
    contains_all(maintenance["run"], ('current_sha="$(git ls-remote --refs origin refs/heads/main | cut -f1)"', 'if [ "$current_sha" = "$VALIDATED_SHA" ]'))

    maintain = named["Maintain Release PR"]
    assert maintain["uses"] == RELEASE_PLEASE_ACTION
    assert maintain["if"] == maintenance_current
    assert_release_please_invocation_agreement(publish, maintain, config)

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
            'test "$base_sha" = "$VALIDATED_SHA"',
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
            'git diff --name-only "$VALIDATED_SHA...HEAD"',
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
    assert writer_source.count('test "$current_sha" = "$VALIDATED_SHA"') >= 2
    assert writer_source.count('test "$remote_candidate_sha" = "$candidate_sha"') >= 2
    assert writer_source.count('test "$pr_head_sha" = "$candidate_sha"') >= 2
    assert writer_source.index("--write") < writer_source.index('git push origin')
    assert writer_source.index('git push origin') < writer_source.index("--render-pr-body")
    assert writer_source.index("--render-pr-body") < writer_source.index("--method PATCH")
    assert writer_source.index("--method PATCH") < writer_source.rindex("--check")
    assert "python3 scripts/release-context" not in writer_source

    order = {step["name"]: i for i, step in enumerate(ordered) if "name" in step}
    assert order["Find merged Release PR"] < order["Verify release candidate ancestry"]
    assert order["Verify release candidate ancestry"] < order["Check out validated release commit"]
    assert order["Check out validated release commit"] < order["Inspect merged release state"]
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
    config = assert_release_config(root)
    assert_release_context(root)
    assert_release_author_identity()
    assert_ci(ci)
    assert_release_workflow(release, release_text, config)
    assert_immutable_actions(ci, release)


if __name__ == "__main__":
    main()
