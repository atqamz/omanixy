# Layer 8 (security-recovery) real-backend evidence for the security.polkit-agent
# ledger entry's `required_before_promotion` list (upstream/porting-matrix.yaml).
#
# Layer 5 (programs.omanixy.security.polkit.system.enable /
# programs.omanixy.security.polkit.agent.enable, modules/nixos/default.nix and
# modules/home/default.nix) proved the declarative capability and the pinned
# Quickshell PolkitAgent/AuthFlow ABI hermetically: offscreen QML against a
# deterministic fake agent object (test/security-polkit-qml-behavior.sh) and a
# real polkitd/D-Bus registration was never exercised. This file boots a real
# NixOS VM with both options enabled, a real `polkitd`, and a minimal offscreen
# Quickshell harness that instantiates the exact same, unmodified
# `Quickshell.Services.Polkit.PolkitAgent { path: "/org/omarchy/PolkitAgent" }`
# object the production, patched `PolkitAgent.qml` uses - built from the exact
# same pinned `quickshell-omanixy` derivation
# (`self.packages.<system>.omanixy-shell.passthru.quickshell`) production runs,
# so this exercises the real ABI, not a reimplementation of it. No nested
# Wayland/Hyprland session is needed: only the agent's own presentation UI (a
# PanelWindow) requires one, and this harness never instantiates a PanelWindow.
#
# The harness is driven live via Quickshell's own IPC mechanism
# (`quickshell ipc call -- polkit <function>`), the same real mechanism
# `packages/omanixy-shell/ipc-wrapper.bash` uses in production, from inside a
# genuine systemd-logind session for a disposable VM-only test user (obtained
# via `systemd-run --uid=<user> -p PAMName=login`, the same session-registration
# mechanism a real login/display-manager session uses) - required because the
# pinned Quickshell polkit listener registers itself against
# `polkit_unix_session_new_for_process(getpid())`, i.e. against whichever
# logind session contains the agent's own process.
{ pkgs, self, home-manager }:
let
  lib = pkgs.lib;
  system = pkgs.stdenv.hostPlatform.system;

  # The exact pinned quickshell-omanixy derivation production builds and runs
  # (packages/omanixy-shell/default.nix's `quickshell` binding), reused as-is
  # rather than refetched, so the harness runs under the identical ABI/module
  # set production does.
  quickshellBin = self.packages.${system}.omanixy-shell.passthru.quickshell;

  testUser = "omanixy-recovery-test";
  testPassword = "omanixy-recovery-test-fixture-password";
  wrongPassword = "omanixy-recovery-test-fixture-password-wrong";
  testActionId = "org.omanixy.test.security-recovery";

  # A minimal, test-harness-only QML fixture: only the real, unmodified
  # PolkitAgent object plus an IpcHandler used to drive it from the test
  # script. Deliberately not the production compat root's patched
  # PolkitAgent.qml (which additionally renders a PanelWindow presentation
  # this scope does not need) - this is the "no nested compositor needed"
  # minimal harness the layer 8 scope calls for, instantiating the exact same
  # native Quickshell.Services.Polkit.PolkitAgent type production uses.
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

      PolkitAgent {
        id: agent
        path: "${dbusPath}"

        onIsRegisteredChanged: console.log("HARNESS_EVENT isRegisteredChanged " + isRegistered)
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
            daemonCancelCount: root.daemonCancelCount
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

  # The real Quattro-shaped agent under test, registering at the real
  # /org/omarchy/PolkitAgent path production uses.
  harnessDir = pkgs.writeTextDir "shell.qml" (mkAgentQml {
    dbusPath = "/org/omarchy/PolkitAgent";
    ipcTarget = "polkit";
  });

  # A trivial, genuinely-separate second D-Bus agent registration used only by
  # the collision scenario - a real independent registration (not the
  # declarative hyprpolkitagent/polkit-gnome conflict, which is already
  # covered by test/security-polkit-hm.sh), never stopped/killed/masked by the
  # harness under test.
  # D-Bus object path segments only allow [A-Za-z0-9_] - no hyphens - so this
  # deliberately does not reuse a hyphenated name; an earlier version of this
  # fixture used "/org/omanixy-test-rival/Agent" and
  # polkit_agent_listener_register_with_options rejected it via a
  # g_variant_is_object_path assertion, which registerComplete never observed
  # as an error, making the rival silently never really occupy the session's
  # agent slot (a spurious "no collision" result, not a real one).
  rivalDir = pkgs.writeTextDir "shell.qml" (mkAgentQml {
    dbusPath = "/org/omanixy_test_rival/Agent";
    ipcTarget = "rival";
  });

  # polkitd's backend refuses to check authorization for any action id that
  # is not registered in its action pool (parsed from *.policy files under
  # its --datadir, which on NixOS resolves to
  # /run/current-system/sw/share/polkit-1/actions via
  # environment.pathsToLink - see pkgs.polkit's mesonFlags): an unregistered
  # action id fails immediately with "Action ... is not registered", before
  # any JS rule or agent is ever consulted. security.polkit.extraConfig's
  # addRule alone is therefore not sufficient; this test-only .policy file
  # registers the action id security.polkit.extraConfig's rule keys on.
  # Test-only: never installed by modules/ or packages/.
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

    echo "SESSION_INFO session=''${XDG_SESSION_ID:-unset} $(loginctl session-status "''${XDG_SESSION_ID:-}" 2>&1 | head -3 | tr '\n' ';')"

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

    case "$scenario" in
      register)
        "$QS" -n -p "$HARNESS_DIR" >harness.log 2>&1 &
        hpid=$!
        if wait_for "$HARNESS_DIR" polkit '.isRegistered == true' 60; then
          echo "RESULT register ok"
        else
          echo "RESULT register fail"
          cat harness.log
        fi
        kill "$hpid" 2>/dev/null || true
        ;;

      auth)
        "$QS" -n -p "$HARNESS_DIR" >harness.log 2>&1 &
        hpid=$!
        if ! wait_for "$HARNESS_DIR" polkit '.isRegistered == true' 60; then
          echo "RESULT auth register-failed"
          cat harness.log
          kill "$hpid" 2>/dev/null || true
          exit 0
        fi

        "$PKCHECK" -a "$ACTION_ID" -u -p $$ >pkcheck1.log 2>&1 &
        p1=$!
        if ! wait_for "$HARNESS_DIR" polkit '.isResponseRequired == true' 40; then
          echo "RESULT auth no-prompt"
          cat harness.log
          cat pkcheck1.log
          kill "$p1" 2>/dev/null || true
          kill "$hpid" 2>/dev/null || true
          exit 0
        fi

        qs_call "$HARNESS_DIR" polkit submit "$WRONG_PASSWORD" >/dev/null
        if wait_for "$HARNESS_DIR" polkit '.failedCount == 1' 20; then
          wrong_result=ok
        else
          wrong_result=no-failure-signal
        fi
        after_wrong=$(qs_status "$HARNESS_DIR" polkit)
        echo "RESULT auth-wrongpass $wrong_result status=$after_wrong"

        if wait_for "$HARNESS_DIR" polkit '.isResponseRequired == true' 20; then
          qs_call "$HARNESS_DIR" polkit submit "$FIXTURE_PASSWORD" >/dev/null
          wait "$p1"
          pkexit=$?
          after_success=$(qs_status "$HARNESS_DIR" polkit)
          echo "RESULT auth-success pkcheck_exit=$pkexit status=$after_success"
        else
          echo "RESULT auth-success no-reprompt-after-failure"
          kill "$p1" 2>/dev/null || true
        fi
        kill "$hpid" 2>/dev/null || true
        ;;

      user-cancel)
        "$QS" -n -p "$HARNESS_DIR" >harness.log 2>&1 &
        hpid=$!
        if ! wait_for "$HARNESS_DIR" polkit '.isRegistered == true' 60; then
          echo "RESULT user-cancel register-failed"
          kill "$hpid" 2>/dev/null || true
          exit 0
        fi
        "$PKCHECK" -a "$ACTION_ID" -u -p $$ >pkcheck.log 2>&1 &
        p1=$!
        if ! wait_for "$HARNESS_DIR" polkit '.isActive == true' 40; then
          echo "RESULT user-cancel no-request"
          cat harness.log
          cat pkcheck.log
          kill "$p1" 2>/dev/null || true
          kill "$hpid" 2>/dev/null || true
          exit 0
        fi
        qs_call "$HARNESS_DIR" polkit cancel >/dev/null
        wait "$p1"
        pkexit=$?
        wait_for "$HARNESS_DIR" polkit '.isActive == false' 20
        final=$(qs_status "$HARNESS_DIR" polkit)
        echo "RESULT user-cancel pkcheck_exit=$pkexit status=$final"
        kill "$hpid" 2>/dev/null || true
        ;;

      daemon-cancel)
        "$QS" -n -p "$HARNESS_DIR" >harness.log 2>&1 &
        hpid=$!
        if ! wait_for "$HARNESS_DIR" polkit '.isRegistered == true' 60; then
          echo "RESULT daemon-cancel register-failed"
          kill "$hpid" 2>/dev/null || true
          exit 0
        fi
        "$PKCHECK" -a "$ACTION_ID" -u -p $$ >pkcheck.log 2>&1 &
        p1=$!
        if ! wait_for "$HARNESS_DIR" polkit '.isResponseRequired == true' 40; then
          echo "RESULT daemon-cancel no-prompt"
          cat harness.log
          cat pkcheck.log
          kill "$p1" 2>/dev/null || true
          kill "$hpid" 2>/dev/null || true
          exit 0
        fi
        kill -TERM "$p1" 2>/dev/null || true
        wait "$p1" 2>/dev/null
        ok=no
        if wait_for "$HARNESS_DIR" polkit '.isActive == false' 40; then ok=yes; fi
        final=$(qs_status "$HARNESS_DIR" polkit)
        echo "RESULT daemon-cancel bounded=$ok status=$final"
        kill "$hpid" 2>/dev/null || true
        ;;

      collision)
        "$QS" -n -p "$RIVAL_DIR" >rival.log 2>&1 &
        rpid=$!
        if ! wait_for "$RIVAL_DIR" rival '.isRegistered == true' 60; then
          echo "RESULT collision rival-register-failed"
          cat rival.log
          kill "$rpid" 2>/dev/null || true
          exit 0
        fi

        "$QS" -n -p "$HARNESS_DIR" >harness1.log 2>&1 &
        h1pid=$!
        sleep 5
        h1_status=$(qs_status "$HARNESS_DIR" polkit)
        rival_status=$(qs_status "$RIVAL_DIR" rival)
        rival_alive=no
        kill -0 "$rpid" 2>/dev/null && rival_alive=yes
        echo "RESULT collision harness1=$h1_status rival=$rival_status rival_alive=$rival_alive"
        echo "DIAG rival.log: $(tr '\n' '|' < rival.log)"
        echo "DIAG harness1.log: $(tr '\n' '|' < harness1.log)"

        sleep 5
        h1_status_no_retry=$(qs_status "$HARNESS_DIR" polkit)
        echo "RESULT collision-no-retry harness1=$h1_status_no_retry"

        rival_alive_before_stop=no
        kill -0 "$rpid" 2>/dev/null && rival_alive_before_stop=yes
        echo "RESULT collision-rival-untouched rival_alive_before_we_stop_it=$rival_alive_before_stop"
        kill "$rpid" 2>/dev/null || true
        wait "$rpid" 2>/dev/null

        sleep 3
        h1_after_rival_gone=$(qs_status "$HARNESS_DIR" polkit)
        echo "RESULT collision-stale harness1=$h1_after_rival_gone"

        kill "$h1pid" 2>/dev/null || true
        wait "$h1pid" 2>/dev/null

        "$QS" -n -p "$HARNESS_DIR" >harness2.log 2>&1 &
        h2pid=$!
        if wait_for "$HARNESS_DIR" polkit '.isRegistered == true' 60; then
          echo "RESULT collision-fresh ok"
        else
          echo "RESULT collision-fresh fail"
        fi
        kill "$h2pid" 2>/dev/null || true
        ;;

      daemon-restart)
        "$QS" -n -p "$HARNESS_DIR" >harness.log 2>&1 &
        hpid=$!
        if ! wait_for "$HARNESS_DIR" polkit '.isRegistered == true' 60; then
          echo "RESULT daemon-restart register-failed"
          kill "$hpid" 2>/dev/null || true
          exit 0
        fi

        "$PKCHECK" -a "$ACTION_ID" -u -p $$ >pkcheck1.log 2>&1 &
        p1=$!
        if ! wait_for "$HARNESS_DIR" polkit '.isResponseRequired == true' 40; then
          echo "RESULT daemon-restart no-prompt"
          cat harness.log
          cat pkcheck1.log
          kill "$p1" 2>/dev/null || true
          kill "$hpid" 2>/dev/null || true
          exit 0
        fi

        touch "$WORKDIR/inflight-ready"

        n=0
        while kill -0 "$p1" 2>/dev/null && [ "$n" -lt 60 ]; do
          sleep 0.5
          n=$((n + 1))
        done
        if kill -0 "$p1" 2>/dev/null; then
          echo "RESULT daemon-restart-inflight hung"
          kill "$p1" 2>/dev/null || true
        else
          wait "$p1"
          echo "RESULT daemon-restart-inflight bounded exit=$?"
        fi

        "$PKCHECK" -a "$ACTION_ID" -u -p $$ >pkcheck2.log 2>&1 &
        p2=$!
        if wait_for "$HARNESS_DIR" polkit '.isResponseRequired == true' 15; then
          qs_call "$HARNESS_DIR" polkit submit "$FIXTURE_PASSWORD" >/dev/null
          wait "$p2"
          echo "RESULT daemon-restart-same-harness reprompted exit=$?"
        else
          echo "RESULT daemon-restart-same-harness stale-no-prompt"
          kill "$p2" 2>/dev/null || true
        fi

        kill "$hpid" 2>/dev/null || true
        wait "$hpid" 2>/dev/null

        "$QS" -n -p "$HARNESS_DIR" >harness-fresh.log 2>&1 &
        hf=$!
        if wait_for "$HARNESS_DIR" polkit '.isRegistered == true' 60; then
          "$PKCHECK" -a "$ACTION_ID" -u -p $$ >pkcheck3.log 2>&1 &
          p3=$!
          if wait_for "$HARNESS_DIR" polkit '.isResponseRequired == true' 40; then
            qs_call "$HARNESS_DIR" polkit submit "$FIXTURE_PASSWORD" >/dev/null
            wait "$p3"
            echo "RESULT daemon-restart-fresh-harness ok exit=$?"
          else
            echo "RESULT daemon-restart-fresh-harness no-prompt"
            kill "$p3" 2>/dev/null || true
          fi
        else
          echo "RESULT daemon-restart-fresh-harness register-failed"
        fi
        kill "$hf" 2>/dev/null || true
        ;;

      *)
        echo "unknown scenario: $scenario" >&2
        exit 1
        ;;
    esac
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

    # Test-only action definition: not installed by modules/ or packages/,
    # lives entirely in this test file. AUTH_SELF requires authentication as
    # the disposable VM-only test user itself (never a real user, never an
    # admin/wheel identity), matching the ledger's "real polkit authentication
    # success/wrong-password against the real backend" evidence requirement.
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
    machine.wait_for_unit("multi-user.target")
    machine.wait_for_unit("polkit.service")

    print("=== scenario 1: real registration ===")
    print(machine.succeed("${runScenario "register"}"))

    print("=== scenario 2: real authentication success + wrong-password failure ===")
    print(machine.succeed("${runScenario "auth"}"))

    print("=== scenario 3a: user-initiated cancellation ===")
    print(machine.succeed("${runScenario "user-cancel"}"))

    print("=== scenario 3b: daemon-initiated cancellation ===")
    print(machine.succeed("${runScenario "daemon-cancel"}"))

    print("=== scenario 4: registration collision with an independent agent ===")
    print(machine.succeed("${runScenario "collision"}"))

    print("=== scenario 5: polkitd disappearance/recovery during an in-flight request ===")
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
    print(machine.succeed("cat /tmp/daemon-restart-out.log"))
  '';
}
