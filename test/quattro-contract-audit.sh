#!/usr/bin/env bash
set -euo pipefail

repo=${1:?repository path required}
scanner="$repo/scripts/audit-quattro-contracts"
python=${PYTHON:-python3}
snapshot="$repo/upstream/quattro-contracts.json"
fixture=$(mktemp -d)
output=$(mktemp)
repeat=$(mktemp)
trap 'rm -rf "$fixture" "$output" "$repeat"' EXIT

run_scan() {
  "$python" "$scanner" "$1"
}

mkdir -p "$fixture/shell/services" "$fixture/shell/plugins/lock" "$fixture/shell/plugins/polkit" \
  "$fixture/shell/plugins/services/idle" "$fixture/shell/plugins/notifications" \
  "$fixture/default/omarchy" "$fixture/config/omarchy" "$fixture/bin"
absolute_path=\$OMARCHY_PATH
{
  printf '%s\n' 'Process { command: ["omarchy-fixture-helper", "--verbose"] }'
  printf '%s\n' "Process { command: [\"${absolute_path}/bin/omarchy-fixture-absolute\"] }"
} > "$fixture/shell/services/Fixture.qml"
{
  printf '%s\n' 'Quickshell.execDetached(["fixture-tool", "arg"]); Util.execDetached(dynamicCommand);'
  printf '%s\n' 'Process { command: dynamicCondition ? ["omarchy-dynamic-helper"] : ["dynamic-external"] }'
  printf '%s\n' 'Util.exec(dynamicCommand); Process { command: ["bash", "-c", dynamicShell] }'
  printf '%s\n' 'Process { command: ["bash", "-lc", dynamicLoginShell] }'
  printf '%s\n' 'root.bar.run("omarchy-bar-helper --flag")'
} > "$fixture/shell/services/Dynamic.qml"
printf '%s\n' 'FileView { path: Quickshell.env("XDG_STATE_HOME") + "/omarchy/fixture.json"; watchChanges: true }' > "$fixture/shell/services/State.qml"
printf '%s\n' "Process { command: [\"env-tool\", \"\$CUSTOM_RUNTIME_VARIABLE\"] }" >> "$fixture/shell/services/State.qml"
printf '%s\n' 'FileView { path: Quickshell.env("lowercase_runtime_variable") }' >> "$fixture/shell/services/State.qml"
printf '%s\n' 'import Quickshell.Networking' 'import Quickshell.Services.Mpris' '/etc/pam.d/fixture; /etc/fixture.conf; org.freedesktop.Fixture' > "$fixture/shell/services/Native.qml"
printf '%s\n' '{"fixture": {"action": "omarchy-menu-helper --flag", "when": "fixture-guard", "checked": "fixture-check", "provider": "fixture-provider"}}' > "$fixture/default/omarchy/omarchy-menu.jsonc"
printf '%s\n' 'omarchy-unreachable' > "$fixture/bin/omarchy-unreachable"
printf '%s\n' 'Process { command: ["omarchy-security-fixture"] }' > "$fixture/shell/plugins/lock/Service.qml"
printf '%s\n' 'Item { }' > "$fixture/shell/plugins/notifications/Card.qml"
{
  printf '%s\n' '#!/usr/bin/env bash'
  printf '%s\n' 'mystery-security-tool --probe'
} > "$fixture/shell/plugins/lock/probe.sh"

run_scan "$fixture" > "$output"
run_scan "$fixture" > "$repeat"
cmp "$output" "$repeat"

jq -e '.direct_omarchy_helpers | map(.name) | index("omarchy-fixture-helper") != null' "$output" >/dev/null
jq -e '.direct_shell_commands | map(.name) | index("omarchy-bar-helper") != null' "$output" >/dev/null
jq -e '.external_executables | map(.name) | index("fixture-tool") != null' "$output" >/dev/null
jq -e '.absolute_helper_paths | map(.name) | index("omarchy-unreachable") == null' "$output" >/dev/null
jq -e '.absolute_helper_paths | map(.name) | index("omarchy-fixture-absolute") != null' "$output" >/dev/null
jq -e '.dynamic_commands | length == 5' "$output" >/dev/null
jq -e '.direct_omarchy_helpers | map(.name) | index("omarchy-dynamic-helper") != null' "$output" >/dev/null
jq -e '.external_executables | map(.name) | index("dynamic-external") != null' "$output" >/dev/null
jq -e '.menu_commands | map(.field) | sort == ["action", "checked", "provider", "when"]' "$output" >/dev/null
jq -e '.security_contracts | map(.name) | index("/etc/pam.d/fixture") != null' "$output" >/dev/null
jq -e '.filesystem_contracts | map(.name) | index("/etc/fixture.conf") != null' "$output" >/dev/null
jq -e '.native_quickshell_modules | sort == ["Quickshell.Networking", "Quickshell.Services.Mpris"]' "$output" >/dev/null
jq -e '.environment_variables | index("CUSTOM_RUNTIME_VARIABLE") != null' "$output" >/dev/null
jq -e '.environment_variables | index("lowercase_runtime_variable") != null' "$output" >/dev/null
jq -e '.schema == 3' "$output" >/dev/null

# Finding 1: a security source with no hand-added filename entry is discovered
# purely by living under a declared root, and carries a content hash.
jq -e '.security_source_files | any(.[]; .path == "shell/plugins/lock/Service.qml" and .present == true and (.hash | length == 64))' "$output" >/dev/null
jq -e '.security_source_files | any(.[]; .path == "shell/plugins/notifications/Card.qml")' "$output" >/dev/null

# Finding 2: an unrecognized bash executable is discovered without any
# predeclared executable name list.
jq -e '.security_external_executables | map(.name) | index("mystery-security-tool") != null' "$output" >/dev/null

# Finding 3: an unknown helper edge is recorded unresolved (disposition null)
# rather than silently skipped, and stays terminal until dispositioned.
jq -e '.security_helper_edges[] | select(.name == "omarchy-security-fixture") | .disposition == null and .present == false' "$output" >/dev/null
jq -e '.security_helpers | map(.name) | index("omarchy-security-fixture") != null' "$output" >/dev/null

service_hash=$(jq -r '.security_source_files[] | select(.path == "shell/plugins/lock/Service.qml") | .hash' "$output")

if cmp "$output" "$snapshot" >/dev/null 2>&1; then
  printf '%s\n' 'fixture unexpectedly matched the pinned snapshot' >&2
  exit 1
fi

cp "$output" "$repeat"
{
  printf '%s\n' 'Process { command: ["omarchy-new-helper", "new-external"] }'
  printf '%s\n' 'Process { command: ["new-external"] }'
  printf '%s\n' '/etc/pam.d/new-service; org.freedesktop.NewService'
  printf '%s\n' "Quickshell.execDetached([\"${absolute_path}/bin/omarchy-new-absolute\"])"
} > "$fixture/shell/services/Drift.qml"
printf '%s\n' 'Process { command: ["omarchy-security-new"] }' >> "$fixture/shell/plugins/lock/Service.qml"
printf '%s\n' '/etc/pam.d/new-security-service; WlSessionLock; org.freedesktop.NewSecurityService' >> "$fixture/shell/plugins/lock/Service.qml"
sed -i 's/}}$/},"drift":{"action":"omarchy-menu-new"}}/' "$fixture/default/omarchy/omarchy-menu.jsonc"
printf '%s\n' 'omarchy-security-fixture-child --flag' > "$fixture/bin/omarchy-security-fixture"
if cmp "$repeat" <(run_scan "$fixture") >/dev/null 2>&1; then
  printf '%s\n' 'new contracts did not change the audit snapshot' >&2
  exit 1
fi
drifted=$(run_scan "$fixture")
jq -e '.direct_omarchy_helpers | map(.name) | index("omarchy-new-helper") != null' <<<"$drifted" >/dev/null
jq -e '.external_executables | map(.name) | index("new-external") != null' <<<"$drifted" >/dev/null
jq -e '.absolute_helper_paths | map(.name) | index("omarchy-new-absolute") != null' <<<"$drifted" >/dev/null
jq -e '.security_contracts | map(.name) | index("/etc/pam.d/new-service") != null' <<<"$drifted" >/dev/null
jq -e '.service_contracts | map(.name) | index("org.freedesktop.NewService") != null' <<<"$drifted" >/dev/null
jq -e '.security_contracts | map(.name) | index("/etc/pam.d/new-security-service") != null' <<<"$drifted" >/dev/null
jq -e '.security_contracts | map(.name) | index("WlSessionLock") != null' <<<"$drifted" >/dev/null
jq -e '.service_contracts | map(.name) | index("org.freedesktop.NewSecurityService") != null' <<<"$drifted" >/dev/null
jq -e '.security_helpers | map(.name) | index("omarchy-security-new") != null' <<<"$drifted" >/dev/null

# Finding 1 (modification): editing a security source changes its hash.
new_service_hash=$(jq -r '.security_source_files[] | select(.path == "shell/plugins/lock/Service.qml") | .hash' <<<"$drifted")
if [ "$service_hash" = "$new_service_hash" ]; then
  printf '%s\n' 'editing a security source did not change its hash' >&2
  exit 1
fi

# Finding 3 (closure): an unresolved edge stays terminal even once its file
# exists and itself references a further omarchy-* name - one omitted or
# unresolved edge never pulls in the rest of a bin tree.
jq -e '.security_helper_edges[] | select(.name == "omarchy-security-fixture") | .disposition == null and .present == true' <<<"$drifted" >/dev/null
jq -e '.security_helper_edges | map(.name) | index("omarchy-security-fixture-child") == null' <<<"$drifted" >/dev/null

printf '%s\n' 'quattro contract audit tests passed'
