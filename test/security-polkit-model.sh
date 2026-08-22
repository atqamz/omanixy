#!/usr/bin/env bash
set -euo pipefail

policy_file=$1

node - "$policy_file" <<'NODE'
const path = process.argv[2]
const model = require(path)

function expect(actual, expected, description) {
  const a = JSON.stringify(actual)
  const e = JSON.stringify(expected)
  if (a !== e) {
    throw new Error(`${description}: expected ${e}, got ${a}`)
  }
}

expect(typeof model.authorizationLabel, "function", "authorizationLabel is exported")
expect(model.promptLooksFingerprint, undefined, "promptLooksFingerprint must not be exported")
expect(model.fingerprintConfiguredFromPamConfig, undefined, "fingerprintConfiguredFromPamConfig must not be exported")
expect(Object.keys(model), ["authorizationLabel"], "module.exports surface must be exactly authorizationLabel")

expect(
  model.authorizationLabel("Authentication is needed to run `/usr/bin/foo` as the super user"),
  "Authorize running '/usr/bin/foo'",
  "known 'needed to run' shape yields a concise authorization label"
)
expect(
  model.authorizationLabel("Authentication is required to run 'apt-get update' as root"),
  "Authorize running 'apt-get update'",
  "known 'required to run' shape (single quotes) yields a concise authorization label"
)
expect(
  model.authorizationLabel("System policy prevents this action without authentication"),
  "System policy prevents this action without authentication",
  "unknown/free-form message is preserved verbatim"
)
expect(model.authorizationLabel(""), "", "empty message is preserved verbatim")
expect(model.authorizationLabel(undefined), "", "undefined message coerces to empty string, not 'undefined'")

console.log("security-polkit-model: all PolkitModel.js behavior assertions passed")
NODE
