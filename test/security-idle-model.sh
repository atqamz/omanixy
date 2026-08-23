#!/usr/bin/env bash
set -euo pipefail

model_file=$1

node - "$model_file" <<'NODE'
const path = process.argv[2]
const model = require(path)

function expect(actual, expected, description) {
  const a = JSON.stringify(actual)
  const e = JSON.stringify(expected)
  if (a !== e) {
    throw new Error(`${description}: expected ${e}, got ${a}`)
  }
}

expect(typeof model.secondsFromConfig, "function", "secondsFromConfig is exported")
expect(model.eventParts, undefined, "eventParts must not be exported")
expect(model.screensaverWindowsAfter, undefined, "screensaverWindowsAfter must not be exported")
expect(Object.keys(model), ["secondsFromConfig"], "module.exports surface must be exactly secondsFromConfig")

const fallback = 300
expect(model.secondsFromConfig(300, fallback), 300, "300 -> 300")
expect(model.secondsFromConfig(10.9, fallback), 10, "10.9 -> 10 (floor)")
expect(model.secondsFromConfig(1, fallback), 1, "1 -> 1")
expect(model.secondsFromConfig(0, fallback), 300, "0 -> fallback (not immediate lock)")
expect(model.secondsFromConfig(-1, fallback), 300, "-1 -> fallback")
expect(model.secondsFromConfig("bad", fallback), 300, "'bad' -> fallback")
expect(model.secondsFromConfig(Infinity, fallback), 300, "Infinity -> fallback")
expect(model.secondsFromConfig(-Infinity, fallback), 300, "-Infinity -> fallback")
expect(model.secondsFromConfig(NaN, fallback), 300, "NaN -> fallback")
expect(model.secondsFromConfig(null, fallback), 300, "null -> fallback")
expect(model.secondsFromConfig(undefined, fallback), 300, "undefined -> fallback")
expect(model.secondsFromConfig("", fallback), 300, "'' -> fallback (Number('') is 0)")
expect(model.secondsFromConfig("42", fallback), 42, "numeric string '42' -> 42")
expect(model.secondsFromConfig(0.5, fallback), 300, "0.5 -> fallback (floors to 0, must not become a near-immediate lock)")

// Pinned Quickshell converts this value through static_cast<int>(timeout *
// 1000) before the quint32 cast (src/wayland/idle_notify/monitor.cpp) -
// 2147483 (floor(INT_MAX / 1000)) is the largest whole-second value that
// stays representable there. This upper bound is derived from that pinned
// backend's own arithmetic range, not an Omanixy policy preference.
expect(model.secondsFromConfig(2147483, fallback), 2147483, "2147483 -> 2147483 (backend boundary)")
expect(model.secondsFromConfig(2147483.9, fallback), 2147483, "2147483.9 -> 2147483 (floors within boundary)")
expect(model.secondsFromConfig(2147484, fallback), 300, "2147484 -> fallback (one second past the backend boundary)")
expect(model.secondsFromConfig(3000000, fallback), 300, "3000000 -> fallback (well past the backend boundary)")
expect(model.secondsFromConfig("2147484", fallback), 300, "'2147484' -> fallback")
expect(model.secondsFromConfig(Number.MAX_SAFE_INTEGER, fallback), 300, "Number.MAX_SAFE_INTEGER -> fallback")

console.log("security-idle-model: all IdleModel.js behavior assertions passed")
NODE
