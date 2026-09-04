#!/usr/bin/env python3
import json
from pathlib import Path

root = Path(__file__).resolve().parent.parent
tuple_data = json.loads((root / "upstream/compatibility-tuple.json").read_text())
lock = json.loads((root / "flake.lock").read_text())
legacy = json.loads((root / "upstream/compatibility-contracts.json").read_text())
omarchy_yaml = (root / "upstream/omarchy.yaml").read_text()
flake_nix = (root / "flake.nix").read_text()

expected = {
    "omarchy": tuple_data["omarchy"]["revision"],
    "quickshell": tuple_data["quickshell"]["revision"],
    "nixpkgs": tuple_data["nixpkgs"]["revision"],
    "home-manager": tuple_data["homeManager"]["revision"],
}

assert tuple_data["releaseLine"] == "0.3.x"
assert tuple_data["status"] == "frozen"

for node, revision in expected.items():
    assert lock["nodes"][node]["locked"]["rev"] == revision, node

for node in ("omarchy", "quickshell", "nixpkgs"):
    assert legacy["pins"][node] == expected[node], node
    assert expected[node] in omarchy_yaml, node

assert f'github:basecamp/omarchy/{expected["omarchy"]}' in flake_nix
assert f'github:quickshell-mirror/quickshell/{expected["quickshell"]}' in flake_nix
assert f'github:nix-community/home-manager/{expected["home-manager"]}' in flake_nix

candidate = tuple_data["reviewedCandidate"]
assert candidate["decision"] == "retain-current-validated-tuple"
assert candidate["omarchyQuattroHead"] != expected["omarchy"]
assert candidate["omarchyCommitsAhead"] > 0
assert candidate["quickshellReleaseRevision"] != expected["quickshell"]
