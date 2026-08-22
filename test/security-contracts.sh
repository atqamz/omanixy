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
    promoted = (
        item["classification"] == item["target"]["classification"]
        and item["support"] == item["target"]["support"]
    )
    if promoted:
        assert item.get("promoted_at_layer") is not None
        # Layer 8 (Section 6): required_before_promotion is a gate on
        # reaching the declared target, not a permanent to-do list. Once an
        # entry has reached its target classification/support, that gate is
        # satisfied and must be empty or absent - remaining hardware- or
        # environment-specific evidence for a hypothetical future move to
        # "supported" belongs under required_before_supported instead.
        assert not item["evidence"].get("required_before_promotion")
    else:
        assert "promoted_at_layer" not in item
        assert item["evidence"]["required_before_promotion"]

promoted_ids = {item["id"] for item in security if "promoted_at_layer" in item}
assert promoted_ids == {
    "security.pam-password",
    "security.lock",
    "security.pam-fingerprint",
    "security.polkit-agent",
    "security.idle",
    "security.notification-daemon",
    "security.recovery",
}

security_recovery = next(item for item in security if item["id"] == "security.recovery")
assert security_recovery["classification"] == "adapted"
assert security_recovery["support"] == "experimental"
assert security_recovery["target"] == {"classification": "adapted", "support": "experimental"}
assert security_recovery["promoted_at_layer"] == "8/8"

# Section 60: an entry may still carry required_before_supported once
# promoted - that vocabulary names real hardware/environment breadth still
# outstanding for a hypothetical future move to "supported", never a reason
# to withhold promotion to "experimental", and it must never be silently
# reported as passed evidence.
for item in security:
    if "required_before_supported" in item["evidence"]:
        assert isinstance(item["evidence"]["required_before_supported"], list)
        assert item["evidence"]["required_before_supported"]

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

idle = next(item for item in security if item["id"] == "security.idle")
assert idle["classification"] == "adapted"
assert idle["support"] == "experimental"
assert idle["target"] == {"classification": "adapted", "support": "experimental"}
assert idle["promoted_at_layer"] == "6/8"

notification_client = next(item for item in items if item["id"] == "notification.client")
notification_daemon = next(item for item in security if item["id"] == "security.notification-daemon")
assert notification_client["helper"] == "omarchy-notification-send"
assert "org.freedesktop.Notifications" not in notification_client.get("dbus_services", [])
assert "org.freedesktop.Notifications" in notification_daemon["dbus_services"]
assert notification_client["id"] != notification_daemon["id"]
assert notification_daemon["classification"] == "adapted"
assert notification_daemon["support"] == "experimental"
assert notification_daemon["target"] == {"classification": "adapted", "support": "experimental"}
assert notification_daemon["promoted_at_layer"] == "7/8"

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

if rg -n 'services\.(hypridle|swayidle)\.enable\s*=\s*(false|true)' \
  "$repo/modules/home"; then
  printf '%s\n' 'Omanixy must not imperatively set a competing idle daemon service' >&2
  exit 1
fi
if rg -n 'systemctl.*(hypridle|swayidle)|kill.*(hypridle|swayidle)|pkill.*(hypridle|swayidle)' \
  "$repo/modules" "$repo/packages" "$repo/scripts"; then
  printf '%s\n' 'Omanixy must not stop or kill a competing idle daemon' >&2
  exit 1
fi

if rg -n 'omarchy-launch-screensaver|omarchy-screensaver|\bttfx\b|\bsocat\b' \
  "$repo/modules/home"; then
  printf '%s\n' 'screensaver vocabulary leaked into the Home Manager module - Layer 6 deliberately omits it' >&2
  exit 1
fi

if rg -n 'omarchy-system-sleep-monitor|omarchy-sleep-lock\.service|systemd-inhibit|omarchy-system-lock\b' \
  "$repo/modules/home"; then
  printf '%s\n' 'sleep/suspend-monitor vocabulary leaked into the Home Manager module - intentionally omitted, consumer-owned suspend policy' >&2
  exit 1
fi

if rg -n 'services\.(mako|dunst|swaync|fnott)\.enable\s*=\s*(false|true)' \
  "$repo/modules/home"; then
  printf '%s\n' 'Omanixy must not imperatively set a competing notification daemon service' >&2
  exit 1
fi
if rg -n 'systemctl.*(mako|dunst|swaync|fnott)|kill.*(mako|dunst|swaync|fnott)|pkill.*(mako|dunst|swaync|fnott)' \
  "$repo/modules" "$repo/packages" "$repo/scripts"; then
  printf '%s\n' 'Omanixy must not stop or kill a competing notification daemon' >&2
  exit 1
fi

if rg -n 'omarchy-hyprland-focus-app' \
  "$repo/modules" "$repo/packages"; then
  printf '%s\n' 'the compositor-focus fallback is intentionally omitted from the native notification daemon' >&2
  exit 1
fi

printf '%s\n' 'security contract checks passed'
