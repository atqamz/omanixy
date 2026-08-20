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
    promoted = (
        item["classification"] == item["target"]["classification"]
        and item["support"] == item["target"]["support"]
    )
    if promoted:
        assert item.get("promoted_at_layer") is not None
    else:
        assert "promoted_at_layer" not in item

promoted_ids = {item["id"] for item in security if "promoted_at_layer" in item}
assert promoted_ids == {
    "security.pam-password",
    "security.lock",
    "security.pam-fingerprint",
    "security.polkit-agent",
}

lock = next(item for item in security if item["id"] == "security.lock")
assert lock["classification"] == "adapted"
assert lock["support"] == "experimental"
assert lock["target"] == {"classification": "adapted", "support": "experimental"}
assert lock["promoted_at_layer"] == "3/8"

pam_fingerprint = next(item for item in security if item["id"] == "security.pam-fingerprint")
assert pam_fingerprint["classification"] == "adapted"
assert pam_fingerprint["support"] == "experimental"
assert pam_fingerprint["target"] == {"classification": "adapted", "support": "experimental"}
assert pam_fingerprint["promoted_at_layer"] == "4/8"

polkit_agent = next(item for item in security if item["id"] == "security.polkit-agent")
assert polkit_agent["classification"] == "adapted"
assert polkit_agent["support"] == "experimental"
assert polkit_agent["target"] == {"classification": "adapted", "support": "experimental"}
assert polkit_agent["promoted_at_layer"] == "5/8"

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

# Layers 2 and 4 own every declarative PAM capability, in exactly one place:
# the NixOS security module. Home Manager and the runtime package must never
# declare a PAM service themselves - only reference the fingerprint readiness
# adapter's helper name, which is not a PAM declaration. Layer 5 owns
# security.polkit (the native NixOS capability only, never a PAM service of
# its own); idle and notification daemon ownership remain out of scope until
# their own stack layers.
if rg -n 'security\.pam\.services|/etc/pam\.d/omarchy-lock-(password|fingerprint)\b|pam_fprintd|pam_unix' \
  "$repo/modules/home" "$repo/packages"; then
  printf '%s\n' 'PAM declaration found outside the layer-2/4 NixOS security module' >&2
  exit 1
fi

if rg -n 'security\.pam\.services|/etc/pam\.d/omarchy-lock-(password|fingerprint)\b|pam_fprintd|pam_unix' \
  "$repo/modules/nixos" | rg -v 'modules/nixos/default\.nix'; then
  printf '%s\n' 'PAM declaration found outside the layer-2/4 NixOS security module file' >&2
  exit 1
fi

if rg -n 'IdleMonitor|NotificationServer|org\.freedesktop\.Notifications' \
  "$repo/modules/nixos"; then
  printf '%s\n' 'idle/notification ownership is out of scope for the layer-2/5 security modules' >&2
  exit 1
fi

# Layer 5 (polkit) must never imperatively mutate a known-conflicting
# session polkit agent - it may only assert against one being enabled
# alongside the Quattro agent, never set, stop, or kill it.
if rg -n 'services\.(hyprpolkitagent|polkit-gnome)\.enable\s*=\s*(false|true)' \
  "$repo/modules/home"; then
  printf '%s\n' 'Omanixy must not imperatively set a competing polkit agent service' >&2
  exit 1
fi
if rg -n 'systemctl.*(hyprpolkitagent|polkit-gnome)|kill.*(hyprpolkitagent|polkit-gnome)' \
  "$repo/modules" "$repo/packages" "$repo/scripts"; then
  printf '%s\n' 'Omanixy must not stop or kill a competing polkit agent' >&2
  exit 1
fi

if rg -n 'programs\.omanixy\.features.*(lock|polkit|idle|notifications)|features.*omarchy\.(lock|polkit|idle|notifications)' \
  "$repo/modules"; then
  printf '%s\n' 'security ownership was added to the presentation feature model' >&2
  exit 1
fi

printf '%s\n' 'security contract checks passed'
