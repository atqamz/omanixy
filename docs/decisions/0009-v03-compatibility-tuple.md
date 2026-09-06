# ADR 0009: Freeze the Omanixy 0.3 compatibility tuple

## Status

Accepted.

## Decision

Omanixy 0.3 keeps the currently validated immutable runtime tuple:

```text
Omarchy Quattro  f0020448ca87329199de7cb12f2015ebc4a3e5e7
Quickshell       28771c7c74b42e20afca0b1b63980cb46515537c
nixpkgs          241313f4e8e508cb9b13278c2b0fa25b9ca27163
Home Manager     3ee51fbdac8c8bdfe1e7e1fcaba6520a563f394f
```

This is an explicit freeze, not an assumption that the newest upstream revisions are compatible.

## Candidate review

The reviewed Omarchy `quattro` candidate was `f99d33a8ddee7b36509a71a6d20d5d23355ce8b1`. It is 270 commits ahead of the current reviewed revision. The range materially changes host-facing surfaces used by Omanixy, including the `omarchy` router, DNS/network/notification/monitor helpers, the default menu, and Quattro clipboard, tray, lock, notifications, audio, Bluetooth, network, power, monitor, weather, polkit, and shell code.

Taking that upstream move at the same time as the Host Contract normalization would combine two independent semantic changes and make crossing regressions harder to localize. The 0.3 Host Contract work therefore audits the known validated source graph first. A later explicit upstream-upgrade issue may review and adopt a newer Omarchy revision against the normalized contract.

Quickshell 0.3.1 was also reviewed as a candidate. Upstream Omarchy documents 0.3.1 as fixing synchronous instance termination and returning to the packaged Quickshell build. The currently pinned nixpkgs revision still packages Quickshell 0.3.0, so adopting 0.3.1 would still require an exact source override rather than simplifying Omanixy's packaging immediately. The existing reviewed Quickshell revision is retained for the same isolation reason.

nixpkgs and Home Manager remain at their current exact lock revisions. No mutable branch head becomes a release dependency.

## Packaging policy

The exact source-pinned Quickshell build remains the supported 0.3 implementation. Replacing it with `pkgs.quickshell` is allowed only after the nixpkgs package is mechanically proven to provide the reviewed exact source/version required by the frozen tuple.

Consumer overrides change the tested tuple. They remain advanced unsupported configurations unless the relevant Omanixy checks are rerun against the exact resolved graph.

## Consequences

- `upstream/compatibility-tuple.json` is the compact 0.3 tuple identity used by Host Contract evidence.
- Existing pin representations must agree mechanically with it.
- #27 audits this exact graph rather than mutable `quattro` or unstable branch heads.
- Upstream freshness is deliberately separated from Host Contract convergence.
