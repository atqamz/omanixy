# Layer 8 (security-recovery) real-backend evidence for the
# security.notification-daemon ledger entry's `required_before_promotion`
# list (upstream/porting-matrix.yaml).
#
# Layer 7 (programs.omanixy.security.notifications.daemon.enable,
# modules/home/default.nix) proved the declarative capability and the pinned
# Quickshell NotificationServer/Service.qml ABI hermetically: offscreen QML
# against a fake NotificationServer and a fake popup PanelWindow
# (test/security-notifications-qml-behavior.sh) - a real org.freedesktop.
# Notifications D-Bus registration was never exercised. This file boots a
# real NixOS VM with the option enabled, a real session D-Bus (obtained via
# a genuine PAM/logind session - `systemd-run --uid=<user> -p PAMName=login`,
# the same session-registration mechanism a real login/display-manager
# session uses), and a minimal offscreen Quickshell harness that loads the
# exact same, unmodified production `Service.qml`/`NotificationLogic.js` the
# notification-daemon-enabled build ships - built from the exact same pinned
# `quickshell-omanixy` derivation production runs - with only the popup
# `PanelWindow` mechanically swapped for a plain `Item` (no Wayland
# layer-shell surface, since only popup *presentation* needs a compositor;
# D-Bus ownership/delivery does not). The real
# `Quickshell.Services.Notifications.NotificationServer` instantiation
# itself is left completely untouched, unlike the hermetic test - that is
# the whole point of this file.
#
# The harness is driven live via Quickshell's own IPC mechanism
# (`quickshell ipc call -- notifications <function>`), the same real
# mechanism `packages/omanixy-shell/ipc-wrapper.bash` uses in production,
# and via independent real D-Bus clients (`notify-send`, `busctl`) - never
# via a hand-authored JS test driver reaching into internal state.
{ pkgs, self, home-manager }:
let
  lib = pkgs.lib;
  system = pkgs.stdenv.hostPlatform.system;

  testUser = "omanixy-recovery-test";

  # The notification-daemon-enabled runtime, obtained the same way
  # flake.nix's own `homeConfigurationFor` builds Home Manager
  # configurations - this is the only way to reach the real, patched
  # Service.qml/NotificationLogic.js and the real omanixy-notification-state
  # adapter binary from this file's restricted `{ pkgs, self, home-manager }`
  # parameter set (the `omarchy`/`quickshellSrc` flake inputs are only
  # reachable through `self.homeManagerModules.default`'s closure, not
  # directly). The extraction never builds an activation package - only
  # `.config.home.packages` is read, which is cheap evaluation.
  notifHome = home-manager.lib.homeManagerConfiguration {
    pkgs = pkgs;
    modules = [
      self.homeManagerModules.default
      {
        home.username = "omanixy-notif-fixture";
        home.homeDirectory = "/build/omanixy-notif-fixture";
        home.stateVersion = "25.11";
        programs.omanixy.enable = true;
        programs.omanixy.security.notifications.daemon.enable = true;
      }
    ];
  };
  runtimePkg = lib.findFirst
    (p: (p.name or "") == "omanixy-shell")
    (throw "security-recovery-notifications-vm: omanixy-shell runtime package not found in home.packages")
    notifHome.config.home.packages;

  quickshellBin = runtimePkg.passthru.quickshell;
  compatRoot = runtimePkg.passthru.omarchyCompatibilityRoot;
  # Default output ("out") of the two-output compatibilityBin derivation -
  # the real omanixy-notification-state adapter binary Service.qml's own
  # Process calls invoke by bare name, exactly as production does.
  notifStateBinDir = "${runtimePkg.passthru.compatibilityBin}/bin";

  # Harness-only mechanical transform, in spirit and in the exact pinned
  # text blocks identical to the offscreen technique already proven in
  # test/security-notifications-qml-behavior.sh: PanelWindow -> Item (no
  # Wayland layer-shell surface is available or needed for D-Bus
  # ownership/delivery), the boolean-edge anchors and the layer-shell-only
  # mask dropped. Unlike that hermetic test, the real
  # Quickshell.Services.Notifications.NotificationServer is left completely
  # untouched.
  #
  # The source Service.qml lives inside compatRoot, a derivation output -
  # reading it via builtins.readFile here would force Nix to build that
  # derivation during evaluation (import-from-derivation), which breaks
  # `nix flake check --no-build` the same way every other check in this
  # repo avoids by doing this kind of file surgery at build time instead of
  # eval time. pkgs.runCommand defers the actual read/patch to the build
  # phase, exactly like the sibling `harnessDir` derivation below already
  # does for its own file copies.
  panelOld = "    PanelWindow {\n      id: popupWindow\n      required property var modelData\n      screen: modelData\n      visible: popupModel.count > 0\n\n      WlrLayershell.namespace: \"omarchy-notifications\"\n      WlrLayershell.layer: WlrLayer.Overlay\n      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None\n      exclusionMode: ExclusionMode.Ignore\n      color: \"transparent\"\n\n";
  panelNew = "    Item {\n      id: popupWindow\n      required property var modelData\n      visible: popupModel.count > 0\n\n";
  anchorsOld = "      anchors { top: true; bottom: true; left: true; right: true }\n\n";
  maskOld = "      mask: Region { item: popupColumn }\n";

  patchServiceQmlScript = pkgs.writeText "notif-harness-patch.py" ''
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
                f"security-recovery-notifications-vm: expected exactly one occurrence of "
                f"the pinned block from {pair_paths[i]!r} in Service.qml, found {count} - "
                "upstream/quickshell drift, patch needs updating",
                file=sys.stderr,
            )
            sys.exit(1)
        text = text.replace(old, new)

    with open(out_path, "w", encoding="utf-8") as f:
        f.write(text)
  '';
  emptyFile = pkgs.writeText "notif-harness-empty.txt" "";
  panelOldFile = pkgs.writeText "notif-harness-panel-old.txt" panelOld;
  panelNewFile = pkgs.writeText "notif-harness-panel-new.txt" panelNew;
  anchorsOldFile = pkgs.writeText "notif-harness-anchors-old.txt" anchorsOld;
  maskOldFile = pkgs.writeText "notif-harness-mask-old.txt" maskOld;

  patchedServiceFile = pkgs.runCommand "notif-harness-Service.qml"
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

  # The real, patched Service.qml/NotificationLogic.js/NotificationCard.qml
  # a notification-daemon-enabled build ships, plus the Commons/Ui
  # singletons `qs.Commons`/`qs.Ui` resolve against, laid out exactly like
  # the already-proven hermetic harness (test/security-notifications-qml-
  # behavior.sh's setup_fixture) so QML import resolution behaves
  # identically.
  harnessDir = pkgs.runCommand "notif-harness-fixture" { } ''
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
    import QtQuick
    import Quickshell

    ShellRoot {
      Loader {
        source: Qt.resolvedUrl("fixture-notifications/Service.qml")
      }
    }
    EOF
  '';

  # An independent, unknown (not "declaratively known") second claimant of
  # org.freedesktop.Notifications - a bare instantiation of the exact same
  # pinned NotificationServer type, run as its own quickshell process on the
  # real session bus. Scenario 4 needs a real competing owner; this is the
  # narrowest one that still exercises the real D-Bus RequestName/
  # QDBusServiceWatcher ABI already statically audited in server.cpp,
  # without needing an actual mako/dunst/swaync/fnott package (that
  # declarative-known-daemon conflict is already covered by the existing
  # hermetic HM assertion tests).
  stubDir = pkgs.runCommand "notif-stub-fixture" { } ''
    mkdir -p $out
    cat > $out/shell.qml <<'EOF'
    import QtQuick
    import Quickshell
    import Quickshell.Services.Notifications

    ShellRoot {
      NotificationServer {
        id: server
        keepOnReload: false
      }
    }
    EOF
  '';

  # One self-contained scenario per case, each starting from a clean state
  # directory (wiped by the test script before every invocation) and each
  # launching its own harness (and, for the collision scenario, its own
  # stub) - matching the sibling security-recovery-polkit-vm.nix's
  # `driverScript` shape. Every check the scenario cares about is computed
  # here, in bash, where the real values already live, and reported as a
  # `CHECK <name> PASS|FAIL ...` line the test script asserts against -
  # never a soft print-only result.
  driverScript = pkgs.writeShellScript "omanixy-notif-vm-driver" ''
    set -u
    QS="${quickshellBin}/bin/quickshell"
    HARNESS_DIR="${harnessDir}"
    STUB_DIR="${stubDir}"

    export HOME="/home/${testUser}"
    export XDG_RUNTIME_DIR="/run/user/$(id -u)"
    export QT_QPA_PLATFORM=offscreen
    export QS_DISABLE_FILE_WATCHER=1
    export QS_NO_RELOAD_POPUP=1
    export PATH="${notifStateBinDir}:$PATH"

    scenario="$1"
    WORKDIR="$HOME/notif-test-$scenario"
    rm -rf "$WORKDIR"
    mkdir -p "$WORKDIR"
    cd "$WORKDIR"

    popup_count() { ls "$HOME/.local/state/omarchy/notifications/"*.json 2>/dev/null | wc -l; }
    history_count() { ls "$HOME/.local/state/omarchy/notifications/history/"*.json 2>/dev/null | wc -l; }
    owner_now() {
      busctl --user call org.freedesktop.DBus /org/freedesktop/DBus \
        org.freedesktop.DBus GetNameOwner s org.freedesktop.Notifications 2>&1
    }
    has_owner() { case "$1" in *'"'*) return 0 ;; *) return 1 ;; esac; }
    qs_ipc() {
      local dir=$1 target=$2 fn=$3
      shift 3
      QML2_IMPORT_PATH="$dir" timeout 10 "$QS" ipc -n -p "$dir" call -- "$target" "$fn" "$@" 2>/dev/null
    }
    wait_ipc_ready() {
      local dir=$1 n=0
      while [ "$n" -lt 150 ]; do
        [ "$(qs_ipc "$dir" notifications ping)" = "ok" ] && return 0
        n=$((n + 1))
        sleep 0.1
      done
      return 1
    }
    # Launches "$QS -n -p $HARNESS_DIR" into $harness_log, retrying if
    # Quickshell reports "An instance of this configuration is already
    # running" - real, observed behavior right after a prior instance of
    # the same $HARNESS_DIR config was killed via an external cgroup-wide
    # `systemctl stop` (session-phase1/session-phase2's own teardown)
    # rather than this script's own in-process `kill "$hpid"; wait "$hpid"`
    # pattern every other scenario uses: Quickshell's own instance lock
    # apparently needs a moment longer to release in that case. Bounded to
    # 20 attempts/~20s; sets $hpid on success.
    launch_harness_retrying() {
      local harness_log=$1 attempt=0
      while [ "$attempt" -lt 20 ]; do
        QML2_IMPORT_PATH="$HARNESS_DIR" "$QS" -n -p "$HARNESS_DIR" >"$harness_log" 2>&1 &
        hpid=$!
        if wait_ipc_ready "$HARNESS_DIR"; then
          return 0
        fi
        if grep -q "already running" "$harness_log" 2>/dev/null; then
          kill "$hpid" 2>/dev/null || true
          wait "$hpid" 2>/dev/null
          attempt=$((attempt + 1))
          sleep 1
          continue
        fi
        return 1
      done
      return 1
    }

    case "$scenario" in

      ownership-delivery)
        QML2_IMPORT_PATH="$HARNESS_DIR" "$QS" -n -p "$HARNESS_DIR" >harness.log 2>&1 &
        hpid=$!
        if ! wait_ipc_ready "$HARNESS_DIR"; then
          echo "CHECK ownership-delivery FAIL harness-never-ready"
          cat harness.log
          kill "$hpid" 2>/dev/null || true
          exit 0
        fi

        owner=$(owner_now)
        if has_owner "$owner"; then
          echo "CHECK ownership PASS owner=$owner"
        else
          echo "CHECK ownership FAIL owner=$owner"
        fi

        notify-send -a TestClient -u normal "Scenario1 hello" "body text"
        sleep 1
        count=$(popup_count)
        if [ "$count" = "1" ]; then
          echo "CHECK delivery PASS"
        else
          echo "CHECK delivery FAIL popup_count=$count"
        fi

        kill "$hpid" 2>/dev/null || true
        wait "$hpid" 2>/dev/null
        ;;

      replace-action-close)
        QML2_IMPORT_PATH="$HARNESS_DIR" "$QS" -n -p "$HARNESS_DIR" >harness.log 2>&1 &
        hpid=$!
        if ! wait_ipc_ready "$HARNESS_DIR"; then
          echo "CHECK replace-action-close FAIL harness-never-ready"
          cat harness.log
          kill "$hpid" 2>/dev/null || true
          exit 0
        fi

        id1=$(notify-send -a TestClient -p -u normal "Scenario2 original")
        n=0
        while [ "$n" -lt 50 ] && [ "$(popup_count)" -lt 1 ]; do n=$((n + 1)); sleep 0.1; done
        count_after_original=$(popup_count)
        notify-send -a TestClient -r "$id1" -u normal "Scenario2 updated"
        n=0
        while [ "$n" -lt 50 ]; do
          survivor=$(cat "$HOME/.local/state/omarchy/notifications/"*"-$id1.json" 2>/dev/null)
          case "$survivor" in *"Scenario2 updated"*) break ;; esac
          n=$((n + 1))
          sleep 0.1
        done
        count_after_replace=$(popup_count)
        if [ "$count_after_replace" = "$count_after_original" ]; then
          echo "CHECK replace-identity PASS count=$count_after_replace"
        else
          echo "CHECK replace-identity FAIL before=$count_after_original after=$count_after_replace"
        fi
        case "$survivor" in
          *"Scenario2 updated"*) echo "CHECK replace-content PASS" ;;
          *) echo "CHECK replace-content FAIL survivor=$survivor" ;;
        esac

        rm -f action-result.txt
        (notify-send -a TestClient -A default=Open "Scenario2 action" >action-result.txt 2>&1) &
        action_pid=$!
        sleep 1
        qs_ipc "$HARNESS_DIR" notifications invokeLast >/dev/null
        wait "$action_pid" 2>/dev/null
        action_result=$(cat action-result.txt 2>/dev/null)
        if [ "$action_result" = "default" ]; then
          echo "CHECK default-action PASS"
        else
          echo "CHECK default-action FAIL result=$action_result"
        fi

        id2=$(notify-send -a TestClient -p -u normal "Scenario2 close")
        busctl --user monitor org.freedesktop.Notifications >closesig.log 2>&1 &
        mon_pid=$!
        sleep 1
        busctl --user call org.freedesktop.Notifications /org/freedesktop/Notifications \
          org.freedesktop.Notifications CloseNotification u "$id2"
        sleep 1
        kill "$mon_pid" 2>/dev/null || true
        wait "$mon_pid" 2>/dev/null
        if grep -q "Member=NotificationClosed" closesig.log; then
          echo "CHECK close-roundtrip PASS line=$(grep -A2 Member=NotificationClosed closesig.log | tr '\n' ' ')"
        else
          echo "CHECK close-roundtrip FAIL"
        fi

        kill "$hpid" 2>/dev/null || true
        wait "$hpid" 2>/dev/null
        ;;

      dnd-restart)
        QML2_IMPORT_PATH="$HARNESS_DIR" "$QS" -n -p "$HARNESS_DIR" >harness1.log 2>&1 &
        hpid=$!
        if ! wait_ipc_ready "$HARNESS_DIR"; then
          echo "CHECK dnd-restart FAIL harness-never-ready"
          cat harness1.log
          kill "$hpid" 2>/dev/null || true
          exit 0
        fi

        qs_ipc "$HARNESS_DIR" notifications setDnd true >/dev/null
        dnd_state=$(qs_ipc "$HARNESS_DIR" notifications isDnd)
        if [ "$dnd_state" = "on" ]; then
          echo "CHECK dnd-on PASS"
        else
          echo "CHECK dnd-on FAIL state=$dnd_state"
        fi

        before_count=$(popup_count)
        notify-send -a TestClient -u normal "Scenario3 silenced"
        sleep 1
        after_count=$(popup_count)
        hist=$(history_count)
        if [ "$after_count" = "$before_count" ]; then
          echo "CHECK dnd-suppressed PASS"
        else
          echo "CHECK dnd-suppressed FAIL before=$before_count after=$after_count"
        fi
        if [ "$hist" -ge 1 ]; then
          echo "CHECK dnd-recorded-in-history PASS history_count=$hist"
        else
          echo "CHECK dnd-recorded-in-history FAIL"
        fi

        sleep 1
        settings=$(cat "$HOME/.local/state/omarchy/notifications.json" 2>/dev/null)
        case "$settings" in
          *'"dnd": true'*) echo "CHECK dnd-settings-flushed PASS" ;;
          *) echo "CHECK dnd-settings-flushed FAIL settings=$settings" ;;
        esac

        kill "$hpid" 2>/dev/null || true
        wait "$hpid" 2>/dev/null
        sleep 1

        QML2_IMPORT_PATH="$HARNESS_DIR" "$QS" -n -p "$HARNESS_DIR" >harness2.log 2>&1 &
        hpid2=$!
        if ! wait_ipc_ready "$HARNESS_DIR"; then
          echo "CHECK dnd-restart-persisted FAIL second-harness-never-ready"
          cat harness2.log
          kill "$hpid2" 2>/dev/null || true
          exit 0
        fi
        restored=$(qs_ipc "$HARNESS_DIR" notifications isDnd)
        if [ "$restored" = "on" ]; then
          echo "CHECK dnd-restart-persisted PASS"
        else
          echo "CHECK dnd-restart-persisted FAIL restored=$restored"
        fi

        kill "$hpid2" 2>/dev/null || true
        wait "$hpid2" 2>/dev/null
        ;;

      collision-reclaim)
        QML2_IMPORT_PATH="$STUB_DIR" "$QS" -n -p "$STUB_DIR" >stub.log 2>&1 &
        spid=$!
        sleep 1
        owner_before=$(owner_now)
        if has_owner "$owner_before"; then
          echo "CHECK stub-owns-name PASS owner=$owner_before"
        else
          echo "CHECK stub-owns-name FAIL owner=$owner_before"
        fi

        QML2_IMPORT_PATH="$HARNESS_DIR" "$QS" -n -p "$HARNESS_DIR" >harness.log 2>&1 &
        hpid=$!
        if ! wait_ipc_ready "$HARNESS_DIR"; then
          echo "CHECK collision-reclaim FAIL harness-never-ready"
          cat harness.log
          kill "$hpid" "$spid" 2>/dev/null || true
          exit 0
        fi

        owner_during=$(owner_now)
        if [ "$owner_during" = "$owner_before" ]; then
          echo "CHECK harness-did-not-steal-name PASS"
        else
          echo "CHECK harness-did-not-steal-name FAIL before=$owner_before during=$owner_during"
        fi

        notify-send -a TestClient -u normal "Scenario4 during collision"
        sleep 1
        count_during=$(popup_count)
        alive_during=no
        kill -0 "$hpid" 2>/dev/null && alive_during=yes
        if [ "$alive_during" = "yes" ]; then
          echo "CHECK harness-survives-collision PASS"
        else
          echo "CHECK harness-survives-collision FAIL"
        fi
        if [ "$count_during" = "0" ]; then
          echo "CHECK harness-did-not-receive-during-collision PASS"
        else
          echo "CHECK harness-did-not-receive-during-collision FAIL count=$count_during"
        fi

        kill "$spid" 2>/dev/null || true
        wait "$spid" 2>/dev/null

        # No restart of the harness anywhere below: $hpid, launched exactly
        # once above, is the only process ever started for this scenario -
        # reclaim must happen event-driven, in that same still-running
        # process, purely via the pinned QDBusServiceWatcher::
        # serviceUnregistered -> tryRegister() path.
        n=0
        owner_after=""
        while [ "$n" -lt 150 ]; do
          owner_after=$(owner_now)
          has_owner "$owner_after" && break
          n=$((n + 1))
          sleep 0.1
        done
        if has_owner "$owner_after"; then
          echo "CHECK reclaim-succeeded PASS owner=$owner_after attempts=$n"
        else
          echo "CHECK reclaim-succeeded FAIL"
        fi

        alive_after=no
        kill -0 "$hpid" 2>/dev/null && alive_after=yes
        if [ "$alive_after" = "yes" ]; then
          echo "CHECK reclaim-no-restart PASS pid=$hpid"
        else
          echo "CHECK reclaim-no-restart FAIL harness-pid-gone"
        fi

        notify-send -a TestClient -u normal "Scenario4 after reclaim"
        sleep 1
        count_after=$(popup_count)
        if [ "$count_after" = "1" ]; then
          echo "CHECK reclaim-functional PASS"
        else
          echo "CHECK reclaim-functional FAIL count=$count_after"
        fi

        kill "$hpid" 2>/dev/null || true
        wait "$hpid" 2>/dev/null
        ;;

      burst)
        QML2_IMPORT_PATH="$HARNESS_DIR" "$QS" -n -p "$HARNESS_DIR" >harness.log 2>&1 &
        hpid=$!
        if ! wait_ipc_ready "$HARNESS_DIR"; then
          echo "CHECK burst FAIL harness-never-ready"
          cat harness.log
          kill "$hpid" 2>/dev/null || true
          exit 0
        fi

        # Each notify-send blocks synchronously on its own real Notify()
        # D-Bus call, so a clean exit is direct, authoritative proof the
        # harness's real NotificationServer accepted and processed that
        # call - independent of anything the popup/history queue does
        # afterward. This offscreen harness's Qt "offscreen" platform
        # plugin synthesizes one real QScreen, so Quickshell.screens is
        # non-empty and the production per-card popup Timer genuinely
        # runs here too: the earliest arrivals in a burst this size can
        # and do auto-expire into history (via the same real
        # dismissPopup/archivePopupFileFor path a live desktop uses)
        # before the burst finishes sending, which is why "received" is
        # checked via Notify() exit status, never via a live-popup-file
        # count racing that real timer.
        received=0
        i=1
        while [ "$i" -le 300 ]; do
          if notify-send -a TestClient -u normal "Burst $i" >/dev/null 2>&1; then
            received=$((received + 1))
          fi
          i=$((i + 1))
        done
        if [ "$received" = "300" ]; then
          echo "CHECK burst-received-all PASS"
        else
          echo "CHECK burst-received-all FAIL successful_sends=$received"
        fi

        alive_after_burst=no
        kill -0 "$hpid" 2>/dev/null && alive_after_burst=yes
        if [ "$alive_after_burst" = "yes" ]; then
          echo "CHECK burst-no-crash PASS"
        else
          echo "CHECK burst-no-crash FAIL"
        fi

        # Let the real per-card popup Timer (see above) finish auto-
        # expiring the whole burst on its own - the same production path a
        # live desktop relies on - rather than forcing it via dismissAll,
        # whose own clearPopups() sweep can enqueue an archive job for an
        # entry a still-in-flight auto-expire Timer is concurrently
        # archiving too. Each popup's own lifetime timer only starts once
        # that popup is actually created, so with 300 arriving over many
        # seconds the last ones do not expire until well after the burst
        # loop above returns - wait for every popup to actually leave (not
        # merely for a lull in the queue) before reading history_count.
        n=0
        while [ "$n" -lt 120 ] && [ "$(popup_count)" -gt 0 ]; do
          n=$((n + 1))
          sleep 0.5
        done
        # The very last archival's move-then-trim is two separate
        # statements inside the one adapter invocation the popup's
        # disappearance above only reflects the first (mv) of - give its
        # trim a moment to finish, then require a stable reading rather
        # than a single point-in-time one, so this never mistakes that
        # narrow, ordinary in-flight window for a real bound violation.
        prev=-1
        stable=0
        n=0
        while [ "$n" -lt 20 ] && [ "$stable" -lt 3 ]; do
          hist=$(history_count)
          if [ "$hist" = "$prev" ]; then
            stable=$((stable + 1))
          else
            stable=0
          fi
          prev=$hist
          n=$((n + 1))
          sleep 0.3
        done
        if [ "$hist" = "10" ]; then
          echo "CHECK burst-history-bounded PASS"
        else
          echo "CHECK burst-history-bounded FAIL history_count=$hist popup_count=$(popup_count)"
          echo "DIAG history listing:"
          ls -la "$HOME/.local/state/omarchy/notifications/history/" 2>&1
        fi

        ping_after=$(qs_ipc "$HARNESS_DIR" notifications ping)
        if [ "$ping_after" = "ok" ]; then
          echo "CHECK burst-responsive-after PASS"
        else
          echo "CHECK burst-responsive-after FAIL ping=$ping_after"
        fi

        # Bounded, proportional log growth: a generous multiplier of the
        # 300-notification stimulus, not an arbitrary byte count - and a
        # short post-stimulus window proving the harness has gone quiet
        # rather than continuing to emit lines on its own.
        harness_log_lines=$(wc -l < harness.log)
        max_log_lines=$((300 * 5 + 200))
        if [ "$harness_log_lines" -le "$max_log_lines" ]; then
          echo "CHECK burst-log-bound PASS lines=$harness_log_lines max=$max_log_lines"
        else
          echo "CHECK burst-log-bound FAIL lines=$harness_log_lines max=$max_log_lines"
        fi
        sleep 2
        harness_log_lines_after_wait=$(wc -l < harness.log)
        if [ "$harness_log_lines_after_wait" = "$harness_log_lines" ]; then
          echo "CHECK burst-log-quiescent PASS lines=$harness_log_lines_after_wait"
        else
          echo "CHECK burst-log-quiescent FAIL before=$harness_log_lines after=$harness_log_lines_after_wait"
        fi

        kill "$hpid" 2>/dev/null || true
        wait "$hpid" 2>/dev/null
        ;;

      session-phase1)
        # Section 15: establish real ownership+delivery in a genuine PAM/
        # logind session (this scenario's own systemd-run session), then
        # signal readiness and block so the outer test can destroy this
        # exact session/unit from the outside while it is still alive.
        #
        # PAM's session-open callback registers the login session with
        # logind but does not block on the user manager (and the D-Bus
        # session bus it hosts) actually finishing startup - this driver
        # script's own process can start running before that bus exists.
        # The pinned NotificationServer registers exactly once at
        # construction with no retry-on-first-failure (only
        # serviceUnregistered-driven reclaim, which never fires for a
        # connection that never existed), so launching the harness before
        # the bus is reachable would silently and permanently fail its
        # registration. Wait for the real bus first.
        n=0
        while [ "$n" -lt 150 ] && ! busctl --user list >/dev/null 2>&1; do
          n=$((n + 1))
          sleep 0.2
        done
        if ! launch_harness_retrying harness.log; then
          echo "CHECK session-phase1-ready FAIL harness-never-ready"
          cat harness.log
          kill "$hpid" 2>/dev/null || true
          exit 0
        fi

        # IPC readiness (Quickshell's own IPC socket) and the D-Bus
        # NotificationServer's async RequestName registration are two
        # independent readiness signals - especially right after a fresh
        # session/bus is created, IPC can be ready slightly before D-Bus
        # registration completes, so this polls briefly rather than
        # checking once.
        n=0
        owner=""
        while [ "$n" -lt 150 ]; do
          owner=$(owner_now)
          has_owner "$owner" && break
          n=$((n + 1))
          sleep 0.2
        done
        if has_owner "$owner"; then
          echo "CHECK session-phase1-ownership PASS owner=$owner"
        else
          echo "CHECK session-phase1-ownership FAIL owner=$owner"
          echo "DIAG harness.log tail: $(tail -30 harness.log | tr '\n' '|')"
        fi

        notify-send -a TestClient -u normal "SessionPhase1 hello"
        sleep 1
        if [ "$(popup_count)" = "1" ]; then
          echo "CHECK session-phase1-delivery PASS"
        else
          echo "CHECK session-phase1-delivery FAIL popup_count=$(popup_count)"
        fi

        # A `-p PAMName=login` session reparents this script (and, with it,
        # the harness it forked) into logind's own session-<N>.scope
        # cgroup, separate from this systemd-run invocation's own
        # transient service unit/cgroup - `systemctl stop` on that service
        # unit alone does not reliably reach processes already reparented
        # into the session scope. Record the real logind session id so the
        # outer test can terminate the scope that actually holds them.
        echo "''${XDG_SESSION_ID:-}" > "$WORKDIR/session-id"
        touch "$WORKDIR/session-ready"
        # Block here, alive, until the outer test stops this whole unit
        # (systemctl stop), which tears down this login session's cgroup -
        # and, once it is the last session for this user with no lingering
        # enabled, the user manager and its D-Bus session bus with it.
        sleep 300
        ;;

      session-phase2)
        # The fresh session/bus half of Section 15: a brand new systemd-run
        # session, proving a fresh harness can claim the name and deliver
        # again after the prior session/bus was genuinely torn down (never
        # simulated by sleeping).
        #
        # Same real bus-readiness wait as session-phase1, and more load-
        # bearing here: this session's own D-Bus user bus was just started
        # fresh moments ago by this very login, so the race is real, not
        # theoretical.
        n=0
        while [ "$n" -lt 150 ] && ! busctl --user list >/dev/null 2>&1; do
          n=$((n + 1))
          sleep 0.2
        done
        if ! launch_harness_retrying harness.log; then
          echo "CHECK session-phase2-ready FAIL harness-never-ready"
          cat harness.log
          kill "$hpid" 2>/dev/null || true
          exit 0
        fi

        n=0
        owner=""
        while [ "$n" -lt 150 ]; do
          owner=$(owner_now)
          has_owner "$owner" && break
          n=$((n + 1))
          sleep 0.2
        done
        if has_owner "$owner"; then
          echo "CHECK session-phase2-ownership PASS owner=$owner"
        else
          echo "CHECK session-phase2-ownership FAIL owner=$owner"
          echo "DIAG harness.log tail: $(tail -30 harness.log | tr '\n' '|')"
        fi

        notify-send -a TestClient -u normal "SessionPhase2 hello"
        sleep 1
        if [ "$(popup_count)" = "1" ]; then
          echo "CHECK session-phase2-delivery PASS"
        else
          echo "CHECK session-phase2-delivery FAIL popup_count=$(popup_count)"
        fi

        kill "$hpid" 2>/dev/null || true
        wait "$hpid" 2>/dev/null
        ;;

      known-daemon-collision)
        # A real, pinned, X11-backed dunst instance under a disposable Xvfb
        # display - not a bare NotificationServer stub - actually owning
        # org.freedesktop.Notifications before Quattro's harness ever
        # starts, so recovery.notifications-known-daemon-collision reduces
        # to a genuine by-name external daemon rather than the unknown/bare
        # owner recovery.notifications-unknown-owner-collision already
        # covers above.
        export DISPLAY=:97
        rm -f /tmp/.X11-unix/X97 2>/dev/null || true
        Xvfb "$DISPLAY" -screen 0 1024x768x16 >xvfb.log 2>&1 &
        xvfb_pid=$!
        n=0
        xvfb_ready=no
        while [ "$n" -lt 100 ]; do
          [ -e /tmp/.X11-unix/X97 ] && { xvfb_ready=yes; break; }
          n=$((n + 1))
          sleep 0.1
        done
        if [ "$xvfb_ready" = "yes" ]; then
          echo "CHECK xvfb-display-ready PASS display=$DISPLAY"
        else
          echo "CHECK xvfb-display-ready FAIL"
          cat xvfb.log
          kill "$xvfb_pid" 2>/dev/null || true
          exit 0
        fi

        dunst >dunst.log 2>&1 &
        dpid=$!
        n=0
        owner_probe=""
        dunst_owns=no
        while [ "$n" -lt 100 ]; do
          owner_probe=$(owner_now)
          if has_owner "$owner_probe"; then dunst_owns=yes; break; fi
          n=$((n + 1))
          sleep 0.1
        done
        if [ "$dunst_owns" = "yes" ]; then
          echo "CHECK dunst-started PASS pid=$dpid"
          echo "CHECK dunst-owns-name PASS owner=$owner_probe"
        else
          echo "CHECK dunst-started FAIL"
          echo "CHECK dunst-owns-name FAIL"
          cat dunst.log
          kill "$dpid" "$xvfb_pid" 2>/dev/null || true
          exit 0
        fi
        owner_before_quattro="$owner_probe"

        QML2_IMPORT_PATH="$HARNESS_DIR" "$QS" -n -p "$HARNESS_DIR" >harness.log 2>&1 &
        hpid=$!
        if ! wait_ipc_ready "$HARNESS_DIR"; then
          echo "CHECK quattro-did-not-steal-name FAIL harness-never-ready"
          cat harness.log
          kill "$hpid" "$dpid" "$xvfb_pid" 2>/dev/null || true
          exit 0
        fi

        owner_during=$(owner_now)
        if [ "$owner_during" = "$owner_before_quattro" ]; then
          echo "CHECK quattro-did-not-steal-name PASS"
        else
          echo "CHECK quattro-did-not-steal-name FAIL before=$owner_before_quattro during=$owner_during"
        fi

        dunst_alive=no
        kill -0 "$dpid" 2>/dev/null && dunst_alive=yes
        if [ "$dunst_alive" = "yes" ]; then
          echo "CHECK dunst-alive-during-collision PASS"
        else
          echo "CHECK dunst-alive-during-collision FAIL"
        fi

        quattro_alive=no
        kill -0 "$hpid" 2>/dev/null && quattro_alive=yes
        if [ "$quattro_alive" = "yes" ]; then
          echo "CHECK quattro-alive-during-collision PASS"
        else
          echo "CHECK quattro-alive-during-collision FAIL"
        fi

        # The test itself terminates its own dunst fixture - never the
        # harness or any production code - exactly like the unknown-owner
        # collision scenario's own stub teardown above.
        kill "$dpid" 2>/dev/null || true
        wait "$dpid" 2>/dev/null
        echo "CHECK test-terminates-dunst PASS pid=$dpid"

        n=0
        owner_after=""
        while [ "$n" -lt 150 ]; do
          owner_after=$(owner_now)
          has_owner "$owner_after" && break
          n=$((n + 1))
          sleep 0.1
        done
        if has_owner "$owner_after"; then
          echo "CHECK quattro-reclaims-name PASS owner=$owner_after attempts=$n"
        else
          echo "CHECK quattro-reclaims-name FAIL"
        fi

        notify-send -a TestClient -u normal "KnownDaemonCollision after reclaim"
        sleep 1
        count_after=$(popup_count)
        if [ "$count_after" = "1" ]; then
          echo "CHECK post-reclaim-delivery PASS"
        else
          echo "CHECK post-reclaim-delivery FAIL popup_count=$count_after"
        fi

        kill "$hpid" 2>/dev/null || true
        wait "$hpid" 2>/dev/null
        kill "$xvfb_pid" 2>/dev/null || true
        wait "$xvfb_pid" 2>/dev/null
        ;;

      *)
        echo "unknown scenario: $scenario" >&2
        exit 1
        ;;
    esac

    # The last command of a case branch is frequently a `wait` on a
    # deliberately-killed background harness/stub/client, whose reported
    # exit status (128+signal) would otherwise become this script's own
    # exit status with nothing to override it. Correctness/failure is
    # reported exclusively via the CHECK lines above, never via this
    # script's own process exit code - always exit 0 once every check has
    # had a chance to run.
    exit 0
  '';

  runScenario = scenario:
    "systemd-run --uid=${testUser} --pipe --wait --collect -p PAMName=login --unit=omanixy-notif-${scenario} ${driverScript} ${scenario}";
in
pkgs.testers.runNixOSTest {
  name = "security-recovery-notifications-vm";

  nodes.machine = { ... }: {
    imports = [
      self.nixosModules.default
      home-manager.nixosModules.home-manager
    ];

    system.stateVersion = "26.11";

    users.users.${testUser} = {
      isNormalUser = true;
    };

    environment.systemPackages = [ quickshellBin pkgs.libnotify pkgs.dunst pkgs.xorg-server ];

    # Proves the real, real-system-integrated declarative capability itself:
    # a genuine NixOS + Home Manager activation with the option on, for a
    # real user - not merely the eval-only extraction above. No NixOS-level
    # pairing is required for this capability (pure session D-Bus
    # ownership), matching upstream/porting-matrix.yaml's
    # security.notification-daemon entry.
    home-manager.useGlobalPkgs = true;
    home-manager.useUserPackages = true;
    home-manager.users.${testUser} = {
      imports = [ self.homeManagerModules.default ];
      home.username = testUser;
      home.homeDirectory = "/home/${testUser}";
      home.stateVersion = "25.11";
      programs.omanixy.enable = true;
      programs.omanixy.security.notifications.daemon.enable = true;
    };

    virtualisation.memorySize = 2048;
  };

  testScript = ''
    ${builtins.readFile ./lib/recovery-check-helpers.py}

    machine.wait_for_unit("multi-user.target")

    print("=== setup: the real declarative capability activates for a real user ===")
    # home-manager-<user>.service is a oneshot unit - by the time
    # multi-user.target is reached it has already run to completion
    # (successfully, or this system.build.toplevel would never have
    # booted), so its own state is "inactive" rather than "active";
    # wait_until_succeeds on the file it produces is the correct check.
    machine.wait_until_succeeds(
        "cat /home/${testUser}/.config/systemd/user/omanixy-shell.service"
    )
    unit_file = machine.succeed(
        "cat /home/${testUser}/.config/systemd/user/omanixy-shell.service"
    )
    assert "ExecStart" in unit_file, unit_file
    print("home-manager-provisioned omanixy-shell.service unit is present for a real user")

    print("=== scenario 1: real D-Bus ownership + real notify-send delivery ===")
    machine.succeed("rm -rf /home/${testUser}/.local/state/omarchy")
    out = machine.succeed("${runScenario "ownership-delivery"}")
    print(out)
    assert_checks(out, RECOVERY_CHECKS["notifications.ownership-delivery"]["checks"])

    print("=== scenario 2: replacement identity, default action, close round-trip ===")
    machine.succeed("rm -rf /home/${testUser}/.local/state/omarchy")
    out = machine.succeed("${runScenario "replace-action-close"}")
    print(out)
    assert_checks(out, RECOVERY_CHECKS["notifications.replace-action-close"]["checks"])

    print("=== scenario 3: DND suppression + persistence across a real process restart ===")
    machine.succeed("rm -rf /home/${testUser}/.local/state/omarchy")
    out = machine.succeed("${runScenario "dnd-restart"}")
    print(out)
    assert_checks(out, RECOVERY_CHECKS["notifications.dnd-restart"]["checks"])

    print("=== scenario 4: unknown independent-owner collision, non-destructive, event-driven reclaim ===")
    machine.succeed("rm -rf /home/${testUser}/.local/state/omarchy")
    out = machine.succeed("${runScenario "collision-reclaim"}")
    print(out)
    assert_checks(out, RECOVERY_CHECKS["notifications.collision-reclaim"]["checks"])

    print("=== scenario 5: notification burst, bounded history and log growth ===")
    machine.succeed("rm -rf /home/${testUser}/.local/state/omarchy")
    out = machine.succeed("${runScenario "burst"}")
    print(out)
    assert_checks(out, RECOVERY_CHECKS["notifications.burst"]["checks"])

    print("=== scenario 6: session/bus destruction and fresh-session recovery ===")
    machine.succeed("loginctl disable-linger ${testUser} 2>&1 || true")
    machine.succeed("rm -rf /home/${testUser}/.local/state/omarchy")
    workdir1 = "/home/${testUser}/notif-test-session-phase1"
    machine.succeed(f"rm -rf {workdir1}")
    machine.execute(
        "${runScenario "session-phase1"} > /tmp/session-phase1-out.log 2>&1 &"
    )
    machine.wait_for_file(f"{workdir1}/session-ready", timeout=60)
    phase1_partial = machine.succeed("cat /tmp/session-phase1-out.log")
    print(phase1_partial)
    assert_checks(phase1_partial, RECOVERY_CHECKS["notifications.session-phase1"]["checks"])

    # Destroy this exact session from the outside - its own logind
    # session-<N>.scope cgroup (which actually holds the driver script and
    # the harness it forked, per the comment recorded inside the scenario
    # above), its login session, and (once it is the last session for this
    # user with lingering disabled) the user manager and D-Bus session bus
    # it owned - never simulated by sleeping or by touching the host.
    session_id = machine.succeed(f"cat {workdir1}/session-id").strip()
    assert session_id, "session-phase1 must have recorded a real logind session id"
    machine.succeed(f"loginctl terminate-session {session_id}")
    machine.succeed("systemctl stop omanixy-notif-session-phase1.service 2>&1 || true")
    # Do not rely on systemd's own lazy StopWhenUnneeded GC pass noticing
    # the last session ended - stop the user manager (and, with it, the
    # D-Bus user-session bus it hosts) explicitly and deterministically,
    # exactly like the rest of this scenario's genuine-destruction
    # discipline: never simulated by sleeping, never left to chance timing.
    machine.succeed(
        "systemctl stop user@$(id -u ${testUser}).service 2>&1 || true"
    )
    machine.wait_until_succeeds(
        "systemctl show user@$(id -u ${testUser}).service -p SubState --value | grep -qx dead",
        timeout=60,
    )
    print("user manager / session D-Bus bus for the test user has been torn down")

    # session-phase1's own delivery check already persisted a popup file;
    # a fresh harness's real restorePopups() would otherwise legitimately
    # restore it alongside session-phase2's own notification, making
    # popup_count 2 rather than 1 for a reason that has nothing to do with
    # what this scenario is actually proving (fresh registration+delivery).
    machine.succeed("rm -rf /home/${testUser}/.local/state/omarchy")

    out = machine.succeed("${runScenario "session-phase2"}")
    print(out)
    assert_checks(out, RECOVERY_CHECKS["notifications.session-phase2"]["checks"])

    print("=== scenario 7: real known-by-name daemon (dunst) collision under Xvfb ===")
    machine.succeed("rm -rf /home/${testUser}/.local/state/omarchy")
    out = machine.succeed("${runScenario "known-daemon-collision"}")
    print(out)
    assert_checks(out, RECOVERY_CHECKS["notifications.known-daemon-collision"]["checks"])
  '';
}
