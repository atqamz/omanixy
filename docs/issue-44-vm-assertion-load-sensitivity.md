# Issue 44: VM assertion load sensitivity

## Result

The study used fixed baseline `e7465a26ce014a3e7c4df9ca54045653b2459821` and `N=10` valid runs for each condition and assertion.
The notification assertion passed `10/10` in the controlled contended arm and `10/10` in the quiet arm, with `history_count=10` and `popup_count=0` in every valid run.
The polkit assertion passed `10/10` in the controlled contended arm and `10/10` in the quiet arm, with `exit=0`, `prompt=yes`, and the expected event sequence in every valid run.
The original unchanged-source high-contention notification run still failed with `history_count=11` and `popup_count=45`, so the evidence supports a load-correlated notification failure under heavier contention than the controlled arm reproduced.
No production notification, PAM, or polkit behavior was changed.
The root flake check now serializes local derivation builds with `nix --option max-jobs 1 flake check --show-trace --print-build-logs`.

## Method

The test source and fixture remained unchanged apart from measurement output and the polkit harness telemetry needed to expose the assertion result.
The controlled contended arm launched the target VM while peer VM and Nix activity was present, and the quiet arm launched only the target VM after confirming no host QEMU or Nix process at run start.
Each record captured the three load averages as one-minute, five-minute, and fifteen-minute values.
Each record captured host QEMU and Nix counts at start, assertion, target end, and peer or final end when that phase existed.
The notification records also captured target and peer VM counts at the assertion window.
The polkit records captured target and peer VM counts at the assertion window and the target VM duration.

The host process count and the per-role VM counts are corroborating views and must not be added together.
One early notification record printed `assertion_observed_qemu_count=6` by summing overlapping views, but the actual host count was three QEMU processes with one target and two peers, so that derived value is ignored.
Polkit target output is buffered by the Nix VM runner and often reports `target_log_vm_count=0` after the target has already exited.
For that assertion, a host QEMU count of two and peer VM count of two establish the overlap even when the target log count is zero.

## Reclassification audit

The contended population was audited by start and assertion counts before calculating the result.
An end count of zero after the target and peers exited is expected cleanup and is not by itself evidence that a run was quiet.
Runs with zero peer evidence at the assertion window were excluded from the contended population and redone.
This dead-peer reclassification is itself a finding about how this suite must be measured.

| Record | Start counts and load | Assertion or end evidence | Classification |
| --- | --- | --- | --- |
| Original exploratory notification failure | load `13.38,11.28,5.81`, host QEMU `4`, Nix `4` | `history_count=11`, `popup_count=45`, exit `1`; no accepted same-suite end telemetry | Exploratory high-contention failure, excluded from the controlled `N=10` population |
| Original exploratory polkit run 1 | load `23.45,18.20,10.66`, host QEMU `2`, Nix `4` | Parser sequence blank; no accepted end telemetry | Exploratory high-contention record, excluded |
| Original exploratory polkit run 2 | load `14.54,17.21,16.05`, host QEMU `0`, Nix `4` | No accepted peer-overlap assertion or end telemetry | Incomplete contended record, excluded |
| Original exploratory polkit run 3 | load `9.75,11.31,13.66`, host QEMU `0`, peer VM `1`, Nix `3` | Old wrapper record did not provide an accepted assertion population | Incomplete contended record, excluded |
| Original exploratory polkit runs 4-10 | Start telemetry missing | End records reported host QEMU `0`, peer VM `0`, and Nix `0` | Quiet or incomplete records wearing a contended label, excluded |
| Controlled polkit run 3 | load `5.29,4.41,3.56`, host QEMU `0`, Nix `0` | Assertion host QEMU `0`, target VM `0`, peer VM `0`; target and peer ended with QEMU `0`, Nix `0` | Invalid dead-peer run, excluded and redone |
| Controlled polkit run 4 | load `5.98,5.04,4.13`, host QEMU `0`, Nix `0` | Assertion host QEMU `0`, target VM `0`, peer VM `0`; target and peer ended with QEMU `0`, Nix `0` | Invalid dead-peer run, excluded and redone |
| Controlled polkit run 3 redo 1 | Triggered with peer wait `200` | The peer completed its `88.63` second test before the target assertion; assertion host QEMU `0`, peer VM `0` | Invalid dead-peer run, excluded and redone with peer wait `320` |

The final controlled contended polkit population is original runs `1`, `2`, and `5-10`, plus redo 2 for runs `3` and `4`.
The user-reported zero end counts for the old polkit runs were therefore not averaged into the contended result.

## Controlled contended notifications

Every row below is valid and has `history_count=10`, `popup_count=0`, assertion target VM count `1`, assertion peer VM count `2`, and target exit `0`.
The `q/n` notation means host QEMU count and host Nix count.
The target-end and peer-end columns are separate observations from the target and peer cleanup points.

| Run | Start load, q/n | Assertion load, q/n | Target VM / peer VM | Target end load, q/n | Peer end load, q/n |
| --- | --- | --- | --- | --- | --- |
| 1 | `2.69,4.11,6.62`, `0/1` | `3.92,4.12,6.44`, `3/2` | `1/2` | `3.78,4.08,6.40`, `2/1` | `3.12,3.88,6.22`, `0/0` |
| 2 | `6.31,4.51,6.21`, `0/1` | `7.22,5.31,6.34`, `3/3` | `1/2` | `6.96,5.29,6.32`, `2/2` | `4.65,4.90,6.15`, `0/1` |
| 3 | `4.65,4.90,6.15`, `0/1` | `5.85,5.09,6.10`, `3/3` | `1/2` | `5.78,5.09,6.10`, `2/2` | `4.56,4.86,5.97`, `0/1` |
| 4 | `4.56,4.86,5.97`, `0/1` | `4.62,4.76,5.83`, `3/3` | `1/2` | `4.54,4.74,5.81`, `2/2` | `3.62,4.48,5.68`, `0/1` |
| 5 | `3.62,4.48,5.68`, `0/1` | `3.90,4.38,5.55`, `3/3` | `1/2` | `3.99,4.39,5.55`, `2/2` | `2.94,4.07,5.38`, `0/0` |
| 6 | `2.94,4.07,5.38`, `0/0` | `2.92,3.82,5.20`, `3/2` | `1/2` | `3.09,3.84,5.20`, `2/1` | `2.39,3.52,5.02`, `0/0` |
| 7 | `2.39,3.52,5.02`, `0/0` | `2.79,3.36,4.85`, `3/2` | `1/2` | `2.72,3.34,4.83`, `2/1` | `2.12,3.07,4.66`, `0/0` |
| 8 | `2.12,3.07,4.66`, `0/0` | `3.10,3.14,4.56`, `3/2` | `1/2` | `3.01,3.12,4.54`, `2/1` | `2.59,2.97,4.42`, `0/0` |
| 9 | `2.59,2.97,4.42`, `0/0` | `2.72,2.93,4.30`, `3/2` | `1/2` | `2.46,2.86,4.27`, `2/1` | `2.16,2.73,4.15`, `0/0` |
| 10 | `2.16,2.73,4.15`, `0/0` | `3.22,2.92,4.11`, `3/2` | `1/2` | `3.05,2.89,4.10`, `2/1` | `2.28,2.71,3.97`, `0/0` |

The controlled contention reached an assertion load of up to `7.22,5.31,6.34`, but it did not reproduce the original failure.

## Controlled contended polkit

Every row below is valid and has `exit=0`, `prompt=yes`, and the expected sequence.
The assertion target log count is zero in these records because of output buffering, while the host and peer counts show the target and peer overlap.

The expected sequence is `isRegisteredChanged true;isActiveChanged true;authenticationRequestStarted;isResponseRequiredChanged true prompt=;authenticationRequestStarted;isResponseRequiredChanged true prompt=;isResponseRequiredChanged false prompt=Password: ;isActiveChanged false;authenticationSucceeded`.

| Run | Source | Start load, q/n | Assertion load, q/n | Target VM / peer VM | Target end load, q/n | Peer end load, q/n |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | Original timed | `2.23,2.32,3.27`, `0/0` | `2.64,3.01,3.29`, `2/2` | `0/2` | `2.64,3.01,3.29`, `2/2` | `2.25,2.42,2.97`, `0/0` |
| 2 | Original timed | `1.70,2.20,2.83`, `0/0` | `3.52,2.90,2.89`, `2/1` | `0/2` | `3.52,2.90,2.89`, `2/1` | `3.56,2.92,2.89`, `0/0` |
| 3 | Redo 2, peer wait `320` | `1.79,1.50,1.02`, `0/0` | `1.27,1.53,1.22`, `2/1` | `0/2` | `1.27,1.53,1.22`, `2/1` | `1.06,1.43,1.20`, `0/0` |
| 4 | Redo 2, peer wait `320` | `0.58,1.24,1.15`, `0/0` | `1.31,1.10,1.09`, `2/1` | `0/2` | `1.31,1.10,1.09`, `2/1` | `1.06,1.07,1.08`, `0/0` |
| 5 | Original timed | `5.98,5.04,4.13`, `0/0` | `2.10,3.14,3.59`, `3/2` | `0/2` | `2.34,3.18,3.59`, `2/1` | `1.90,2.55,3.26`, `0/0` |
| 6 | Original timed | `1.90,2.55,3.26`, `0/0` | `2.32,2.87,3.20`, `2/1` | `0/2` | `2.32,2.87,3.20`, `2/1` | `1.60,2.19,2.86`, `0/0` |
| 7 | Original timed | `1.60,2.19,2.86`, `0/0` | `2.28,2.23,2.66`, `2/1` | `0/2` | `2.28,2.23,2.66`, `2/1` | `1.48,1.96,2.47`, `0/0` |
| 8 | Original timed | `1.48,1.96,2.47`, `0/0` | `2.60,2.18,2.37`, `2/2` | `0/2` | `2.60,2.18,2.37`, `2/1` | `2.60,2.18,2.37`, `0/0` |
| 9 | Original timed | `2.60,2.18,2.37`, `0/0` | `2.42,2.62,2.53`, `2/1` | `0/2` | `2.42,2.62,2.53`, `2/1` | `2.42,2.62,2.53`, `0/0` |
| 10 | Original timed | `2.42,2.62,2.53`, `0/0` | `1.80,1.90,2.21`, `2/1` | `0/2` | `1.80,1.90,2.21`, `2/1` | `1.84,1.90,2.21`, `0/0` |

## Quiet notifications

Every row below started with host QEMU `0` and Nix `0`, passed with `history_count=10` and `popup_count=0`, and ended with host QEMU `0` and Nix `0`.
The assertion target VM count was `1` in every row.

| Run | Start load | Assertion load | Assertion q/n | End load | Result |
| --- | --- | --- | --- | --- | --- |
| 1 | `0.42,0.80,0.97` | `1.45,1.04,1.04` | `1/1` | `1.41,1.04,1.04` | `history=10,popup=0,exit=0` |
| 2 | `1.41,1.04,1.04` | `1.24,1.05,1.04` | `1/1` | `1.30,1.06,1.05` | `history=10,popup=0,exit=0` |
| 3 | `1.30,1.06,1.05` | `1.35,1.11,1.07` | `1/1` | `1.24,1.09,1.06` | `history=10,popup=0,exit=0` |
| 4 | `1.24,1.09,1.06` | `1.26,1.11,1.07` | `1/1` | `1.22,1.11,1.07` | `history=10,popup=0,exit=0` |
| 5 | `1.22,1.11,1.07` | `1.12,1.09,1.06` | `1/1` | `1.03,1.07,1.06` | `history=10,popup=0,exit=0` |
| 6 | `1.03,1.07,1.06` | `1.04,1.06,1.06` | `1/1` | `0.96,1.04,1.05` | `history=10,popup=0,exit=0` |
| 7 | `0.96,1.04,1.05` | `1.15,1.08,1.06` | `1/1` | `1.05,1.06,1.06` | `history=10,popup=0,exit=0` |
| 8 | `1.05,1.06,1.06` | `1.92,1.26,1.12` | `1/1` | `1.84,1.26,1.12` | `history=10,popup=0,exit=0` |
| 9 | `1.84,1.26,1.12` | `2.16,1.48,1.21` | `1/1` | `2.14,1.49,1.21` | `history=10,popup=0,exit=0` |
| 10 | `2.14,1.49,1.21` | `1.80,1.47,1.22` | `1/1` | `1.65,1.45,1.22` | `history=10,popup=0,exit=0` |

## Quiet polkit

Every row below started with host QEMU `0` and Nix `0`, passed with `exit=0`, `prompt=yes`, and the expected sequence, and ended with host QEMU `0` and Nix `0`.
The target log count was zero at assertion in every row because of output buffering.

| Run | Start load | Assertion load | Assertion q/n | End load | Result |
| --- | --- | --- | --- | --- | --- |
| 1 | `0.83,1.24,1.16` | `0.75,0.87,1.01` | `0/0` | `0.75,0.87,1.01` | `exit=0,prompt=yes` |
| 2 | `0.75,0.87,1.01` | `2.14,1.75,1.36` | `0/0` | `2.14,1.75,1.36` | `exit=0,prompt=yes` |
| 3 | `2.14,1.75,1.36` | `1.81,1.82,1.52` | `0/0` | `1.81,1.82,1.52` | `exit=0,prompt=yes` |
| 4 | `1.81,1.82,1.52` | `2.27,2.13,1.76` | `0/0` | `2.27,2.13,1.76` | `exit=0,prompt=yes` |
| 5 | `2.27,2.13,1.76` | `1.68,2.04,1.85` | `0/0` | `1.68,2.04,1.85` | `exit=0,prompt=yes` |
| 6 | `1.68,2.04,1.85` | `1.73,1.91,1.85` | `0/1` | `1.73,1.91,1.85` | `exit=0,prompt=yes` |
| 7 | `1.73,1.91,1.85` | `2.17,1.91,1.85` | `0/1` | `2.17,1.91,1.85` | `exit=0,prompt=yes` |
| 8 | `2.17,1.91,1.85` | `4.06,3.31,2.48` | `1/1` | `4.06,3.31,2.48` | `exit=0,prompt=yes` |
| 9 | `4.06,3.31,2.48` | `6.64,5.52,3.75` | `0/0` | `6.64,5.52,3.75` | `exit=0,prompt=yes` |
| 10 | `6.64,5.52,3.75` | `4.69,6.53,5.00` | `0/0` | `4.69,6.53,5.00` | `exit=0,prompt=yes` |

## Changes and limits

The VM assertions now emit machine-readable `MEASURE` lines for the bounded notification history and same-harness polkit reprompt sequence.
The measurement check validates those output contracts and validates that the root `just check` command preserves build logs while setting `max-jobs=1`.
The serialization is a harness-side safeguard for load-sensitive derivation checks and does not alter production behavior.

The controlled contention was materially lighter than the original exploratory failure, and `N=10` cannot exclude a rare intermittent failure.
The original exploratory records are retained as evidence but are not treated as valid condition samples when their start or assertion overlap telemetry is missing.
No separate production defect was reproduced for polkit, so this task does not create a new polkit issue.

The conclusion is that notification checks require serialized local flake evaluation because the unchanged source has failed under extreme host contention, while the valid controlled and quiet samples did not distinguish notification outcomes by load.
The polkit assertion showed no load-sensitive failure in the valid `N=10` samples after dead-peer records were removed and replaced.
