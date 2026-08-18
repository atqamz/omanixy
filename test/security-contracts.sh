#!/usr/bin/env bash
set -euo pipefail

repo=${1:?repository path required}
compatibility_root=${2:?compatibility root path required}
matrix=$repo/upstream/porting-matrix.yaml
metadata=$repo/upstream/omarchy.yaml
baseline=$repo/upstream/shell-baseline.json
snapshot=$repo/upstream/quattro-contracts.json

python=${PYTHON:-python3}
"$python" - "$matrix" "$metadata" "$snapshot" <<'PY'
import json
import sys
import yaml

data = yaml.safe_load(open(sys.argv[1], encoding="utf-8"))
metadata = yaml.safe_load(open(sys.argv[2], encoding="utf-8"))
snapshot = json.load(open(sys.argv[3], encoding="utf-8"))
items = data["items"]
security = [item for item in items if item["id"].startswith("security.")]
assert {item["id"] for item in security} == {
    "security.lock",
    "security.pam-password",
    "security.pam-fingerprint",
    "security.polkit-agent",
    "security.idle",
    "security.notification-daemon",
    "security.recovery",
}
classifications = {"exact", "adapted", "omitted", "blocked"}
support_states = {"supported", "experimental", "omitted", "blocked"}
for item in security:
    assert item["classification"] in classifications
    assert item["support"] in support_states
    assert item["maturity"] == "audited"
    assert item["audit_layer"] == "1/8"
    assert item["target"]["classification"] in classifications
    assert item["target"]["support"] in support_states
    assert item["evidence"]["available"]
    assert item["evidence"]["required_before_promotion"]
    assert item["classification"] != item["target"]["classification"] or item["support"] != item["target"]["support"]

lock = next(item for item in security if item["id"] == "security.lock")
assert lock["classification"] == "blocked"
assert lock["support"] == "blocked"
assert lock["target"] == {"classification": "adapted", "support": "experimental"}

notification_client = next(item for item in items if item["id"] == "notification.client")
notification_daemon = next(item for item in security if item["id"] == "security.notification-daemon")
assert notification_client["helper"] == "omarchy-notification-send"
assert "org.freedesktop.Notifications" not in notification_client.get("dbus_services", [])
assert "org.freedesktop.Notifications" in notification_daemon["dbus_services"]
assert notification_client["id"] != notification_daemon["id"]

support_states = metadata["policy"]["support_state_definition"]
assert set(support_states) == {"supported", "experimental", "omitted", "blocked"}
scope = metadata["contract_audit"]["security_scope"]
assert set(scope["source_roots"]) == set(snapshot["security_source_roots"])
snapshot_dispositions = {
    edge["path"]: edge["disposition"] for edge in snapshot["security_helper_edges"]
}
assert None not in snapshot_dispositions.values()
assert scope["helper_dispositions"] == snapshot_dispositions
PY

jq -e '
  (.featureCapabilities.notification == ["notification-send"])
  and (.disabledPlugins | index("omarchy.lock") != null)
  and (.disabledPlugins | index("omarchy.polkit") != null)
  and (.disabledPlugins | index("omarchy.idle") != null)
  and (.disabledPlugins | index("omarchy.notifications") != null)
' "$baseline" >/dev/null

jq -e '
  .schema == 4
  and (.security_source_files | all(.[]; .present == true))
  and (.security_helpers | map(.name) | index("omarchy-system-lock") != null)
  and (.security_helpers | map(.name) | index("omarchy-system-wake") != null)
  and (.security_contracts | map(.name) | index("WlSessionLock") != null)
  and (.security_contracts | map(.name) | index("/etc/pam.d/omarchy-lock-password") != null)
' "$snapshot" >/dev/null

# Section 5/7 case I: on the real pinned repo (not an arbitrary fixture) the
# closure is fully resolved and every dynamic/ambiguous execution has an
# exact, pinned, reviewed disposition - the pinned snapshot must actually
# reach the 0/0/0 state the audit exists to enforce, not merely be capable of
# reporting non-zero when something is wrong.
jq -e '
  ([.security_helper_edges[] | select(.disposition == null)] | length == 0)
  and (.security_dead_dispositions | length == 0)
  and (.security_unreviewed_dynamic_executions | length == 0)
  and (.security_dead_dynamic_execution_dispositions | length == 0)
' "$snapshot" >/dev/null

for plugin in lock polkit notifications; do
  test ! -e "$compatibility_root/shell/plugins/$plugin"
done
test ! -e "$compatibility_root/shell/plugins/services/idle"

if rg -n 'security\.pam\.services|/etc/pam\.d/omarchy-lock|omarchy-lock-(password|fingerprint)' \
  "$repo/modules" "$repo/packages"; then
  printf '%s\n' 'layer 1 contains a runtime PAM declaration' >&2
  exit 1
fi

if rg -n 'programs\.omanixy\.features.*(lock|polkit|idle|notifications)|features.*omarchy\.(lock|polkit|idle|notifications)' \
  "$repo/modules"; then
  printf '%s\n' 'security ownership was added to the presentation feature model' >&2
  exit 1
fi

printf '%s\n' 'security contract checks passed'
