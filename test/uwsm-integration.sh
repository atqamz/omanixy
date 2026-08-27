#!/usr/bin/env bash
set -euo pipefail

runtime=${1:?runtime package path required}
compatibility_root=${2:?compatibility root path required}
quickshell=${3:?selected Quickshell executable required}
runtime_path=$(sed -n 's/^export PATH="\(.*\)"$/\1/p' "$runtime/bin/omanixy-shell-runtime")
test -n "$runtime_path"

uwsm=$(PATH="$runtime_path" command -v uwsm)
test -n "$uwsm"
case "$uwsm" in
  /nix/store/*-uwsm-*/bin/uwsm) ;;
  *) printf 'selected UWSM executable is not the packaged binary: %s\n' "$uwsm" >&2; exit 1 ;;
esac
uwsm_help_status=0
uwsm_help=$(PATH="$runtime_path" uwsm app --help 2>&1) || uwsm_help_status=$?
if ((uwsm_help_status == 0)); then
  grep -Fq 'usage: uwsm app' <<<"$uwsm_help"
else
  grep -Fq 'DBUS_SESSION_BUS_ADDRESS' <<<"$uwsm_help"
fi

support="$compatibility_root/shell/services/AppLibrarySupport.js"
app_library="$compatibility_root/shell/services/AppLibrary.qml"
node - "$support" <<'NODE'
const support = require(process.argv[2]);

if (support.semanticDesktopId(" org.telegram.desktop ") !== " org.telegram.desktop ") {
  throw new Error("semantic desktop id was mutated");
}
if (support.normalizeDesktopId(" org.example.User.desktop ") !== "org.example.User") {
  throw new Error("legacy hide/config normalization drifted");
}
if (support.desktopFileId("org.telegram.desktop.desktop") !== "org.telegram.desktop") {
  throw new Error("desktop filename was not converted to its semantic id");
}
const ownedSuffix = { "org.telegram.desktop": true };
if (!support.canRemove("org.telegram.desktop", ownedSuffix) || !support.canRemove("org.telegram.desktop.desktop", ownedSuffix) || support.canRemove("org.telegram", ownedSuffix)) {
  throw new Error("launcher deletion ownership confused a semantic .desktop suffix with a filename suffix");
}
if (support.launchCommand("org.example.User") !== "uwsm app -- gtk-launch 'org.example.User.desktop'") {
  throw new Error("unexpected direct UWSM command for ordinary desktop id");
}
if (support.launchCommand("org.telegram.desktop") !== "uwsm app -- gtk-launch 'org.telegram.desktop.desktop'") {
  throw new Error("semantic id ending in .desktop was truncated before gtk-launch");
}
if (support.launchCommand("Example App") !== "uwsm app -- gtk-launch 'Example App.desktop'") {
  throw new Error("desktop id containing a space was not preserved");
}
if (support.launchCommand("bad;id") !== "uwsm app -- gtk-launch 'bad;id.desktop'") {
  throw new Error("shell metacharacter was not contained as one quoted desktop id argument");
}
if (support.launchCommand("odd'id") !== "uwsm app -- gtk-launch 'odd'\\''id.desktop'") {
  throw new Error("single quote was not escaped as one desktop id argument");
}
if (support.launchCommand("") !== "") {
  throw new Error("empty desktop id produced a launch command");
}

const exact = { appId: "org.example.User", title: "irrelevant" };
if (support.matchingToplevels({ id: "org.example.User", startupClass: "" }, [exact]).length !== 1 || support.matchingToplevels({ id: "org.example.User", startupClass: "" }, [exact])[0] !== exact) {
  throw new Error("desktop id did not exactly match appId");
}

const startup = { appId: "ExampleStartup", title: "irrelevant" };
const startupMatches = support.matchingToplevels({ id: "org.example.User", startupClass: "ExampleStartup" }, [startup]);
if (startupMatches.length !== 1 || startupMatches[0] !== startup) {
  throw new Error("StartupWMClass did not exactly match appId");
}

const suffixId = { appId: "org.telegram.desktop", title: "irrelevant" };
const suffixMatches = support.matchingToplevels({ id: "org.telegram.desktop", startupClass: "" }, [suffixId]);
if (suffixMatches.length !== 1 || suffixMatches[0] !== suffixId) {
  throw new Error("semantic desktop suffix was not preserved for toplevel matching");
}
if (support.matchingToplevels({ id: "org.telegram.desktop", startupClass: "" }, [{ appId: "org.telegram" }]).length !== 0) {
  throw new Error("semantic .desktop suffix was incorrectly stripped during matching");
}

const folded = { appId: "org.example.case", title: "irrelevant" };
const foldedMatches = support.matchingToplevels({ id: "Org.Example.Case", startupClass: "" }, [folded]);
if (foldedMatches.length !== 1 || foldedMatches[0] !== folded) {
  throw new Error("unique case-normalized identity did not match");
}

const exactPreferred = { appId: "Org.Example.Case", title: "irrelevant" };
const preferredMatches = support.matchingToplevels({ id: "Org.Example.Case", startupClass: "" }, [folded, exactPreferred]);
if (preferredMatches.length !== 1 || preferredMatches[0] !== exactPreferred) {
  throw new Error("exact identity did not outrank case-normalized identity");
}

const duplicateA = { appId: "org.example.Duplicate", title: "first" };
const duplicateB = { appId: "org.example.Duplicate", title: "second" };
const duplicateEntry = { id: "org.example.Duplicate", startupClass: "" };
if (support.matchingToplevels(duplicateEntry, [duplicateA, duplicateB]).length !== 2) {
  throw new Error("matching set lost a valid multi-window application");
}

const titleOnly = { appId: "org.example.Other", title: "org.example.User" };
if (support.matchingToplevels({ id: "org.example.User", startupClass: "" }, [titleOnly]).length !== 0) {
  throw new Error("window title incorrectly participated in application identity");
}

if (support.matchingToplevels({ id: "org.example.User", startupClass: "" }, []).length !== 0) {
  throw new Error("empty toplevel set produced a match");
}

const entry = { id: "org.example.User", startupClass: "" };
const unrelated = { appId: "org.example.Other", title: "irrelevant" };
const launchedA = { appId: "org.example.User", title: "new-a" };
const launchedB = { appId: "org.example.User", title: "new-b" };
if (!support.coldLaunchSucceeded(entry, [launchedA], [], unrelated, unrelated)) {
  throw new Error("new matching toplevel did not complete cold-launch feedback");
}
if (!support.coldLaunchSucceeded(entry, [launchedA, launchedB], [], unrelated, unrelated)) {
  throw new Error("multi-window cold launch incorrectly required a unique toplevel");
}
if (support.coldLaunchSucceeded(entry, [launchedA, launchedB], [launchedA, launchedB], unrelated, unrelated)) {
  throw new Error("pre-existing matching toplevels falsely completed cold-launch feedback");
}
if (!support.coldLaunchSucceeded(entry, [launchedA, launchedB], [launchedA, launchedB], unrelated, launchedB)) {
  throw new Error("single-instance handoff focus did not complete cold-launch feedback");
}
if (support.coldLaunchSucceeded(entry, [unrelated], [], unrelated, unrelated)) {
  throw new Error("unrelated toplevel incorrectly completed cold-launch feedback");
}

const activationTarget = { appId: "org.example.User", activated: false };
if (!support.activationSucceeded(activationTarget, activationTarget)) {
  throw new Error("active target did not complete activation feedback");
}
if (!support.activationSucceeded({ appId: "org.example.User", activated: true }, unrelated)) {
  throw new Error("activated target property did not complete activation feedback");
}
if (support.activationSucceeded(activationTarget, unrelated)) {
  throw new Error("unfocused target incorrectly completed activation feedback");
}
NODE

grep -Fq 'var id = AppLibrarySupport.semanticDesktopId(desktopId)' "$app_library"
grep -Fq 'var entry = DesktopEntries.byId(id)' "$app_library"
grep -Fq 'if (!entry) return' "$app_library"
grep -Fq 'id = AppLibrarySupport.semanticDesktopId(entry.id)' "$app_library"
grep -Fq 'AppLibrarySupport.matchingToplevels(entry, ToplevelManager.toplevels.values || [])' "$app_library"
grep -Fq 'toplevel.activate()' "$app_library"
grep -Fq 'AppLibrarySupport.activationSucceeded(root.launchTargetToplevel, active)' "$app_library"
grep -Fq 'AppLibrarySupport.coldLaunchSucceeded(' "$app_library"
grep -Fq 'root.launchInitialMatches' "$app_library"
grep -Fq 'AppLibrarySupport.desktopFileId(lines[i])' "$app_library"
launch_feedback=$(sed -n '/function beginLaunchFeedback/,/launchTimeout.restart()/p' "$app_library")
grep -Fq 'Quickshell.execDetached(["omarchy-shell", "osd", "close"])' <<<"$launch_feedback"
grep -Fq 'root.launchOsdOpen = false' <<<"$launch_feedback"
grep -Fq 'uwsm app -- gtk-launch ' "$support"
if grep -Fq 'uwsm-app -- gtk-launch' "$app_library" "$support"; then
  printf '%s\n' 'built launcher still depends on uwsm-app daemon path' >&2
  exit 1
fi

if [[ ${OMANIXY_LIVE_UWSM:-0} != 1 ]]; then
  printf '%s\n' 'LIVE_UWSM_UNCLAIMED: optional live smoke was not requested'
  exit 0
fi

test_root=$(mktemp -d)
trap 'rm -rf "$test_root"' EXIT
fixture_bin="$test_root/bin"
data_home="$test_root/data"
runtime_dir="$test_root/runtime"
config_root="$test_root/config"
mkdir -p "$fixture_bin" "$data_home/applications" "$runtime_dir" "$config_root"
ln -s "$compatibility_root/shell" "$test_root/qs"
ln -s "$compatibility_root/shell/Commons" "$config_root/Commons"
ln -s "$compatibility_root/shell/services" "$config_root/services"
cat > "$fixture_bin/gtk-launch" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" > "$LAUNCH_LOG"
EOF
chmod +x "$fixture_bin/gtk-launch"
sed -i "1c#!$(command -v bash)" "$fixture_bin/gtk-launch"
cat > "$data_home/applications/org.example.User.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Omanixy test app
Exec=$fixture_bin/gtk-launch
EOF
cat > "$fixture_bin/systemctl" <<'EOF'
#!/usr/bin/env bash
case "$*" in
  *show-environment*) printf 'PATH=%s\n' "$FIXTURE_PATH" ;;
  *) exit 0 ;;
esac
EOF
chmod +x "$fixture_bin/systemctl"
sed -i "1c#!$(command -v bash)" "$fixture_bin/systemctl"
for utility in sleep flock notify-send; do
  printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "$fixture_bin/$utility"
  chmod +x "$fixture_bin/$utility"
  sed -i "1c#!$(command -v bash)" "$fixture_bin/$utility"
done

cat > "$config_root/shell.qml" <<'EOF'
import QtQuick
import Quickshell
import Quickshell.Io

Loader {
  source: Quickshell.env("OMANIXY_APP_LIBRARY")
  property bool launched: false
  property int attempts: 0
  onLoaded: {
    if (item) item.launch("org.example.User", "Omanixy test app")
    launched = true
  }
  Timer {
    interval: 100
    running: true
    repeat: true
    onTriggered: {
      attempts++
      if (launched && attempts >= 20) Qt.quit()
    }
  }
}
EOF
launch_status=0
LAUNCH_LOG="$test_root/launch.log" \
  XDG_DATA_HOME="$data_home" \
  XDG_RUNTIME_DIR="$runtime_dir" \
  QT_QPA_PLATFORM=offscreen \
  OMANIXY_APP_LIBRARY="$config_root/services/AppLibrary.qml" \
  OMARCHY_PATH="$compatibility_root" \
  LAUNCH_LOG="$test_root/launch.log" \
  FIXTURE_PATH="$fixture_bin:$runtime_path" \
  PATH="$fixture_bin:$runtime_path" \
  timeout 10s "$quickshell" -n -p "$config_root" || launch_status=$?
if ((launch_status == 124)); then
  printf '%s\n' 'live AppLibrary/direct-UWSM launch timed out' >&2
  exit 1
fi
for _ in {1..20}; do
  test -f "$test_root/launch.log" && break
  sleep 0.1
done
if test -f "$test_root/launch.log"; then
  grep -Fxq 'org.example.User.desktop' "$test_root/launch.log"
else
  printf '%s\n' 'real AppLibrary/direct-UWSM launch produced no evidence' >&2
  exit 1
fi

printf '%s\n' 'LIVE_SMOKE_CLAIMED: real direct UWSM launch recorder observed the desktop id'
