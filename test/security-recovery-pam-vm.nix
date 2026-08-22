{ pkgs, self, home-manager }:

let
  system = pkgs.system;
  quickshell = self.packages.${system}.omanixy-shell.passthru.quickshell;
  harnessQml = ./security-recovery-pam-harness.qml;
  testUser = "omanixy-recovery-test";
  testUserPassword = "omanixy-recovery-test-fixture";
in
pkgs.testers.runNixOSTest {
  name = "security-recovery-pam-vm";

  nodes.machine = { ... }: {
    imports = [ self.nixosModules.default home-manager.nixosModules.home-manager ];

    programs.omanixy.security.pam.password.enable = true;

    users.users.${testUser} = {
      isNormalUser = true;
      password = testUserPassword;
    };

    environment.etc."omanixy/pam-harness.qml".source = harnessQml;

    home-manager.useGlobalPkgs = true;
    home-manager.useUserPackages = true;
    home-manager.users.${testUser} = {
      imports = [ self.homeManagerModules.default ];
      home.username = testUser;
      home.homeDirectory = "/home/${testUser}";
      home.stateVersion = "25.11";
      programs.omanixy.enable = true;
    };
  };

  nodes.fingerprintMachine = { ... }: {
    imports = [ self.nixosModules.default ];

    programs.omanixy.security.pam.password.enable = true;
    programs.omanixy.security.pam.fingerprint.enable = true;

    users.users.${testUser} = {
      isNormalUser = true;
      password = testUserPassword;
    };

    environment.etc."omanixy/pam-harness.qml".source = harnessQml;
  };

  testScript = ''
    ${builtins.readFile ./lib/recovery-check-helpers.py}

    import json
    import shlex
    import time

    start_all()

    machine.wait_for_unit("multi-user.target")
    machine.succeed("id ${testUser}")
    machine.succeed("loginctl enable-linger ${testUser}")
    uid = machine.succeed("id -u ${testUser}").strip()
    machine.wait_for_unit(f"user@{uid}.service")
    machine.execute(f"su -l ${testUser} -c 'XDG_RUNTIME_DIR=/run/user/{uid} systemctl --user daemon-reload'")

    def run_su(machine_ref, m_uid, inner):
        inner_full = f"XDG_RUNTIME_DIR=/run/user/{m_uid} {inner}"
        cmd = f"su -l ${testUser} -c {shlex.quote(inner_full)}"
        return machine_ref.execute(cmd)

    def run_harness(machine_ref, m_uid, mode, config, password="", wrong_password="", repeat_count=None, extra_timeout=30, watchdog_ms=None):
        env = {
            "HARNESS_MODE": mode,
            "HARNESS_PAM_CONFIG": config,
            "HARNESS_PAM_USER": "${testUser}",
            "HARNESS_PASSWORD": password,
            "HARNESS_WRONG_PASSWORD": wrong_password,
            "HARNESS_WATCHDOG_MS": str(watchdog_ms if watchdog_ms is not None else max(25000, (extra_timeout - 5) * 1000)),
        }
        if repeat_count is not None:
            env["HARNESS_REPEAT_COUNT"] = str(repeat_count)
        env_str = " ".join(f"{k}={shlex.quote(v)}" for k, v in env.items())
        inner = (
            f"{env_str} QT_QPA_PLATFORM=offscreen "
            f"timeout {extra_timeout} ${quickshell}/bin/quickshell -n -p /etc/omanixy/pam-harness.qml"
        )
        return run_su(machine_ref, m_uid, inner)

    def leftover_quickshell(machine_ref):
        return int(machine_ref.succeed("pgrep -fc 'qu[i]ckshell -n -p' || true").strip() or "0")

    class Checks:
        def __init__(self):
            self.lines = []

        def record(self, name, ok, detail=""):
            state = "PASS" if ok else "FAIL"
            self.lines.append(f"CHECK {name} {state} {detail}".rstrip())
            return ok

        def finish(self, scenario_id):
            output = "\n".join(self.lines)
            print(output)
            assert_scenario(output, scenario_id)
            self.lines = []

    c = Checks()
    status, output = run_harness(machine, uid, "single", "omarchy-lock-password", password="${testUserPassword}")
    print("=== SCENARIO 1a: correct password ===")
    print(output)
    c.record("correct-password-success", "HARNESS_DONE completed:Success" in output)

    status, output = run_harness(machine, uid, "single", "omarchy-lock-password", password="definitely-wrong-password")
    print("=== SCENARIO 1b: wrong password ===")
    print(output)
    c.record("wrong-password-failure", "HARNESS_DONE completed:Failed" in output)
    c.finish("pam-password.live-conversation")

    c = Checks()
    unix_chkpwd_baseline = int(machine.succeed("pgrep -c unix_chkpwd || true").strip() or "0")
    print(f"unix_chkpwd baseline before repeat scenario: {unix_chkpwd_baseline}")

    t0 = time.time()
    status, output = run_harness(
        machine, uid, "repeat", "omarchy-lock-password",
        password="${testUserPassword}", wrong_password="definitely-wrong-password",
        repeat_count=20, extra_timeout=280, watchdog_ms=270000,
    )
    elapsed = time.time() - t0
    print("=== SCENARIO 2: 20 wrong attempts then correct ===")
    print(f"elapsed={elapsed:.1f}s")
    print(output)
    c.record("repeat-final-success", "HARNESS_DONE repeat-final:Success" in output)

    attempt_lines = [l for l in output.splitlines() if "HARNESS_EVENT attempt" in l]
    event_lines = [l for l in output.splitlines() if "HARNESS_EVENT" in l]
    max_events = 20 * 8 + 20
    c.record(
        "attempt-count-bound", 20 <= len(attempt_lines) <= 21,
        f"attempts={len(attempt_lines)}",
    )
    c.record(
        "event-volume-bound", len(event_lines) <= max_events,
        f"events={len(event_lines)} max={max_events}",
    )

    proc_count = int(machine.succeed("pgrep -c unix_chkpwd || true").strip() or "0")
    print(f"unix_chkpwd helper processes immediately after repeat scenario: {proc_count}")
    c.record("helper-no-growth-immediate", proc_count <= unix_chkpwd_baseline, f"count={proc_count} baseline={unix_chkpwd_baseline}")

    time.sleep(2)
    proc_count_after_wait = int(machine.succeed("pgrep -c unix_chkpwd || true").strip() or "0")
    print(f"unix_chkpwd helper processes after a 2s post-stimulus observation window: {proc_count_after_wait}")
    c.record("helper-no-growth-after-wait", proc_count_after_wait == proc_count, f"{proc_count} -> {proc_count_after_wait}")
    c.finish("pam-password.repeated-failure")

    c = Checks()
    t0 = time.time()
    status, output = run_harness(machine, uid, "cancel", "omarchy-lock-password", watchdog_ms=15000, extra_timeout=20)
    elapsed = time.time() - t0
    print("=== SCENARIO 3: cancel mid-conversation ===")
    print(f"elapsed={elapsed:.1f}s")
    print(output)
    c.record("abort-event", "HARNESS_EVENT abort" in output)
    c.record("not-success", "HARNESS_DONE completed:Success" not in output)
    c.record("not-ordinary-failure", "HARNESS_DONE completed:Failed" not in output)
    c.record("aborted-active-false", "HARNESS_DONE aborted-active-false" in output)
    c.record("bounded-elapsed", elapsed < 10, f"elapsed={elapsed:.1f}s")
    leftover = leftover_quickshell(machine)
    print(f"leftover quickshell processes immediately after cancel: {leftover}")
    c.record("no-orphan-process", leftover == 0, f"leftover={leftover}")
    c.finish("pam-password.cancel")

    c = Checks()
    machine.fail("test -e /etc/pam.d/omarchy-lock-fingerprint")
    status, output = run_harness(machine, uid, "single", "omarchy-lock-fingerprint", password="irrelevant")
    print("=== SCENARIO 4: missing PAM service ===")
    print(output)
    c.record("service-absent", True)
    c.record("not-ordinary-failure", "HARNESS_DONE completed:Failed" not in output)
    c.record(
        "start-failed-distinct",
        "HARNESS_EVENT start-failed" in output or "HARNESS_EVENT error StartFailed" in output,
    )
    c.finish("pam-password.missing-service")

    fingerprintMachine.wait_for_unit("multi-user.target")
    fingerprintMachine.succeed("id ${testUser}")
    fuid = fingerprintMachine.succeed("id -u ${testUser}").strip()
    fingerprintMachine.succeed("loginctl enable-linger ${testUser}")
    fingerprintMachine.wait_for_unit(f"user@{fuid}.service")

    def fprintd_manager_call(machine_ref, method, timeout_s=15):
        return machine_ref.execute(
            f"timeout {timeout_s} busctl --json=short call net.reactivated.Fprint "
            f"/net/reactivated/Fprint/Manager net.reactivated.Fprint.Manager {method}"
        )

    outage_dropin = "/run/systemd/system/fprintd.service.d/99-recovery-test-outage.conf"

    def induce_outage(machine_ref):
        machine_ref.succeed(f"mkdir -p {outage_dropin.rsplit('/', 1)[0]}")
        machine_ref.succeed(
            "printf '[Service]\\nExecStart=\\nExecStart=/run/current-system/sw/bin/false\\n' "
            f"> {outage_dropin}"
        )
        machine_ref.succeed("systemctl daemon-reload")

    def restore_outage(machine_ref):
        machine_ref.succeed(f"rm -f {outage_dropin}")
        machine_ref.succeed("systemctl daemon-reload")
        machine_ref.succeed("systemctl reset-failed fprintd.service 2>&1 || true")

    def get_devices(machine_ref, timeout_s=15):
        status, out = fprintd_manager_call(machine_ref, "GetDevices", timeout_s)
        devices = None
        if status == 0:
            try:
                devices = json.loads(out.strip().splitlines()[-1])["data"][0]
            except Exception:
                devices = None
        return status, out, devices

    c = Checks()
    c.record(
        "pam-service-exists",
        fingerprintMachine.execute("test -e /etc/pam.d/omarchy-lock-fingerprint")[0] == 0,
    )
    is_enabled = fingerprintMachine.succeed("systemctl is-enabled fprintd.service 2>&1 || true").strip()
    print(f"fprintd.service is-enabled: {is_enabled!r}")
    c.record("fprintd-enable-false", is_enabled != "enabled", f"is-enabled={is_enabled!r}")

    activatable = fingerprintMachine.succeed(
        "busctl call org.freedesktop.DBus /org/freedesktop/DBus org.freedesktop.DBus ListActivatableNames"
    )
    c.record(
        "dbus-activation-surface-exists",
        "net.reactivated.Fprint" in activatable,
        f"activatable_names_contains_fprint={'net.reactivated.Fprint' in activatable}",
    )

    status, out, devices = get_devices(fingerprintMachine)
    print("=== FINGERPRINT A: real backend, no device - GetDevices ===")
    print(f"status={status}")
    print(out)
    c.record("manager-responds", status == 0, f"status={status}")
    active_state = fingerprintMachine.succeed("systemctl show fprintd.service -p ActiveState --value").strip()
    print(f"fprintd.service ActiveState after GetDevices: {active_state}")
    c.record("backend-activated", active_state == "active", f"ActiveState={active_state}")
    c.record("get-devices-empty", devices == [], f"devices={devices!r}")

    t0 = time.time()
    status, output = run_harness(fingerprintMachine, fuid, "single", "omarchy-lock-fingerprint", password="irrelevant", extra_timeout=30)
    elapsed = time.time() - t0
    print("=== FINGERPRINT A: fingerprint conversation against the real no-device backend ===")
    print(f"elapsed={elapsed:.1f}s")
    print(output)
    c.record("fingerprint-never-success", "HARNESS_DONE completed:Success" not in output)
    c.record("fingerprint-bounded", elapsed < 25, f"elapsed={elapsed:.1f}s")

    status, output = run_harness(fingerprintMachine, fuid, "single", "omarchy-lock-password", password="${testUserPassword}")
    print("=== FINGERPRINT A: password still available ===")
    print(output)
    c.record("password-still-works", "HARNESS_DONE completed:Success" in output)
    c.finish("fingerprint.no-device")

    c = Checks()
    owner_before_outage = fingerprintMachine.execute(
        "busctl call org.freedesktop.DBus /org/freedesktop/DBus org.freedesktop.DBus GetNameOwner s net.reactivated.Fprint 2>&1"
    )[1]
    print(f"name owner before outage stimulus: {owner_before_outage!r}")

    fingerprintMachine.succeed("systemctl stop fprintd.service 2>&1 || true")
    deadline = time.time() + 30
    stop_state = None
    while time.time() < deadline:
        stop_state = fingerprintMachine.succeed(
            "systemctl show fprintd.service -p ActiveState --value"
        ).strip()
        if stop_state in ("inactive", "failed", "dead"):
            break
        time.sleep(1)
    print(f"fprintd.service ActiveState after stop: {stop_state}")
    fingerprintMachine.succeed("pkill -9 -f '/libexec/fprint[d]' 2>&1 || true")

    induce_outage(fingerprintMachine)

    status, out, devices = get_devices(fingerprintMachine, timeout_s=10)
    print("=== FINGERPRINT B: backend deliberately unavailable - GetDevices ===")
    print(f"status={status}")
    print(out)
    c.record("backend-genuinely-unavailable", status != 0, f"status={status}")

    t0 = time.time()
    status, output = run_harness(fingerprintMachine, fuid, "single", "omarchy-lock-fingerprint", password="irrelevant", extra_timeout=30)
    elapsed = time.time() - t0
    print("=== FINGERPRINT B: fingerprint conversation against the unavailable backend ===")
    print(f"elapsed={elapsed:.1f}s")
    print(output)
    c.record("fingerprint-never-success", "HARNESS_DONE completed:Success" not in output)
    c.record("fingerprint-bounded-failure", elapsed < 25, f"elapsed={elapsed:.1f}s")
    leftover = leftover_quickshell(fingerprintMachine)
    print(f"leftover quickshell processes after the outage attempt: {leftover}")
    c.record("no-runaway-retry", leftover == 0, f"leftover={leftover}")

    status, output = run_harness(fingerprintMachine, fuid, "single", "omarchy-lock-password", password="${testUserPassword}")
    print("=== FINGERPRINT B: password still available during the outage ===")
    print(output)
    c.record("password-still-works", "HARNESS_DONE completed:Success" in output)
    c.finish("fingerprint.backend-unavailable")

    c = Checks()
    restore_outage(fingerprintMachine)

    status, out, devices = get_devices(fingerprintMachine)
    print("=== FINGERPRINT C: backend restored - GetDevices ===")
    print(f"status={status}")
    print(out)
    c.record("backend-restored", status == 0, f"status={status}")
    c.record("manager-responds-again", status == 0, f"status={status}")
    c.record("get-devices-empty-again", devices == [], f"devices={devices!r}")

    t0 = time.time()
    status, output = run_harness(fingerprintMachine, fuid, "single", "omarchy-lock-fingerprint", password="irrelevant", extra_timeout=30)
    elapsed = time.time() - t0
    print("=== FINGERPRINT C: fresh fingerprint conversation after recovery ===")
    print(f"elapsed={elapsed:.1f}s")
    print(output)
    c.record("fingerprint-bounded-again", elapsed < 25 and "HARNESS_DONE completed:Success" not in output, f"elapsed={elapsed:.1f}s")

    status, output = run_harness(fingerprintMachine, fuid, "single", "omarchy-lock-password", password="${testUserPassword}")
    print("=== FINGERPRINT C: password still available after recovery ===")
    print(output)
    c.record("password-still-works-again", "HARNESS_DONE completed:Success" in output)
    c.finish("fingerprint.backend-recovery")

    c = Checks()
    fingerprintMachine.succeed("systemctl stop fprintd.service 2>&1 || true")
    fingerprintMachine.succeed("pkill -9 -f '/libexec/fprint[d]' 2>&1 || true")
    induce_outage(fingerprintMachine)

    def journal_cursor(machine_ref, unit):
        out = machine_ref.succeed(f"journalctl -u {unit} --no-pager -n 0 --show-cursor 2>&1").strip()
        return out.splitlines()[-1].split("cursor:", 1)[1].strip()

    def journal_count_since(machine_ref, unit, cursor):
        out = machine_ref.execute(
            f"journalctl -u {unit} --no-pager --after-cursor={shlex.quote(cursor)} 2>&1"
        )[1]
        return len([l for l in out.splitlines() if l.strip()])

    backend_baseline_cursor = journal_cursor(fingerprintMachine, "fprintd.service")

    stress_attempts = 0
    stress_successes = 0
    for i in range(20):
        status, output = run_harness(fingerprintMachine, fuid, "single", "omarchy-lock-fingerprint", password="irrelevant", extra_timeout=25, watchdog_ms=20000)
        stress_attempts += 1
        if "HARNESS_DONE completed:Success" in output:
            stress_successes += 1
    print(f"=== FINGERPRINT D: finite outage stress - {stress_attempts} attempts, {stress_successes} successes ===")

    c.record("stress-20-attempts-completed", stress_attempts == 20, f"attempts={stress_attempts}")
    c.record("stress-zero-success", stress_successes == 0, f"successes={stress_successes}")

    leftover = leftover_quickshell(fingerprintMachine)
    print(f"leftover quickshell processes immediately after the stress run: {leftover}")

    backend_events = journal_count_since(fingerprintMachine, "fprintd.service", backend_baseline_cursor)
    max_backend_events = 20 * 20 + 100
    print(f"fprintd.service journal events since baseline: {backend_events} (max {max_backend_events})")
    c.record("stress-backend-log-bound", backend_events <= max_backend_events, f"events={backend_events} max={max_backend_events}")

    time.sleep(2)
    leftover_after_wait = leftover_quickshell(fingerprintMachine)
    backend_events_after_wait = journal_count_since(fingerprintMachine, "fprintd.service", backend_baseline_cursor)
    print(f"leftover quickshell processes after a 2s post-stimulus observation window: {leftover_after_wait}")
    print(f"fprintd.service journal events after the same window: {backend_events_after_wait}")
    c.record("stress-no-runaway-retry", leftover_after_wait == leftover, f"{leftover} -> {leftover_after_wait}")
    c.record("stress-backend-log-quiescent", backend_events_after_wait == backend_events, f"before={backend_events} after={backend_events_after_wait}")

    c.record("stress-no-quickshell-process", leftover_after_wait == 0, f"leftover_after_wait={leftover_after_wait}")
    fprintd_procs = int(fingerprintMachine.succeed("pgrep -c '/libexec/fprint[d]' 2>&1 || true").strip() or "0")
    print(f"real fprintd processes alive after the stress run: {fprintd_procs}")
    c.record("stress-no-fprintd-process", fprintd_procs == 0, f"fprintd_procs={fprintd_procs}")

    status, output = run_harness(fingerprintMachine, fuid, "single", "omarchy-lock-password", password="${testUserPassword}")
    print("=== FINGERPRINT D: password still available after the finite outage stress ===")
    print(output)
    c.record("password-still-works-after-stress", "HARNESS_DONE completed:Success" in output)
    c.finish("fingerprint.backend-stress")

    c = Checks()
    machine.execute(f"su -l ${testUser} -c 'XDG_RUNTIME_DIR=/run/user/{uid} systemctl --user reset-failed omanixy-shell' 2>&1")
    status, output = run_su(machine, uid, "systemctl --user start omanixy-shell")
    print("=== SCENARIO 6a: initial start ===")
    print(f"status={status}")
    print(output)

    def show(prop):
        _, out = run_su(machine, uid, f"systemctl --user show omanixy-shell -p {prop} --value")
        return out.strip()

    deadline = time.time() + 90
    active_state = None
    result_prop = None
    n_restarts = None
    while time.time() < deadline:
        active_state = show("ActiveState")
        result_prop = show("Result")
        n_restarts = show("NRestarts")
        print(f"poll: ActiveState={active_state} Result={result_prop} NRestarts={n_restarts}")
        if active_state == "failed":
            break
        time.sleep(2)

    print("=== SCENARIO 6b: crash-loop bound reached ===")
    print(f"ActiveState={active_state} Result={result_prop} NRestarts={n_restarts}")
    c.record("crash-loop-bounded", active_state == "failed", f"ActiveState={active_state}")
    c.record("start-limit-hit", result_prop == "start-limit-hit", f"Result={result_prop}")
    c.record("restart-count-bounded", n_restarts is not None and int(n_restarts) <= 6, f"NRestarts={n_restarts}")

    reset_status, reset_output = run_su(machine, uid, "systemctl --user reset-failed omanixy-shell")
    print("=== SCENARIO 6c: reset-failed ===")
    print(f"status={reset_status}")
    print(reset_output)
    c.record("reset-failed-succeeds", reset_status == 0, f"status={reset_status}")

    restart_status, restart_output = run_su(machine, uid, "systemctl --user start omanixy-shell")
    print("=== SCENARIO 6d: restart after reset-failed ===")
    print(f"status={restart_status}")
    print(restart_output)
    c.record("fresh-start-accepted", restart_status == 0, f"status={restart_status}")
    c.finish("shell-restart.crash-loop-bound")

    print("ALL_SCENARIOS_DONE")
  '';
}
