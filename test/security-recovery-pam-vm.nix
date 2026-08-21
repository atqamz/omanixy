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

  # A second, password+fingerprint-enabled node dedicated to the fingerprint
  # scenarios below. It needs no Home Manager pairing: the harness drives
  # Quickshell.Services.Pam.PamContext directly against the raw
  # omarchy-lock-fingerprint PAM service, never the production lock plugin.
  # programs.omanixy.security.pam.fingerprint.enable never sets
  # services.fprintd.enable itself (modules/nixos/default.nix); it only
  # registers the resolved services.fprintd.package with
  # services.dbus.packages/systemd.packages/environment.systemPackages, the
  # same real D-Bus activation surface services.fprintd.enable would
  # register, without widening any other PAM service's fprintAuth default.
  # No fingerprint reader exists in this VM, so the real fprintd daemon this
  # node genuinely D-Bus-activates is expected to report zero devices.
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
        # The bracket trick (qu[i]ckshell) keeps this pattern from matching
        # the literal pgrep/su/bash wrapper command lines that necessarily
        # contain the same search string, so it only matches a real
        # quickshell process.
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
            assert_checks(output, RECOVERY_CHECKS[scenario_id]["checks"])
            self.lines = []

    # --- Scenario 1: real PAM conversation, correct and wrong password ---
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

    # --- Scenario 2: repeated wrong password (>=20 attempts), then still retryable ---
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
    # Bounded on both sides: a generous multiplier of the 20-attempt
    # stimulus, not an arbitrary byte count.
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

    # A short observation window after the stimulus has already stopped: the
    # count must not keep growing on its own (no repeating sub-second
    # PAM/log loop left running).
    time.sleep(2)
    proc_count_after_wait = int(machine.succeed("pgrep -c unix_chkpwd || true").strip() or "0")
    print(f"unix_chkpwd helper processes after a 2s post-stimulus observation window: {proc_count_after_wait}")
    c.record("helper-no-growth-after-wait", proc_count_after_wait == proc_count, f"{proc_count} -> {proc_count_after_wait}")
    c.finish("pam-password.repeated-failure")

    # --- Scenario 3: PAM cancel mid-conversation ---
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

    # --- Scenario 4: missing PAM service (fingerprint disabled on this node -> no /etc/pam.d file) ---
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

    # ============================================================
    # Fingerprint scenarios, on fingerprintMachine: real fprintd backend,
    # no physical reader present in this VM.
    # ============================================================
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
        # NixOS provisions fprintd.service's main unit fragment as a real
        # symlink directly under /etc/systemd/system (persistent-tier
        # search path, read-only in this disposable test VM's root), which
        # ranks above /run/systemd/system for resolving *which* fragment
        # defines the unit - so a plain `systemctl mask [--runtime]`
        # (confirmed empirically: it left LoadState=loaded, still fully
        # answering GetDevices) can neither write there nor out-rank it.
        # systemd.service.d/ drop-ins, unlike the main fragment, are always
        # merged in from every search-path tier regardless of which tier
        # the base fragment itself resolved from - so a *runtime* drop-in
        # under /run genuinely does take effect on top of the real /etc
        # fragment. Overriding ExecStart to a command that always fails
        # makes every future start attempt (manual or D-Bus-activated)
        # genuinely fail, without touching any Omanixy-owned or
        # nixpkgs-owned file.
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

    # --- Fingerprint scenario A: real backend, no device ---
    c = Checks()
    c.record(
        "pam-service-exists",
        fingerprintMachine.execute("test -e /etc/pam.d/omarchy-lock-fingerprint")[0] == 0,
    )
    is_enabled = fingerprintMachine.succeed("systemctl is-enabled fprintd.service 2>&1 || true").strip()
    print(f"fprintd.service is-enabled: {is_enabled!r}")
    # A D-Bus system-activated service is never [Install]-enabled by a
    # symlink; registration alone (services.dbus.packages/systemd.packages)
    # never flips systemctl is-enabled to "enabled". This is the runtime
    # complement to the module's own build-time
    # services.fprintd.enable == false assertion (modules/nixos/default.nix)
    # - if that assertion were ever violated the build itself would already
    # have failed before this VM ever booted.
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

    # --- Fingerprint scenario B: real backend deliberately made unavailable ---
    c = Checks()
    owner_before_outage = fingerprintMachine.execute(
        "busctl call org.freedesktop.DBus /org/freedesktop/DBus org.freedesktop.DBus GetNameOwner s net.reactivated.Fprint 2>&1"
    )[1]
    print(f"name owner before outage stimulus: {owner_before_outage!r}")

    fingerprintMachine.succeed("systemctl stop fprintd.service 2>&1 || true")
    # Bounded poll for a fully synchronous stop: `systemctl stop` normally
    # already blocks until the unit reaches an inactive state, but this
    # confirms it explicitly (and bounds the wait) before the process-level
    # belt-and-braces kill below, rather than assuming the default
    # synchronous behavior held.
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
    # Belt-and-braces: guarantee no real fprintd process instance from
    # before the outage stimulus is still alive and still holding the bus
    # name, independent of whatever systemd itself reports. The bracketed
    # "fprint[d]" (mirroring the qu[i]ckshell trick used elsewhere in this
    # file) keeps pkill's own argv - which literally contains this same
    # search text - from matching and killing itself.
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

    # --- Fingerprint scenario C: backend recovery ---
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

    # --- Fingerprint scenario D: finite real-backend-unavailable stress (20 attempts) ---
    c = Checks()
    fingerprintMachine.succeed("systemctl stop fprintd.service 2>&1 || true")
    fingerprintMachine.succeed("pkill -9 -f '/libexec/fprint[d]' 2>&1 || true")
    induce_outage(fingerprintMachine)

    stress_attempts = 0
    stress_successes = 0
    stress_output_lines = 0
    for i in range(20):
        status, output = run_harness(fingerprintMachine, fuid, "single", "omarchy-lock-fingerprint", password="irrelevant", extra_timeout=25, watchdog_ms=20000)
        stress_attempts += 1
        stress_output_lines += len(output.splitlines())
        if "HARNESS_DONE completed:Success" in output:
            stress_successes += 1
    print(f"=== FINGERPRINT D: finite outage stress - {stress_attempts} attempts, {stress_successes} successes, {stress_output_lines} output lines ===")

    c.record("stress-20-attempts-completed", stress_attempts == 20, f"attempts={stress_attempts}")
    c.record("stress-zero-success", stress_successes == 0, f"successes={stress_successes}")

    leftover = leftover_quickshell(fingerprintMachine)
    print(f"leftover quickshell processes immediately after the stress run: {leftover}")
    c.record("stress-single-process", leftover == 0, f"leftover={leftover}")

    # Generous multiplier of the 20-attempt stimulus, mirroring
    # recovery.polkit-stress-finite's own bound formula.
    max_lines = 20 * 15 + 50
    c.record("stress-log-bound", stress_output_lines <= max_lines, f"lines={stress_output_lines} max={max_lines}")

    time.sleep(2)
    leftover_after_wait = leftover_quickshell(fingerprintMachine)
    print(f"leftover quickshell processes after a 2s post-stimulus observation window: {leftover_after_wait}")
    c.record("stress-no-runaway-retry", leftover_after_wait == leftover, f"{leftover} -> {leftover_after_wait}")
    c.record("stress-log-quiescent", leftover_after_wait == 0, f"leftover_after_wait={leftover_after_wait}")

    status, output = run_harness(fingerprintMachine, fuid, "single", "omarchy-lock-password", password="${testUserPassword}")
    print("=== FINGERPRINT D: password still available after the finite outage stress ===")
    print(output)
    c.record("password-still-works-after-stress", "HARNESS_DONE completed:Success" in output)
    c.finish("fingerprint.backend-stress")

    # --- Scenario 6: systemd user-service crash-loop bound (no Wayland compositor present) ---
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

    # Not permanently wedged: reset-failed + start must be re-attemptable.
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
