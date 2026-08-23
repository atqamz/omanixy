{ pkgs, self, home-manager }:
let
  lib = pkgs.lib;
  system = pkgs.stdenv.hostPlatform.system;

  quickshellBin = self.packages.${system}.omanixy-shell.passthru.quickshell;

  testUser = "omanixy-recovery-test";
  testPassword = "omanixy-recovery-test-fixture-password";
  wrongPassword = "omanixy-recovery-test-fixture-password-wrong";
  testActionId = "org.omanixy.test.security-recovery";

  mkAgentQml = { dbusPath, ipcTarget }: ''
    import QtQuick
    import Quickshell
    import Quickshell.Io
    import Quickshell.Services.Polkit

    ShellRoot {
      id: root
      property int succeededCount: 0
      property int failedCount: 0
      property int daemonCancelCount: 0
      property int registeredTrueCount: 0

      PolkitAgent {
        id: agent
        path: "${dbusPath}"

        onIsRegisteredChanged: {
          console.log("HARNESS_EVENT isRegisteredChanged " + isRegistered)
          if (isRegistered) root.registeredTrueCount += 1
        }
        onIsActiveChanged: console.log("HARNESS_EVENT isActiveChanged " + isActive)
        onAuthenticationRequestStarted: console.log("HARNESS_EVENT authenticationRequestStarted")
        onFlowChanged: {
          if (agent.flow) {
            agent.flow.isResponseRequiredChanged.connect(function() {
              console.log("HARNESS_EVENT isResponseRequiredChanged " + agent.flow.isResponseRequired + " prompt=" + agent.flow.inputPrompt)
            })
            agent.flow.authenticationSucceeded.connect(function() {
              root.succeededCount += 1
              console.log("HARNESS_EVENT authenticationSucceeded")
            })
            agent.flow.authenticationFailed.connect(function() {
              root.failedCount += 1
              console.log("HARNESS_EVENT authenticationFailed")
            })
            agent.flow.authenticationRequestCancelled.connect(function() {
              root.daemonCancelCount += 1
              console.log("HARNESS_EVENT authenticationRequestCancelled")
            })
          }
        }
      }

      IpcHandler {
        target: "${ipcTarget}"

        function status(): string {
          return JSON.stringify({
            isRegistered: agent.isRegistered,
            isActive: agent.isActive,
            isResponseRequired: agent.flow ? agent.flow.isResponseRequired : false,
            inputPrompt: agent.flow ? agent.flow.inputPrompt : "",
            actionId: agent.flow ? agent.flow.actionId : "",
            succeededCount: root.succeededCount,
            failedCount: root.failedCount,
            daemonCancelCount: root.daemonCancelCount,
            registeredTrueCount: root.registeredTrueCount
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

      Component.onCompleted: console.log("HARNESS_READY")
    }
  '';

  harnessDir = pkgs.writeTextDir "shell.qml" (mkAgentQml {
    dbusPath = "/org/omarchy/PolkitAgent";
    ipcTarget = "polkit";
  });

  rivalDir = pkgs.writeTextDir "shell.qml" (mkAgentQml {
    dbusPath = "/org/omanixy_test_rival/Agent";
    ipcTarget = "rival";
  });

  testActionPolicy = pkgs.runCommand "omanixy-test-action-policy" { } ''
    mkdir -p "$out/share/polkit-1/actions"
    cat > "$out/share/polkit-1/actions/${testActionId}.policy" <<EOF
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE policyconfig PUBLIC "-//freedesktop//DTD PolicyKit Policy Configuration 1.0//EN" "http://www.freedesktop.org/standards/PolicyKit/1/policyconfig.dtd">
    <policyconfig>
      <action id="${testActionId}">
        <description>Omanixy layer 8 security-recovery polkit VM test action</description>
        <message>Authentication is required for the Omanixy layer 8 polkit VM test</message>
        <defaults>
          <allow_any>no</allow_any>
          <allow_inactive>no</allow_inactive>
          <allow_active>auth_self</allow_active>
        </defaults>
      </action>
    </policyconfig>
    EOF
  '';

  driverScript = pkgs.writeShellScript "omanixy-polkit-vm-driver" ''
    set -u
    QS="${quickshellBin}/bin/quickshell"
    PKCHECK="${pkgs.polkit.bin}/bin/pkcheck"
    JQ="${pkgs.jq}/bin/jq"
    HARNESS_DIR="${harnessDir}"
    RIVAL_DIR="${rivalDir}"
    ACTION_ID="${testActionId}"
    FIXTURE_PASSWORD="${testPassword}"
    WRONG_PASSWORD="${wrongPassword}"

    export HOME="/home/${testUser}"
    export XDG_RUNTIME_DIR="/run/user/$(id -u)"
    export QT_QPA_PLATFORM=offscreen

    scenario="$1"
    WORKDIR="$HOME/polkit-test-$scenario"
    rm -rf "$WORKDIR"
    mkdir -p "$WORKDIR"
    cd "$WORKDIR"

    echo "DIAG session=''${XDG_SESSION_ID:-unset} $(loginctl session-status "''${XDG_SESSION_ID:-}" 2>&1 | head -3 | tr '\n' ';')"

    qs_status() { timeout 5 "$QS" ipc -p "$1" call -- "$2" status 2>/dev/null; }
    qs_call() { local dir=$1 target=$2 fn=$3; shift 3; timeout 5 "$QS" ipc -p "$dir" call -- "$target" "$fn" "$@" 2>/dev/null; }
    wait_for() {
      local dir=$1 target=$2 expr=$3 limit=''${4:-40} n=0 val
      while [ "$n" -lt "$limit" ]; do
        val=$(qs_status "$dir" "$target")
        if [ -n "$val" ] && printf '%s' "$val" | "$JQ" -e "$expr" >/dev/null 2>&1; then
          return 0
        fi
        n=$((n + 1))
        sleep 0.5
      done
      return 1
    }
    check() {
      local name=$1 ok=$2; shift 2
      if [ "$ok" = "yes" ]; then
        echo "CHECK $name PASS $*"
      else
        echo "CHECK $name FAIL $*"
      fi
    }

    case "$scenario" in

      register)
        rival_running=$(pgrep -fc 'qu[i]ckshell.*-p .*rival' 2>/dev/null || true)
        [ "''${rival_running:-0}" = "0" ] && check rival-absent yes || check rival-absent no "rival_running=$rival_running"

        polkitd_state=$(systemctl is-active polkit.service 2>&1)
        [ "$polkitd_state" = "active" ] && check polkitd-active yes "$polkitd_state" || check polkitd-active no "$polkitd_state"

        "$QS" -n -p "$HARNESS_DIR" >harness.log 2>&1 &
        hpid=$!
        if wait_for "$HARNESS_DIR" polkit '.isRegistered == true' 60; then
          check registered yes
        else
          check registered no
          cat harness.log
        fi

        registered_events=$(grep -c 'HARNESS_EVENT isRegisteredChanged true' harness.log || true)
        [ "''${registered_events:-0}" = "1" ] && check single-registration-event yes || check single-registration-event no "count=$registered_events"

        kill -0 "$hpid" 2>/dev/null && check harness-alive yes || check harness-alive no
        kill "$hpid" 2>/dev/null || true
        wait "$hpid" 2>/dev/null
        ;;

      auth)
        "$QS" -n -p "$HARNESS_DIR" >harness.log 2>&1 &
        hpid=$!
        if wait_for "$HARNESS_DIR" polkit '.isRegistered == true' 60; then
          check agent-registered yes
        else
          check agent-registered no
          cat harness.log
          kill "$hpid" 2>/dev/null || true
          exit 0
        fi

        "$PKCHECK" -a "$ACTION_ID" -u -p $$ >pkcheck1.log 2>&1 &
        p1=$!
        if wait_for "$HARNESS_DIR" polkit '.isResponseRequired == true' 40; then
          check request-created yes
        else
          check request-created no
          cat harness.log
          cat pkcheck1.log
          kill "$p1" "$hpid" 2>/dev/null || true
          exit 0
        fi

        qs_call "$HARNESS_DIR" polkit submit "$WRONG_PASSWORD" >/dev/null
        if wait_for "$HARNESS_DIR" polkit '.failedCount == 1' 20; then
          check wrong-password-failure yes
        else
          check wrong-password-failure no "$(qs_status "$HARNESS_DIR" polkit)"
        fi

        if wait_for "$HARNESS_DIR" polkit '.isResponseRequired == true' 20; then
          check reprompt-after-failure yes
        else
          check reprompt-after-failure no
          kill "$p1" "$hpid" 2>/dev/null || true
          exit 0
        fi

        qs_call "$HARNESS_DIR" polkit submit "$FIXTURE_PASSWORD" >/dev/null
        wait "$p1"
        pkexit=$?
        [ "$pkexit" = "0" ] && check pkcheck-exit-zero yes || check pkcheck-exit-zero no "exit=$pkexit"

        if wait_for "$HARNESS_DIR" polkit '.succeededCount == 1' 20; then
          check correct-password-success yes
        else
          check correct-password-success no "$(qs_status "$HARNESS_DIR" polkit)"
        fi

        if wait_for "$HARNESS_DIR" polkit '.isActive == false' 20; then
          check flow-inactive-after yes
        else
          check flow-inactive-after no "$(qs_status "$HARNESS_DIR" polkit)"
        fi

        kill "$hpid" 2>/dev/null || true
        wait "$hpid" 2>/dev/null
        ;;

      user-cancel)
        "$QS" -n -p "$HARNESS_DIR" >harness.log 2>&1 &
        hpid=$!
        if ! wait_for "$HARNESS_DIR" polkit '.isRegistered == true' 60; then
          check request-active no "register-failed"
          kill "$hpid" 2>/dev/null || true
          exit 0
        fi
        "$PKCHECK" -a "$ACTION_ID" -u -p $$ >pkcheck.log 2>&1 &
        p1=$!
        if wait_for "$HARNESS_DIR" polkit '.isActive == true' 40; then
          check request-active yes
        else
          check request-active no
          cat harness.log
          cat pkcheck.log
          kill "$p1" "$hpid" 2>/dev/null || true
          exit 0
        fi

        cancel_result=$(qs_call "$HARNESS_DIR" polkit cancel)
        [ "$cancel_result" = "cancelled" ] && check user-cancel-invoked yes || check user-cancel-invoked no "result=$cancel_result"

        wait "$p1"
        pkexit=$?
        [ "$pkexit" != "0" ] && check requester-bounded yes "exit=$pkexit" || check requester-bounded no "exit=$pkexit"

        if wait_for "$HARNESS_DIR" polkit '.isActive == false' 20; then
          check flow-inactive-after-cancel yes
        else
          check flow-inactive-after-cancel no
        fi

        final=$(qs_status "$HARNESS_DIR" polkit)
        printf '%s' "$final" | "$JQ" -e '.isResponseRequired == false' >/dev/null 2>&1 \
          && check no-stale-prompt yes "$final" || check no-stale-prompt no "$final"

        kill -0 "$hpid" 2>/dev/null && check harness-alive-after-cancel yes || check harness-alive-after-cancel no
        kill "$hpid" 2>/dev/null || true
        ;;

      daemon-cancel)
        "$QS" -n -p "$HARNESS_DIR" >harness.log 2>&1 &
        hpid=$!
        if ! wait_for "$HARNESS_DIR" polkit '.isRegistered == true' 60; then
          check request-active no "register-failed"
          kill "$hpid" 2>/dev/null || true
          exit 0
        fi
        "$PKCHECK" -a "$ACTION_ID" -u -p $$ >pkcheck.log 2>&1 &
        p1=$!
        if wait_for "$HARNESS_DIR" polkit '.isResponseRequired == true' 40; then
          check request-active yes
        else
          check request-active no
          cat harness.log
          cat pkcheck.log
          kill "$p1" "$hpid" 2>/dev/null || true
          exit 0
        fi

        kill -TERM "$p1" 2>/dev/null
        cancel_sent=$?
        [ "$cancel_sent" = "0" ] && check daemon-cancel-stimulus yes || check daemon-cancel-stimulus no "kill_exit=$cancel_sent"
        wait "$p1" 2>/dev/null

        if wait_for "$HARNESS_DIR" polkit '.isActive == false' 40; then
          check flow-inactive-after-daemon-cancel yes
        else
          check flow-inactive-after-daemon-cancel no
        fi

        final=$(qs_status "$HARNESS_DIR" polkit)
        printf '%s' "$final" | "$JQ" -e '.isResponseRequired == false' >/dev/null 2>&1 \
          && check no-stale-request yes "$final" || check no-stale-request no "$final"

        kill -0 "$hpid" 2>/dev/null && check no-shell-restart yes || check no-shell-restart no
        kill "$hpid" 2>/dev/null || true
        ;;

      collision)
        "$QS" -n -p "$RIVAL_DIR" >rival.log 2>&1 &
        rpid=$!
        if wait_for "$RIVAL_DIR" rival '.isRegistered == true' 60; then
          check rival-registered yes
        else
          check rival-registered no
          cat rival.log
          kill "$rpid" 2>/dev/null || true
          exit 0
        fi

        "$QS" -n -p "$HARNESS_DIR" >harness1.log 2>&1 &
        h1pid=$!
        sleep 5
        h1_status=$(qs_status "$HARNESS_DIR" polkit)
        printf '%s' "$h1_status" | "$JQ" -e '.isRegistered == false' >/dev/null 2>&1 \
          && check quattro-not-registered yes "$h1_status" || check quattro-not-registered no "$h1_status"

        rival_status=$(qs_status "$RIVAL_DIR" rival)
        rival_alive=no
        kill -0 "$rpid" 2>/dev/null && rival_alive=yes
        [ "$rival_alive" = "yes" ] && printf '%s' "$rival_status" | "$JQ" -e '.isRegistered == true' >/dev/null 2>&1 \
          && check rival-remains-registered yes "$rival_status" || check rival-remains-registered no "alive=$rival_alive status=$rival_status"

        sleep 5
        h1_status_no_retry=$(qs_status "$HARNESS_DIR" polkit)
        printf '%s' "$h1_status_no_retry" | "$JQ" -e '.isRegistered == false' >/dev/null 2>&1 \
          && check no-retry-while-rival-present yes "$h1_status_no_retry" || check no-retry-while-rival-present no "$h1_status_no_retry"

        kill -0 "$rpid" 2>/dev/null
        rival_alive_before_stop=$?
        kill "$rpid" 2>/dev/null
        term_exit=$?
        wait "$rpid" 2>/dev/null
        { [ "$rival_alive_before_stop" = "0" ] && [ "$term_exit" = "0" ]; } \
          && check test-terminates-rival yes || check test-terminates-rival no "was_alive=$rival_alive_before_stop term_exit=$term_exit"

        sleep 3
        h1_after_rival_gone=$(qs_status "$HARNESS_DIR" polkit)
        printf '%s' "$h1_after_rival_gone" | "$JQ" -e '.isRegistered == false' >/dev/null 2>&1 \
          && check quattro-remains-unregistered-after-rival-gone yes "$h1_after_rival_gone" \
          || check quattro-remains-unregistered-after-rival-gone no "$h1_after_rival_gone"

        kill "$h1pid" 2>/dev/null || true
        wait "$h1pid" 2>/dev/null

        "$QS" -n -p "$HARNESS_DIR" >harness2.log 2>&1 &
        h2pid=$!
        if wait_for "$HARNESS_DIR" polkit '.isRegistered == true' 60; then
          check fresh-quattro-registers yes
        else
          check fresh-quattro-registers no
        fi
        kill "$h2pid" 2>/dev/null || true
        ;;

      stress)
        "$QS" -n -p "$HARNESS_DIR" >harness.log 2>&1 &
        hpid=$!
        if ! wait_for "$HARNESS_DIR" polkit '.isRegistered == true' 60; then
          check stress-20-cycles-completed no "register-failed"
          check stress-single-harness-process no "register-failed"
          check stress-log-bound no "register-failed"
          check stress-no-continued-growth no "register-failed"
          check stress-final-correct-auth no "register-failed"
          cat harness.log
          kill "$hpid" 2>/dev/null || true
          exit 0
        fi

        unix_chkpwd_before=$(pgrep -c unix_chkpwd 2>/dev/null); unix_chkpwd_before=''${unix_chkpwd_before:-0}
        cycles_ok=0
        n=1
        while [ "$n" -le 20 ]; do
          "$PKCHECK" -a "$ACTION_ID" -u -p $$ >"pkcheck-$n.log" 2>&1 &
          pn=$!
          cycle_failed_once=no
          attempt=0
          while [ "$attempt" -lt 6 ] && wait_for "$HARNESS_DIR" polkit '.isResponseRequired == true' 20; do
            before_failed=$(qs_status "$HARNESS_DIR" polkit | "$JQ" -r '.failedCount')
            qs_call "$HARNESS_DIR" polkit submit "$WRONG_PASSWORD" >/dev/null
            attempt=$((attempt + 1))
            if wait_for "$HARNESS_DIR" polkit ".failedCount == $((before_failed + 1))" 20; then
              cycle_failed_once=yes
            fi
          done
          kill "$pn" 2>/dev/null || true
          wait "$pn" 2>/dev/null
          [ "$cycle_failed_once" = "yes" ] && cycles_ok=$((cycles_ok + 1))
          n=$((n + 1))
        done
        [ "$cycles_ok" = "20" ] && check stress-20-cycles-completed yes || check stress-20-cycles-completed no "cycles_ok=$cycles_ok"

        procs=$(pgrep -fc 'qu[i]ckshell -n -p' || true)
        [ "$procs" = "1" ] && check stress-single-harness-process yes || check stress-single-harness-process no "procs=$procs"

        events=$(grep -c '^HARNESS_EVENT' harness.log || true)
        max_events=$((20 * 6 * 10 + 50))
        [ "''${events:-0}" -le "$max_events" ] \
          && check stress-log-bound yes "events=$events max=$max_events" \
          || check stress-log-bound no "events=$events max=$max_events"

        sleep 2
        events_after_wait=$(grep -c '^HARNESS_EVENT' harness.log || true)
        [ "$events_after_wait" = "$events" ] \
          && check stress-no-continued-growth yes "events=$events events_after_wait=$events_after_wait" \
          || check stress-no-continued-growth no "events=$events events_after_wait=$events_after_wait"

        unix_chkpwd_after=$(pgrep -c unix_chkpwd 2>/dev/null); unix_chkpwd_after=''${unix_chkpwd_after:-0}
        echo "DIAG unix_chkpwd before=$unix_chkpwd_before after=$unix_chkpwd_after"

        "$PKCHECK" -a "$ACTION_ID" -u -p $$ >pkcheck-final.log 2>&1 &
        pf=$!
        if wait_for "$HARNESS_DIR" polkit '.isResponseRequired == true' 20; then
          qs_call "$HARNESS_DIR" polkit submit "$FIXTURE_PASSWORD" >/dev/null
          wait "$pf"
          pfexit=$?
          [ "$pfexit" = "0" ] && check stress-final-correct-auth yes || check stress-final-correct-auth no "exit=$pfexit"
        else
          check stress-final-correct-auth no "no-prompt"
          kill "$pf" 2>/dev/null || true
        fi

        kill "$hpid" 2>/dev/null || true
        ;;

      daemon-restart)
        "$QS" -n -p "$HARNESS_DIR" >harness.log 2>&1 &
        hpid=$!
        if ! wait_for "$HARNESS_DIR" polkit '.isRegistered == true' 60; then
          check request-active-before-restart no "register-failed"
          kill "$hpid" 2>/dev/null || true
          exit 0
        fi

        "$PKCHECK" -a "$ACTION_ID" -u -p $$ >pkcheck1.log 2>&1 &
        p1=$!
        if wait_for "$HARNESS_DIR" polkit '.isResponseRequired == true' 40; then
          check request-active-before-restart yes
        else
          check request-active-before-restart no
          cat harness.log
          cat pkcheck1.log
          kill "$p1" "$hpid" 2>/dev/null || true
          exit 0
        fi

        touch "$WORKDIR/inflight-ready"

        n=0
        while kill -0 "$p1" 2>/dev/null && [ "$n" -lt 60 ]; do
          sleep 0.5
          n=$((n + 1))
        done
        if kill -0 "$p1" 2>/dev/null; then
          check inflight-requester-bounded no "still-running-after-30s"
          kill "$p1" 2>/dev/null || true
        else
          wait "$p1"
          check inflight-requester-bounded yes "exit=$?"
        fi

        "$PKCHECK" -a "$ACTION_ID" -u -p $$ >pkcheck2.log 2>&1 &
        p2=$!
        if wait_for "$HARNESS_DIR" polkit '.isResponseRequired == true' 15; then
          qs_call "$HARNESS_DIR" polkit submit "$FIXTURE_PASSWORD" >/dev/null
          wait "$p2"
          p2exit=$?
          [ "$p2exit" = "0" ] && check same-harness-reprompt yes "exit=$p2exit" || check same-harness-reprompt no "exit=$p2exit"
        else
          check same-harness-reprompt no "stale-no-prompt"
          kill "$p2" 2>/dev/null || true
        fi

        kill "$hpid" 2>/dev/null || true
        wait "$hpid" 2>/dev/null

        "$QS" -n -p "$HARNESS_DIR" >harness-fresh.log 2>&1 &
        hf=$!
        if wait_for "$HARNESS_DIR" polkit '.isRegistered == true' 60; then
          check fresh-harness-registers yes
          "$PKCHECK" -a "$ACTION_ID" -u -p $$ >pkcheck3.log 2>&1 &
          p3=$!
          if wait_for "$HARNESS_DIR" polkit '.isResponseRequired == true' 40; then
            qs_call "$HARNESS_DIR" polkit submit "$FIXTURE_PASSWORD" >/dev/null
            wait "$p3"
            p3exit=$?
            [ "$p3exit" = "0" ] && check fresh-harness-auth-success yes "exit=$p3exit" || check fresh-harness-auth-success no "exit=$p3exit"
          else
            check fresh-harness-auth-success no "no-prompt"
            kill "$p3" 2>/dev/null || true
          fi
        else
          check fresh-harness-registers no
          check fresh-harness-auth-success no "register-failed"
        fi
        kill "$hf" 2>/dev/null || true
        ;;

      *)
        echo "unknown scenario: $scenario" >&2
        exit 1
        ;;
    esac

    exit 0
  '';

  runScenario = scenario:
    "systemd-run --uid=${testUser} --pipe --wait --collect -p PAMName=login --unit=omanixy-polkit-${scenario} ${driverScript} ${scenario}";
in
pkgs.testers.runNixOSTest {
  name = "security-recovery-polkit-vm";

  nodes.machine = { ... }: {
    imports = [
      self.nixosModules.default
      home-manager.nixosModules.home-manager
    ];

    system.stateVersion = "26.11";

    programs.omanixy.security.polkit.system.enable = true;

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

    environment.systemPackages = [ quickshellBin pkgs.jq testActionPolicy ];

    home-manager.useGlobalPkgs = true;
    home-manager.useUserPackages = true;
    home-manager.users.${testUser} = {
      imports = [ self.homeManagerModules.default ];
      home.username = testUser;
      home.homeDirectory = "/home/${testUser}";
      home.stateVersion = "25.11";
      programs.omanixy.enable = true;
      programs.omanixy.security.polkit.agent.enable = true;
    };

    virtualisation.memorySize = 2048;
  };

  testScript = ''
    ${builtins.readFile ./lib/recovery-check-helpers.py}

    machine.wait_for_unit("multi-user.target")
    machine.wait_for_unit("polkit.service")

    print("=== scenario 1: real registration ===")
    out = machine.succeed("${runScenario "register"}")
    print(out)
    assert_scenario(out, "polkit.register")

    print("=== scenario 2: real authentication success + wrong-password failure ===")
    out = machine.succeed("${runScenario "auth"}")
    print(out)
    assert_scenario(out, "polkit.auth")

    print("=== scenario 3a: user-initiated cancellation ===")
    out = machine.succeed("${runScenario "user-cancel"}")
    print(out)
    assert_scenario(out, "polkit.user-cancel")

    print("=== scenario 3b: daemon-initiated cancellation ===")
    out = machine.succeed("${runScenario "daemon-cancel"}")
    print(out)
    assert_scenario(out, "polkit.daemon-cancel")

    print("=== scenario 4: registration collision with an independent agent ===")
    out = machine.succeed("${runScenario "collision"}")
    print(out)
    assert_scenario(out, "polkit.collision")

    print("=== scenario 5: finite real wrong-password stress (20 cycles) ===")
    out = machine.succeed("${runScenario "stress"}")
    print(out)
    assert_scenario(out, "polkit.stress")

    print("=== scenario 6: polkitd disappearance/recovery during an in-flight request ===")
    workdir = "/home/${testUser}/polkit-test-daemon-restart"
    machine.succeed(f"rm -rf {workdir}")
    machine.execute(
        "${runScenario "daemon-restart"} > /tmp/daemon-restart-out.log 2>&1 &"
    )
    machine.wait_for_file(f"{workdir}/inflight-ready", timeout=60)
    machine.succeed("systemctl restart polkit.service")
    machine.wait_until_succeeds(
        "systemctl show omanixy-polkit-daemon-restart.service -p SubState --value | grep -qx dead",
        timeout=90,
    )
    out = machine.succeed("cat /tmp/daemon-restart-out.log")
    print(out)
    assert_scenario(out, "polkit.daemon-restart")
  '';
}
