{ pkgs, self, home-manager }:
let
  lib = pkgs.lib;
  system = pkgs.stdenv.hostPlatform.system;

  testUser = "omanixy-recovery-test";

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
  notifStateBinDir = "${runtimePkg.passthru.compatibilityBin}/bin";

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
    owner_unique() { printf '%s\n' "$1" | sed -n 's/^s "\(:[^"]*\)"$/\1/p'; }
    owner_pid_for() {
      local unique=$1
      [ -z "$unique" ] && return 1
      busctl --user call org.freedesktop.DBus /org/freedesktop/DBus \
        org.freedesktop.DBus GetConnectionUnixProcessID s "$unique" 2>/dev/null \
        | sed -n 's/^u \([0-9]\+\)$/\1/p'
    }
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

        n=0
        while [ "$n" -lt 120 ] && [ "$(popup_count)" -gt 0 ]; do
          n=$((n + 1))
          sleep 0.5
        done
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

        echo "''${XDG_SESSION_ID:-}" > "$WORKDIR/session-id"
        touch "$WORKDIR/session-ready"
        sleep 300
        ;;

      session-phase2)
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
        else
          echo "CHECK dunst-started FAIL"
          echo "CHECK dunst-owns-name FAIL no-owner"
          cat dunst.log
          kill "$dpid" "$xvfb_pid" 2>/dev/null || true
          exit 0
        fi
        owner_before_quattro="$owner_probe"

        dunst_unique=$(owner_unique "$owner_before_quattro")
        dunst_owner_pid=$(owner_pid_for "$dunst_unique")
        dunst_exe=$(readlink -f "/proc/$dunst_owner_pid/exe" 2>/dev/null || true)
        if [ -n "$dunst_owner_pid" ] && [ "$dunst_owner_pid" = "$dpid" ]; then
          echo "CHECK dunst-owns-name PASS unique=$dunst_unique pid=$dunst_owner_pid exe=$dunst_exe"
        else
          echo "CHECK dunst-owns-name FAIL unique=$dunst_unique owner_pid=$dunst_owner_pid dunst_pid=$dpid exe=$dunst_exe"
          kill "$dpid" "$xvfb_pid" 2>/dev/null || true
          exit 0
        fi

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

        during_unique=$(owner_unique "$owner_during")
        during_owner_pid=$(owner_pid_for "$during_unique")
        if [ -n "$during_owner_pid" ] && [ "$during_owner_pid" = "$dpid" ]; then
          echo "CHECK dunst-owns-name-pid-stable PASS pid=$during_owner_pid"
        else
          echo "CHECK dunst-owns-name-pid-stable FAIL pid=$during_owner_pid dunst_pid=$dpid"
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

        after_unique=$(owner_unique "$owner_after")
        after_owner_pid=$(owner_pid_for "$after_unique")
        if [ -n "$after_owner_pid" ] && [ "$after_owner_pid" = "$hpid" ] \
          && [ -n "$after_unique" ] && [ "$after_unique" != "$dunst_unique" ]; then
          echo "CHECK quattro-reclaims-name-pid PASS pid=$after_owner_pid unique=$after_unique"
        else
          echo "CHECK quattro-reclaims-name-pid FAIL pid=$after_owner_pid hpid=$hpid unique=$after_unique dunst_unique=$dunst_unique"
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
    assert_scenario(out, "notifications.ownership-delivery")

    print("=== scenario 2: replacement identity, default action, close round-trip ===")
    machine.succeed("rm -rf /home/${testUser}/.local/state/omarchy")
    out = machine.succeed("${runScenario "replace-action-close"}")
    print(out)
    assert_scenario(out, "notifications.replace-action-close")

    print("=== scenario 3: DND suppression + persistence across a real process restart ===")
    machine.succeed("rm -rf /home/${testUser}/.local/state/omarchy")
    out = machine.succeed("${runScenario "dnd-restart"}")
    print(out)
    assert_scenario(out, "notifications.dnd-restart")

    print("=== scenario 4: unknown independent-owner collision, non-destructive, event-driven reclaim ===")
    machine.succeed("rm -rf /home/${testUser}/.local/state/omarchy")
    out = machine.succeed("${runScenario "collision-reclaim"}")
    print(out)
    assert_scenario(out, "notifications.collision-reclaim")

    print("=== scenario 5: notification burst, bounded history and log growth ===")
    machine.succeed("rm -rf /home/${testUser}/.local/state/omarchy")
    out = machine.succeed("${runScenario "burst"}")
    print(out)
    assert_scenario(out, "notifications.burst")

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
    assert_scenario(phase1_partial, "notifications.session-phase1")

    session_id = machine.succeed(f"cat {workdir1}/session-id").strip()
    assert session_id, "session-phase1 must have recorded a real logind session id"
    machine.succeed(f"loginctl terminate-session {session_id}")
    machine.succeed("systemctl stop omanixy-notif-session-phase1.service 2>&1 || true")
    machine.succeed(
        "systemctl stop user@$(id -u ${testUser}).service 2>&1 || true"
    )
    machine.wait_until_succeeds(
        "systemctl show user@$(id -u ${testUser}).service -p SubState --value | grep -qx dead",
        timeout=60,
    )
    print("user manager / session D-Bus bus for the test user has been torn down")

    machine.succeed("rm -rf /home/${testUser}/.local/state/omarchy")

    out = machine.succeed("${runScenario "session-phase2"}")
    print(out)
    assert_scenario(out, "notifications.session-phase2")

    print("=== scenario 7: real known-by-name daemon (dunst) collision under Xvfb ===")
    machine.succeed("rm -rf /home/${testUser}/.local/state/omarchy")
    out = machine.succeed("${runScenario "known-daemon-collision"}")
    print(out)
    assert_scenario(out, "notifications.known-daemon-collision")
  '';
}
