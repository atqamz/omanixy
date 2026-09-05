#!/usr/bin/env bash
set -euo pipefail

repo=${1:?repository path required}

${PYTHON:-python3} - "$repo/upstream/omarchy.yaml" <<'PY'
import sys
import yaml

data = yaml.safe_load(open(sys.argv[1], encoding="utf-8"))
assert data["policy"]["runtime_pair"]["status"] == "validated"
assert data["policy"]["runtime_pair"]["validation"]["wayland_hyprland_smoke"] is False
assert data["track"] == "quattro"
PY
jq -e '
  .schema >= 2
  and (.pins.omarchy | type) == "string"
  and (.pins.quickshell | type) == "string"
  and (.pins.nixpkgs | type) == "string"
  and (.helpers | type) == "object"
' "$repo/upstream/compatibility-contracts.json" >/dev/null

schema=$repo/upstream/host-contract.schema.json
registry=$repo/upstream/host-contract.json

jq -e '
  ."$schema" == "https://json-schema.org/draft/2020-12/schema"
  and (."$defs".crossingKind.enum == [
    "native-api",
    "host-contract",
    "declarative-host-integration",
    "state-contract",
    "trusted-extension",
    "distribution-policy",
    "internal-provider-seam"
  ])
  and (."$defs".hostContractCapability.properties.executionClass.enum == [
    "query",
    "mutation",
    "interactive"
  ])
  and (."$defs".hostContractCapability.properties.privilegeModel.enum == [
    "unprivileged",
    "authorized-runtime-api"
  ])
  and (."$defs".supportState.enum == [
    "supported",
    "experimental",
    "omitted",
    "blocked",
    "not-applicable"
  ])
  and (."$defs".hostContractCapability.required | index("capabilityId") != null)
  and (."$defs".hostContractCapability.required | index("canonicalRoute") != null)
  and (."$defs".hostContractCapability.required | index("flatBackingBinary") != null)
  and (."$defs".hostContractCapability.required | index("exitContract") != null)
  and (."$defs".crossing.required | index("kind") != null)
  and (."$defs".crossing.required | index("transport") != null)
  and (."$defs".crossing.required | index("disposition") != null)
  and (."$defs".crossing.required | index("supportState") != null)
  and (."$defs".crossing.required | index("capabilityId") != null)
' "$schema" >/dev/null

jq -e '
  .documentType == "host-contract"
  and .schemaVersion == 1
  and .capabilityIdRule == "semanticDomain.operation"
  and .registryState == "schema-only"
  and (.capabilities | type) == "array"
  and all(.capabilities[]; .capabilityId == (.semanticDomain + "." + .operation))
  and (([.capabilities[].capabilityId] | length) == ([.capabilities[].capabilityId] | unique | length))
' "$registry" >/dev/null

test -s "$repo/LICENSE"

printf '%s\n' 'stale text checks passed'
