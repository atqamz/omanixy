#!/usr/bin/env python3
import json
import subprocess
import sys
import tempfile
from pathlib import Path


OMARCHY_REVISION = "f0020448ca87329199de7cb12f2015ebc4a3e5e7"
QUICKSHELL_REVISION = "28771c7c74b42e20afca0b1b63980cb46515537c"
NIXPKGS_REVISION = "241313f4e8e508cb9b13278c2b0fa25b9ca27163"
MATRIX = """items:
  - id: exact
    classification: exact
    maturity: validated
  - id: adapted
    classification: adapted
    maturity: validated
  - id: security.lock
    classification: adapted
    support: experimental
    maturity: audited
  - id: omitted
    classification: omitted
    maturity: validated
  - id: blocked
    classification: blocked
    maturity: audited
"""
OMARCHY = f"""project: basecamp/omarchy
track: quattro
revision: {OMARCHY_REVISION}
policy:
  runtime_pair:
    status: validated
    omarchy:
      revision: {OMARCHY_REVISION}
    quickshell:
      revision: {QUICKSHELL_REVISION}
      nixpkgs:
        revision: {NIXPKGS_REVISION}
  validated_quattro_pair: true
"""
CHANGELOG = """# Changelog

## 0.1.0

### Features

- add feature

### Bug Fixes

- fix bug

### Migration

None.
"""
PR_HEADER = ":robot: I have created a release *beep* *boop*"
PR_FOOTER = (
    "This PR was generated with [Release Please](https://github.com/googleapis/release-please). "
    "See [documentation](https://github.com/googleapis/release-please#release-please)."
)


def write(path, content):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8")


def run_tool(tool, root, mode):
    return subprocess.run(
        [sys.executable, str(tool), mode],
        cwd=root,
        text=True,
        capture_output=True,
        check=False,
    )


def assert_ok(result):
    assert result.returncode == 0, result.stdout + result.stderr


def assert_failed(result):
    assert result.returncode != 0


def make_repo(tmp_path, tool, version="0.1.0", changelog=CHANGELOG):
    root = tmp_path / "repo"
    write(root / "upstream/omarchy.yaml", OMARCHY)
    write(root / "upstream/porting-matrix.yaml", MATRIX)
    write(root / ".release-please-manifest.json", json.dumps({".": version}) + "\n")
    write(root / "version.txt", version + "\n")
    write(root / "CHANGELOG.md", changelog)
    return root


def make_release_only_repo(tmp_path, version="0.1.0", changelog=CHANGELOG):
    root = tmp_path / "repo"
    write(root / ".release-please-manifest.json", json.dumps({".": version}) + "\n")
    write(root / "version.txt", version + "\n")
    write(root / "CHANGELOG.md", changelog)
    return root


def test_bootstrap_check(tool):
    with tempfile.TemporaryDirectory() as temp:
        root = make_repo(Path(temp), tool, version="0.0.0", changelog="# Changelog\n")
        assert_ok(run_tool(tool, root, "--check"))
        assert_failed(run_tool(tool, root, "--release-notes"))
        assert_failed(run_tool(tool, root, "--render-pr-body"))


def test_write_and_check_render_exact_context(tool):
    with tempfile.TemporaryDirectory() as temp:
        root = make_repo(Path(temp), tool)
        assert_ok(run_tool(tool, root, "--write"))
        content = (root / "CHANGELOG.md").read_text(encoding="utf-8")
        assert OMARCHY_REVISION in content
        assert QUICKSHELL_REVISION in content
        assert "exact: 1" in content
        assert "adapted: 2" in content
        assert "omitted: 1" in content
        assert "blocked: 1" in content
        assert "experimental: 1" in content
        assert (
            "https://github.com/atqamz/omanixy/blob/v0.1.0/upstream/porting-matrix.yaml"
            in content
        )
        assert content.count("### Upstream\n") == 1
        assert content.count("### Compatibility\n") == 1
        assert_ok(run_tool(tool, root, "--check"))


def test_release_renderers_are_canonical_and_upstream_independent(tool):
    with tempfile.TemporaryDirectory() as temp:
        root = make_release_only_repo(Path(temp))
        notes = run_tool(tool, root, "--release-notes")
        assert_ok(notes)
        expected_notes = CHANGELOG.split("## 0.1.0", 1)[1]
        expected_notes = "## 0.1.0" + expected_notes
        expected_notes = expected_notes.strip()
        assert notes.stdout == expected_notes + "\n"

        body = run_tool(tool, root, "--render-pr-body")
        assert_ok(body)
        expected_body = f"{PR_HEADER}\n---\n\n\n{expected_notes}\n\n---\n{PR_FOOTER}\n"
        assert body.stdout == expected_body


def test_write_repairs_duplicates_and_is_idempotent(tool):
    duplicate = CHANGELOG.replace(
        "### Features\n",
        "### Upstream\n\nold upstream\n\n### Upstream\n\nolder upstream\n\n### Features\n",
    ).replace(
        "### Bug Fixes\n",
        "### Compatibility\n\nold compatibility\n\n### Compatibility\n\nolder compatibility\n\n### Bug Fixes\n",
    )
    with tempfile.TemporaryDirectory() as temp:
        root = make_repo(Path(temp), tool, changelog=duplicate)
        assert_ok(run_tool(tool, root, "--write"))
        first = (root / "CHANGELOG.md").read_bytes()
        assert_ok(run_tool(tool, root, "--write"))
        second = (root / "CHANGELOG.md").read_bytes()
        assert first == second
        assert first.count(b"### Upstream\n") == 1
        assert first.count(b"### Compatibility\n") == 1
        assert b"- add feature" in first
        assert b"- fix bug" in first


def test_malformed_omarchy_fails_closed(tool):
    with tempfile.TemporaryDirectory() as temp:
        root = make_repo(Path(temp), tool)
        write(root / "upstream/omarchy.yaml", "[")
        assert_failed(run_tool(tool, root, "--check"))


def test_missing_runtime_pair_fails_closed(tool):
    with tempfile.TemporaryDirectory() as temp:
        root = make_repo(Path(temp), tool)
        write(root / "upstream/omarchy.yaml", "project: basecamp/omarchy\nrevision: " + OMARCHY_REVISION + "\n")
        assert_failed(run_tool(tool, root, "--check"))


def test_malformed_matrix_fails_closed(tool):
    with tempfile.TemporaryDirectory() as temp:
        root = make_repo(Path(temp), tool)
        write(root / "upstream/porting-matrix.yaml", "items: invalid\n")
        assert_failed(run_tool(tool, root, "--check"))


def test_breaking_candidate_requires_migration(tool):
    breaking = CHANGELOG.replace("### Migration\n\nNone.", "### BREAKING CHANGES\n\n- break the public contract\n\n### Migration\n\nNone.")
    with tempfile.TemporaryDirectory() as temp:
        root = make_repo(Path(temp), tool, changelog=breaking)
        assert_ok(run_tool(tool, root, "--write"))
        assert_failed(run_tool(tool, root, "--check"))
        write(
            root / "CHANGELOG.md",
            (root / "CHANGELOG.md").read_text(encoding="utf-8").replace(
                "### Migration\n\nNone.",
                "### Migration\n\nUpdate programs.omanixy.shell.config to the new shape.",
            ),
        )
        assert_ok(run_tool(tool, root, "--check"))


def test_nonbreaking_none_migration_passes(tool):
    with tempfile.TemporaryDirectory() as temp:
        root = make_repo(Path(temp), tool)
        assert_ok(run_tool(tool, root, "--write"))
        assert_ok(run_tool(tool, root, "--check"))


def test_linked_release_heading_passes(tool):
    changelog = CHANGELOG.replace(
        "## 0.1.0",
        "## [0.1.0](https://github.com/atqamz/omanixy/releases/tag/v0.1.0) (2026-08-23)",
    )
    with tempfile.TemporaryDirectory() as temp:
        root = make_repo(Path(temp), tool, changelog=changelog)
        assert_ok(run_tool(tool, root, "--write"))
        assert_ok(run_tool(tool, root, "--check"))
        notes = run_tool(tool, root, "--release-notes")
        assert_ok(notes)
        assert notes.stdout.startswith("## [0.1.0](https://github.com/atqamz/omanixy/releases/tag/v0.1.0)")


def test_version_heading_mismatch_fails(tool):
    with tempfile.TemporaryDirectory() as temp:
        root = make_repo(Path(temp), tool, changelog=CHANGELOG.replace("## 0.1.0", "## 0.2.0"))
        assert_failed(run_tool(tool, root, "--check"))
        assert_failed(run_tool(tool, root, "--release-notes"))
        assert_failed(run_tool(tool, root, "--render-pr-body"))


def test_manifest_version_mismatch_fails(tool):
    with tempfile.TemporaryDirectory() as temp:
        root = make_repo(Path(temp), tool)
        write(root / ".release-please-manifest.json", '{".": "0.2.0"}\n')
        assert_failed(run_tool(tool, root, "--check"))
        assert_failed(run_tool(tool, root, "--release-notes"))


def test_invalid_semver_fails_closed(tool):
    invalid_versions = (
        "01.2.3",
        "1.02.3",
        "1.2.03",
        "1.2.3-01",
        "1.2.3-alpha.01",
        "1.2.3-",
    )
    for version in invalid_versions:
        with tempfile.TemporaryDirectory() as temp:
            root = make_repo(Path(temp), tool, version=version)
            assert_failed(run_tool(tool, root, "--check"))
            assert_failed(run_tool(tool, root, "--release-notes"))
            assert_failed(run_tool(tool, root, "--render-pr-body"))


def main():
    tool = Path(sys.argv[1]).resolve()
    tests = [
        test_bootstrap_check,
        test_write_and_check_render_exact_context,
        test_release_renderers_are_canonical_and_upstream_independent,
        test_write_repairs_duplicates_and_is_idempotent,
        test_malformed_omarchy_fails_closed,
        test_missing_runtime_pair_fails_closed,
        test_malformed_matrix_fails_closed,
        test_breaking_candidate_requires_migration,
        test_nonbreaking_none_migration_passes,
        test_linked_release_heading_passes,
        test_version_heading_mismatch_fails,
        test_manifest_version_mismatch_fails,
        test_invalid_semver_fails_closed,
    ]
    failures = []
    for test in tests:
        try:
            test(tool)
        except Exception as error:
            failures.append(f"{test.__name__}: {error}")
    if failures:
        raise SystemExit("\n".join(failures))


if __name__ == "__main__":
    main()
