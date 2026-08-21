# Layer 8 (security-recovery) final, cross-cutting real-backend evidence for
# the security.recovery ledger entry's `recovery.cross-feature-boot` and
# `recovery.cross-feature-crash` rows (upstream/security-recovery-matrix.yaml),
# referenced by upstream/porting-matrix.yaml's security.recovery entry and by
# docs/decisions/0005-quattro-security-session-boundary.md's "Cross-feature
# boot and crash recovery" note.
#
# Every earlier layer-8 sibling (test/security-recovery-pam-vm.nix,
# test/security-recovery-polkit-vm.nix,
# test/security-recovery-notifications-vm.nix) proved its own surface in
# isolation. This file selects all three simultaneously -
# `programs.omanixy.security.pam.password.enable`,
# `programs.omanixy.security.polkit.system.enable` (NixOS) paired with
# `programs.omanixy.security.polkit.agent.enable` and
# `programs.omanixy.security.notifications.daemon.enable` (Home Manager) - in
# one booted NixOS VM, and proves the combination itself introduces no new
# failure mode: no extra PAM service, no extra polkit agent, no extra
# notification daemon spawned as a side effect of combining the three, and no
# cross-contamination when the process holding all three real objects is
# killed and restarted.
#
# Lock and idle are deliberately excluded, unchanged from the other layer-8
# VM tests: both require a live nested Wayland compositor this KVM/QEMU host
# cannot reach (see the ADR's "Nested-compositor environment limitation"
# section and upstream/security-recovery-matrix.yaml's
# `recovery.lock-nested-compositor`/`recovery.idle-nested-compositor` rows).
# Fingerprint hardware is naturally absent here too and is not exercised by
# this file; that no-device path is already covered live by
# test/security-recovery-pam-vm.nix's own scenario 5.
#
# The combined harness below deliberately mirrors how the real, production
# `omanixy-shell.service` would run all three in one process: a bare
# `PamContext` (never the production lock plugin's `WlSessionLock`-bound
# `Service.qml`, exactly like test/security-recovery-pam-vm.nix's own
# harness), a bare `PolkitAgent` at the real `/org/omarchy/PolkitAgent` path
# (never the production `PanelWindow`-bound `PolkitAgent.qml`, exactly like
# test/security-recovery-polkit-vm.nix's own harness), and the real,
# unmodified production `Service.qml`/`NotificationLogic.js` a
# notification-daemon-enabled build ships, loaded via `Loader` with only its
# `PanelWindow` mechanically swapped for a plain `Item` (no Wayland
# layer-shell surface, exactly like test/security-recovery-notifications-vm.nix
# already proved) - all three real Quickshell objects, in one real Quickshell
# process, on the exact same pinned `quickshell-omanixy` derivation production
# runs.
{ pkgs, self, home-manager }:
let
  lib = pkgs.lib;
  system = pkgs.stdenv.hostPlatform.system;

  testUser = "omanixy-recovery-test";
  testPassword = "omanixy-recovery-test-fixture-password";
  testActionId = "org.omanixy.test.security-recovery-cross-feature";

  # The notification-daemon-enabled runtime, extracted the same narrow way
  # test/security-recovery-notifications-vm.nix already does: only
  # `.config.home.packages` is read (cheap evaluation, no activation
  # package built), and only `programs.omanixy.security.notifications.daemon`
  # is turned on for this extraction - `security.polkit.agent` is
  # deliberately left off here because this harness never loads the
  # production, `PanelWindow`-bound `PolkitAgent.qml` the compat root would
  # otherwise carry (it uses the bare native type directly, exactly like
  # test/security-recovery-polkit-vm.nix), so there is nothing in the compat
  # root for that option to add that this file would ever read; enabling it
  # here would also require an `osConfig` this standalone extraction has none
  # of, for no benefit.
  notifHome = home-manager.lib.homeManagerConfiguration {
    pkgs = pkgs;
    modules = [
      self.homeManagerModules.default
      {
        home.username = "omanixy-crossfeature-fixture";
        home.homeDirectory = "/build/omanixy-crossfeature-fixture";
        home.stateVersion = "25.11";
        programs.omanixy.enable = true;
        programs.omanixy.security.notifications.daemon.enable = true;
      }
    ];
  };
  runtimePkg = lib.findFirst
    (p: (p.name or "") == "omanixy-shell")
    (throw "security-recovery-cross-feature-vm: omanixy-shell runtime package not found in home.packages")
    notifHome.config.home.packages;

  # The exact pinned quickshell-omanixy derivation production builds and
  # runs, reused as-is so the harness runs under the identical ABI/module set
  # production does - the same binary every layer-8 sibling reuses.
  quickshellBin = runtimePkg.passthru.quickshell;
  compatRoot = runtimePkg.passthru.omarchyCompatibilityRoot;
  notifStateBinDir = "${runtimePkg.passthru.compatibilityBin}/bin";

  # The identical mechanical PanelWindow -> Item substitution
  # test/security-recovery-notifications-vm.nix already proved: no Wayland
  # layer-shell surface is available or needed for D-Bus ownership/delivery,
  # and the real NotificationServer instantiation itself is left completely
  # untouched.
  #
  # The source Service.qml lives inside compatRoot, a derivation output -
  # reading it via builtins.readFile here would force Nix to build that
  # derivation during evaluation (import-from-derivation), which breaks
  # `nix flake check --no-build`. pkgs.runCommand defers the read/patch to
  # the build phase instead, mirroring
  # test/security-recovery-notifications-vm.nix's own fix for the identical
  # pattern.
  panelOld = "    PanelWindow {\n      id: popupWindow\n      required property var modelData\n      screen: modelData\n      visible: popupModel.count > 0\n\n      WlrLayershell.namespace: \"omarchy-notifications\"\n      WlrLayershell.layer: WlrLayer.Overlay\n      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None\n      exclusionMode: ExclusionMode.Ignore\n      color: \"transparent\"\n\n";
  panelNew = "    Item {\n      id: popupWindow\n      required property var modelData\n      visible: popupModel.count > 0\n\n";
  anchorsOld = "      anchors { top: true; bottom: true; left: true; right: true }\n\n";
  maskOld = "      mask: Region { item: popupColumn }\n";

  patchServiceQmlScript = pkgs.writeText "cross-feature-harness-patch.py" ''
    import sys

    def read(path):
        with open(path, encoding="utf-8") as f:
            return f.read()

    src_path = sys.argv[1]
    out_path = sys.argv[-1]
    pair_paths = sys.argv[2:-1]
    text = read(src_path)
    for i in range(0, len(pair_paths), 2):
        old = read(pair_paths[i])
        new = read(pair_paths[i + 1])
        count = text.count(old)
        if count != 1:
            print(
                f"security-recovery-cross-feature-vm: expected exactly one occurrence of "
                f"the pinned block from {pair_paths[i]!r} in Service.qml, found {count} - "
                "upstream/quickshell drift, patch needs updating",
                file=sys.stderr,
            )
            sys.exit(1)
        text = text.replace(old, new)

    with open(out_path, "w", encoding="utf-8") as f:
        f.write(text)
  '';
  emptyFile = pkgs.writeText "cross-feature-harness-empty.txt" "";
  panelOldFile = pkgs.writeText "cross-feature-harness-panel-old.txt" panelOld;
  panelNewFile = pkgs.writeText "cross-feature-harness-panel-new.txt" panelNew;
  anchorsOldFile = pkgs.writeText "cross-feature-harness-anchors-old.txt" anchorsOld;
  maskOldFile = pkgs.writeText "cross-feature-harness-mask-old.txt" maskOld;

  patchedServiceFile = pkgs.runCommand "cross-feature-harness-Service.qml"
    {
      nativeBuildInputs = [ pkgs.python3 ];
    } ''
    python3 ${patchServiceQmlScript} \
      "${compatRoot}/shell/plugins/notifications/Service.qml" \
      "${panelOldFile}" "${panelNewFile}" \
      "${anchorsOldFile}" "${emptyFile}" \
      "${maskOldFile}" "${emptyFile}" \
      "$out"
  '';

  # The combined harness: a bare PamContext, a bare PolkitAgent at the real
  # production D-Bus path, and (via Loader) the real patched notification
  # Service.qml - three real Quickshell native objects sharing one process,
  # driven entirely over IPC so the test script never reaches into internal
  # QML state by hand.
  harnessQml = ''
    import QtQuick
    import Quickshell
    import Quickshell.Io
    import Quickshell.Services.Pam
    import Quickshell.Services.Polkit

    ShellRoot {
      id: root
      property int pamCompletedCount: 0
      property string pamLastResult: ""
      property int polkitSucceededCount: 0
      property int polkitFailedCount: 0

      PamContext {
        id: pam
        config: "omarchy-lock-password"
        user: "${testUser}"

        onCompleted: function(result) {
          root.pamLastResult = PamResult.toString(result)
          root.pamCompletedCount += 1
          console.log("HARNESS_EVENT pam-completed " + root.pamLastResult)
        }
        onError: function(error) {
          root.pamLastResult = "error:" + PamError.toString(error)
          console.log("HARNESS_EVENT pam-error " + PamError.toString(error))
        }
      }

      PolkitAgent {
        id: agent
        path: "/org/omarchy/PolkitAgent"

        onIsRegisteredChanged: console.log("HARNESS_EVENT polkit-registered " + isRegistered)
        onFlowChanged: {
          if (agent.flow) {
            agent.flow.authenticationSucceeded.connect(function() {
              root.polkitSucceededCount += 1
              console.log("HARNESS_EVENT polkit-succeeded")
            })
            agent.flow.authenticationFailed.connect(function() {
              root.polkitFailedCount += 1
              console.log("HARNESS_EVENT polkit-failed")
            })
          }
        }
      }

      IpcHandler {
        target: "pam"

        function start(): string {
          if (pam.active) return "already-active"
          return pam.start() ? "started" : "start-failed"
        }

        function respond(value: string): string {
          if (!pam.responseRequired) return "no-prompt"
          pam.respond(value)
          return "responded"
        }

        function status(): string {
          return JSON.stringify({
            active: pam.active,
            responseRequired: pam.responseRequired,
            lastResult: root.pamLastResult,
            completedCount: root.pamCompletedCount
          })
        }
      }

      IpcHandler {
        target: "polkit"

        function status(): string {
          return JSON.stringify({
            isRegistered: agent.isRegistered,
            isActive: agent.isActive,
            isResponseRequired: agent.flow ? agent.flow.isResponseRequired : false,
            succeededCount: root.polkitSucceededCount,
            failedCount: root.polkitFailedCount
          })
        }

        function submit(value: string): string {
          if (!agent.flow) return "no-flow"
          agent.flow.submit(value)
          return "submitted"
        }

        function cancel(): string {
          if (!agent.flow) return "no-flow"
          agent.flow.cancelAuthenticationRequest()
          return "cancelled"
        }
      }

      Loader {
        source: Qt.resolvedUrl("fixture-notifications/Service.qml")
      }

      Component.onCompleted: console.log("HARNESS_READY")
    }
  '';

  # Laid out exactly like the notifications sibling's own fixture directory
  # (test/security-recovery-notifications-vm.nix's harnessDir) so QML import
  # resolution behaves identically, with the combined shell.qml above in
  # place of that file's Loader-only root.
  harnessDir = pkgs.runCommand "cross-feature-harness-fixture" { } ''
    mkdir -p $out/fixture-notifications/components
    cp ${compatRoot}/shell/plugins/notifications/NotificationLogic.js $out/fixture-notifications/NotificationLogic.js
    cp ${compatRoot}/shell/plugins/notifications/components/NotificationCard.qml $out/fixture-notifications/components/NotificationCard.qml
    cp ${patchedServiceFile} $out/fixture-notifications/Service.qml
    cat > $out/fixture-notifications/components/qmldir <<'EOF'
    module fixture-notifications.components
    NotificationCard 1.0 NotificationCard.qml
    EOF
    cp -R ${compatRoot}/shell/Commons $out/Commons
    cp -R ${compatRoot}/shell/Ui $out/Ui
    chmod -R u+w $out/Commons $out/Ui
    cat > $out/shell.qml <<'EOF'
    ${harnessQml}
    EOF
  '';

  # polkitd refuses to check an unregistered action id before any agent is
  # ever consulted - the same test-only .policy file
  # test/security-recovery-polkit-vm.nix already established the need for,
  # registering this file's own distinct action id. Test-only: never
  # installed by modules/ or packages/.
  testActionPolicy = pkgs.runCommand "omanixy-cross-feature-test-action-policy" { } ''
    mkdir -p "$out/share/polkit-1/actions"
    cat > "$out/share/polkit-1/actions/${testActionId}.policy" <<EOF
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE policyconfig PUBLIC "-//freedesktop//DTD PolicyKit Policy Configuration 1.0//EN" "http://www.freedesktop.org/standards/PolicyKit/1/policyconfig.dtd">
    <policyconfig>
      <action id="${testActionId}">
        <description>Omanixy layer 8 cross-feature security-recovery polkit VM test action</description>
        <message>Authentication is required for the Omanixy layer 8 cross-feature polkit VM test</message>
        <defaults>
          <allow_any>no</allow_any>
          <allow_inactive>no</allow_inactive>
          <allow_active>auth_self</allow_active>
        </defaults>
      </action>
    </policyconfig>
    EOF
  '';

  driverScript = pkgs.writeShellScript "omanixy-cross-feature-vm-driver" ''
    set -u
    QS="${quickshellBin}/bin/quickshell"
    PKCHECK="${pkgs.polkit.bin}/bin/pkcheck"
    JQ="${pkgs.jq}/bin/jq"
    HARNESS_DIR="${harnessDir}"
    ACTION_ID="${testActionId}"
    FIXTURE_PASSWORD="${testPassword}"

    export HOME="/home/${testUser}"
    export XDG_RUNTIME_DIR="/run/user/$(id -u)"
    export QT_QPA_PLATFORM=offscreen
    export QS_DISABLE_FILE_WATCHER=1
    export QS_NO_RELOAD_POPUP=1
    export PATH="${notifStateBinDir}:$PATH"

    scenario="$1"
    WORKDIR="$HOME/cross-feature-test-$scenario"
    rm -rf "$WORKDIR"
    mkdir -p "$WORKDIR"
    cd "$WORKDIR"

    popup_count() { ls "$HOME/.local/state/omarchy/notifications/"*.json 2>/dev/null | wc -l; }
    owner_now() {
      busctl --user call org.freedesktop.DBus /org/freedesktop/DBus \
        org.freedesktop.DBus GetNameOwner s org.freedesktop.Notifications 2>&1
    }
    has_owner() { case "$1" in *'"'*) return 0 ;; *) return 1 ;; esac; }
    qs_ipc() {
      local target=$1 fn=$2
      shift 2
      QML2_IMPORT_PATH="$HARNESS_DIR" timeout 10 "$QS" ipc -n -p "$HARNESS_DIR" call -- "$target" "$fn" "$@" 2>/dev/null
    }
    wait_for() {
      local target=$1 expr=$2 limit=''${3:-40} n=0 val
      while [ "$n" -lt "$limit" ]; do
        val=$(qs_ipc "$target" status)
        if [ -n "$val" ] && printf '%s' "$val" | "$JQ" -e "$expr" >/dev/null 2>&1; then
          return 0
        fi
        n=$((n + 1))
        sleep 0.5
      done
      return 1
    }
    wait_ipc_ready() {
      local n=0
      while [ "$n" -lt 150 ]; do
        [ "$(qs_ipc notifications ping)" = "ok" ] && return 0
        n=$((n + 1))
        sleep 0.1
      done
      return 1
    }

    case "$scenario" in

      boot)
        QML2_IMPORT_PATH="$HARNESS_DIR" "$QS" -n -p "$HARNESS_DIR" >harness.log 2>&1 &
        hpid=$!

        if ! wait_ipc_ready; then
          echo "CHECK boot-ready FAIL harness-never-ready"
          cat harness.log
          kill "$hpid" 2>/dev/null || true
          exit 0
        fi
        echo "CHECK boot-ready PASS"

        if wait_for polkit '.isRegistered == true' 60; then
          echo "CHECK polkit-registration PASS"
        else
          echo "CHECK polkit-registration FAIL"
        fi

        owner=$(owner_now)
        if has_owner "$owner"; then
          echo "CHECK notifications-ownership PASS owner=$owner"
        else
          echo "CHECK notifications-ownership FAIL owner=$owner"
        fi

        # Real PAM conversation against the real generated
        # omarchy-lock-password service.
        qs_ipc pam start >/dev/null
        if wait_for pam '.responseRequired == true' 20; then
          qs_ipc pam respond "$FIXTURE_PASSWORD" >/dev/null
          if wait_for pam '.completedCount == 1' 20; then
            pam_status=$(qs_ipc pam status)
            case "$pam_status" in
              *'"lastResult":"Success"'*) echo "CHECK pam-conversation PASS status=$pam_status" ;;
              *) echo "CHECK pam-conversation FAIL status=$pam_status" ;;
            esac
          else
            echo "CHECK pam-conversation FAIL no-completion"
          fi
        else
          echo "CHECK pam-conversation FAIL no-prompt"
        fi

        # Real polkit authentication against the real running polkitd.
        "$PKCHECK" -a "$ACTION_ID" -u -p $$ >pkcheck.log 2>&1 &
        p1=$!
        if wait_for polkit '.isResponseRequired == true' 40; then
          qs_ipc polkit submit "$FIXTURE_PASSWORD" >/dev/null
          wait "$p1"
          pkexit=$?
          if [ "$pkexit" = "0" ]; then
            echo "CHECK polkit-authentication PASS"
          else
            echo "CHECK polkit-authentication FAIL exit=$pkexit"
          fi
        else
          echo "CHECK polkit-authentication FAIL no-prompt"
          cat pkcheck.log
          kill "$p1" 2>/dev/null || true
        fi

        # Real delivery through the real, unmodified NotificationServer.
        notify-send -a TestClient -u normal "CrossFeature boot hello" "body text"
        sleep 1
        count=$(popup_count)
        if [ "$count" = "1" ]; then
          echo "CHECK notifications-delivery PASS"
        else
          echo "CHECK notifications-delivery FAIL popup_count=$count"
        fi

        # Combining all three capabilities must not spawn any extra process:
        # exactly one quickshell process exists throughout this scenario,
        # holding the one PamContext, the one PolkitAgent, and the one
        # NotificationServer together.
        qs_procs=$(pgrep -fc 'qu[i]ckshell -n -p' || true)
        if [ "$qs_procs" = "1" ]; then
          echo "CHECK single-process PASS qs_procs=$qs_procs"
        else
          echo "CHECK single-process FAIL qs_procs=$qs_procs"
        fi

        kill "$hpid" 2>/dev/null || true
        wait "$hpid" 2>/dev/null
        ;;

      crash)
        QML2_IMPORT_PATH="$HARNESS_DIR" "$QS" -n -p "$HARNESS_DIR" >harness1.log 2>&1 &
        hpid=$!

        if ! wait_ipc_ready; then
          echo "CHECK crash-setup FAIL harness-never-ready"
          cat harness1.log
          kill "$hpid" 2>/dev/null || true
          exit 0
        fi
        if ! wait_for polkit '.isRegistered == true' 60; then
          echo "CHECK crash-setup FAIL polkit-never-registered"
          kill "$hpid" 2>/dev/null || true
          exit 0
        fi

        # Establish real, live/in-flight state on all three surfaces at once.
        qs_ipc pam start >/dev/null
        if wait_for pam '.responseRequired == true' 20; then
          echo "CHECK crash-pam-inflight PASS"
        else
          echo "CHECK crash-pam-inflight FAIL"
        fi

        "$PKCHECK" -a "$ACTION_ID" -u -p $$ >pkcheck-inflight.log 2>&1 &
        p1=$!
        if wait_for polkit '.isResponseRequired == true' 40; then
          echo "CHECK crash-polkit-inflight PASS"
        else
          echo "CHECK crash-polkit-inflight FAIL"
          cat pkcheck-inflight.log
        fi

        # A live notification carrying a real pending default action,
        # matching a real independent client - not a fixture with no action
        # to resurrect.
        rm -f action-result.txt
        (notify-send -a TestClient -A default=Open "CrossFeature pending action" >action-result.txt 2>&1) &
        action_pid=$!
        n=0
        while [ "$n" -lt 20 ] && [ "$(popup_count)" -lt 1 ]; do n=$((n + 1)); sleep 0.2; done
        popup_before=$(popup_count)
        if [ "$popup_before" -ge 1 ]; then
          echo "CHECK crash-notification-live PASS count=$popup_before"
        else
          echo "CHECK crash-notification-live FAIL count=$popup_before"
        fi

        unix_chkpwd_before=$(pgrep -c unix_chkpwd 2>/dev/null || echo 0)

        # Simulate the real omanixy-shell.service process crashing while PAM,
        # polkit, and notification state all exist at once.
        kill -9 "$hpid" 2>/dev/null || true
        wait "$hpid" 2>/dev/null

        # Bounded, not necessarily fast: a real pkcheck client must not hang
        # forever just because the process that was going to answer it died.
        n=0
        while kill -0 "$p1" 2>/dev/null && [ "$n" -lt 60 ]; do sleep 0.5; n=$((n + 1)); done
        if kill -0 "$p1" 2>/dev/null; then
          echo "CHECK crash-polkit-client-bounded FAIL still-running-after-30s"
          kill "$p1" 2>/dev/null || true
          wait "$p1" 2>/dev/null
        else
          wait "$p1" 2>/dev/null
          echo "CHECK crash-polkit-client-bounded PASS pkcheck_exit=$?"
        fi

        leftover_qs=$(pgrep -fc 'qu[i]ckshell -n -p' || true)
        if [ "$leftover_qs" = "0" ]; then
          echo "CHECK crash-no-orphan-process PASS"
        else
          echo "CHECK crash-no-orphan-process FAIL leftover=$leftover_qs"
        fi

        unix_chkpwd_after=$(pgrep -c unix_chkpwd 2>/dev/null || echo 0)
        echo "DIAG unix_chkpwd before=$unix_chkpwd_before after=$unix_chkpwd_after"

        # The bounded systemd restart: a fresh combined harness process,
        # mirroring the real omanixy-shell.service's Restart=on-failure
        # bringing the process back after a crash.
        QML2_IMPORT_PATH="$HARNESS_DIR" "$QS" -n -p "$HARNESS_DIR" >harness2.log 2>&1 &
        h2pid=$!

        if ! wait_ipc_ready; then
          echo "CHECK crash-restart FAIL harness-never-ready"
          cat harness2.log
          kill "$h2pid" 2>/dev/null || true
          kill "$action_pid" 2>/dev/null || true
          exit 0
        fi

        # No stale polkit authentication flow: the fresh harness registers
        # cleanly at the same real D-Bus path the crashed one held, with no
        # lingering "already registered" conflict from the dead process.
        if wait_for polkit '.isRegistered == true' 60; then
          echo "CHECK crash-polkit-fresh-registration PASS"
        else
          echo "CHECK crash-polkit-fresh-registration FAIL"
        fi

        # A fresh authentication request against the fresh harness succeeds
        # cleanly.
        "$PKCHECK" -a "$ACTION_ID" -u -p $$ >pkcheck-fresh.log 2>&1 &
        p2=$!
        if wait_for polkit '.isResponseRequired == true' 40; then
          qs_ipc polkit submit "$FIXTURE_PASSWORD" >/dev/null
          wait "$p2"
          pkexit2=$?
          if [ "$pkexit2" = "0" ]; then
            echo "CHECK crash-polkit-fresh-auth PASS"
          else
            echo "CHECK crash-polkit-fresh-auth FAIL exit=$pkexit2"
          fi
        else
          echo "CHECK crash-polkit-fresh-auth FAIL no-prompt"
          cat pkcheck-fresh.log
          kill "$p2" 2>/dev/null || true
        fi

        # A fresh PAM conversation still works.
        qs_ipc pam start >/dev/null
        if wait_for pam '.responseRequired == true' 20; then
          qs_ipc pam respond "$FIXTURE_PASSWORD" >/dev/null
          if wait_for pam '.completedCount == 1' 20; then
            fresh_pam_status=$(qs_ipc pam status)
            case "$fresh_pam_status" in
              *'"lastResult":"Success"'*) echo "CHECK crash-pam-fresh PASS status=$fresh_pam_status" ;;
              *) echo "CHECK crash-pam-fresh FAIL status=$fresh_pam_status" ;;
            esac
          else
            echo "CHECK crash-pam-fresh FAIL no-completion"
          fi
        else
          echo "CHECK crash-pam-fresh FAIL no-prompt"
        fi

        # The pre-crash notification's popup file persists (data-only state
        # surviving the crash) and is restored by the fresh harness's own
        # Component.onCompleted restorePopups() path.
        n=0
        while [ "$n" -lt 30 ] && [ "$(popup_count)" -lt 1 ]; do n=$((n + 1)); sleep 0.2; done
        popup_after_restart=$(popup_count)
        if [ "$popup_after_restart" -ge 1 ]; then
          echo "CHECK crash-notification-restored PASS count=$popup_after_restart"
        else
          echo "CHECK crash-notification-restored FAIL count=$popup_after_restart"
        fi

        # The restored row is data-only: invoking it must never resurrect the
        # pre-crash sender's action as live. The original notify-send client
        # (still running, still listening for its own ActionInvoked signal)
        # is the independent witness - if the restored row's action ever
        # fired, its output would contain "default".
        qs_ipc notifications invokeLast >/dev/null
        sleep 2
        action_result=$(cat action-result.txt 2>/dev/null || true)
        case "$action_result" in
          *default*) echo "CHECK crash-notification-action-not-resurrected FAIL action_result=$action_result" ;;
          *) echo "CHECK crash-notification-action-not-resurrected PASS action_result=''${action_result:-<empty>}" ;;
        esac

        kill "$h2pid" 2>/dev/null || true
        kill "$action_pid" 2>/dev/null || true
        wait "$h2pid" 2>/dev/null
        ;;

      *)
        echo "unknown scenario: $scenario" >&2
        exit 1
        ;;
    esac

    # Correctness/failure is reported exclusively via the CHECK lines above,
    # never via this script's own process exit code - the last command of a
    # case branch is frequently a `wait` on a deliberately-killed background
    # process, whose (128+signal) exit status must never leak out as this
    # script's own.
    exit 0
  '';

  runScenario = scenario:
    "systemd-run --uid=${testUser} --pipe --wait --collect -p PAMName=login --unit=omanixy-crossfeature-${scenario} ${driverScript} ${scenario}";
in
pkgs.testers.runNixOSTest {
  name = "security-recovery-cross-feature-vm";

  nodes.machine = { ... }: {
    imports = [
      self.nixosModules.default
      home-manager.nixosModules.home-manager
    ];

    system.stateVersion = "26.11";

    programs.omanixy.security.pam.password.enable = true;
    programs.omanixy.security.polkit.system.enable = true;

    # polkitd refuses to check an unregistered action id before any agent is
    # ever consulted; this test-only rule/policy pair (never installed by
    # modules/ or packages/) registers this file's own distinct action id,
    # requiring authentication as the disposable VM-only test user itself.
    security.polkit.extraConfig = ''
      polkit.addRule(function(action, subject) {
        if (action.id == "${testActionId}") {
          return polkit.Result.AUTH_SELF;
        }
      });
    '';

    users.users.${testUser} = {
      isNormalUser = true;
      password = testPassword;
    };

    environment.systemPackages = [ quickshellBin pkgs.jq pkgs.libnotify testActionPolicy ];

    home-manager.useGlobalPkgs = true;
    home-manager.useUserPackages = true;
    home-manager.users.${testUser} = {
      imports = [ self.homeManagerModules.default ];
      home.username = testUser;
      home.homeDirectory = "/home/${testUser}";
      home.stateVersion = "25.11";
      programs.omanixy.enable = true;
      programs.omanixy.security.polkit.agent.enable = true;
      programs.omanixy.security.notifications.daemon.enable = true;
    };

    virtualisation.memorySize = 3072;
  };

  testScript = ''
    machine.wait_for_unit("multi-user.target")
    machine.wait_for_unit("polkit.service")

    print("=== setup: the real declarative capability activates for a real user with all three surfaces selected together ===")
    machine.wait_until_succeeds(
        "cat /home/${testUser}/.config/systemd/user/omanixy-shell.service"
    )
    unit_file = machine.succeed(
        "cat /home/${testUser}/.config/systemd/user/omanixy-shell.service"
    )
    assert "ExecStart" in unit_file, unit_file
    print("home-manager-provisioned omanixy-shell.service unit is present (never started by this test)")

    # No extra PAM service as a side effect of combining capabilities: only
    # the one password service this layer's PAM option generates exists;
    # fingerprint is off, so its service must not exist either.
    machine.succeed("test -e /etc/pam.d/omarchy-lock-password")
    machine.fail("test -e /etc/pam.d/omarchy-lock-fingerprint")

    def assert_all_checks_pass(output):
        fails = [
            line for line in output.splitlines()
            if line.startswith("CHECK ") and " FAIL" in line
        ]
        assert not fails, "\n".join(fails) + "\n\nfull output:\n" + output

    print("=== scenario 1: cross-feature boot, no ownership conflicts ===")
    machine.succeed("rm -rf /home/${testUser}/.local/state/omarchy")
    out = machine.succeed("${runScenario "boot"}")
    print(out)
    assert_all_checks_pass(out)

    uid = machine.succeed("id -u ${testUser}").strip()
    active_state = machine.succeed(
        f"su -l ${testUser} -c 'XDG_RUNTIME_DIR=/run/user/{uid} systemctl --user show omanixy-shell -p ActiveState --value'"
    ).strip()
    print(f"omanixy-shell.service ActiveState after scenario 1: {active_state}")
    assert active_state in ("inactive", "dead"), (
        f"enabling PAM, polkit, and the notification daemon together must not itself "
        f"start omanixy-shell.service as a side effect; got {active_state}"
    )

    user_units = machine.succeed(
        f"su -l ${testUser} -c 'XDG_RUNTIME_DIR=/run/user/{uid} systemctl --user list-units --type=service --all' 2>&1"
    )
    lowered = user_units.lower()
    assert "hyprpolkitagent" not in lowered and "polkit-gnome" not in lowered, (
        "combining the capabilities must not have caused any other polkit agent unit "
        f"to appear:\n{user_units}"
    )
    print("no extra polkit agent or notification daemon unit is present alongside the combined capability")

    print("=== scenario 2: cross-feature crash recovery ===")
    machine.succeed("rm -rf /home/${testUser}/.local/state/omarchy")
    out = machine.succeed("${runScenario "crash"}")
    print(out)
    assert_all_checks_pass(out)
  '';
}
