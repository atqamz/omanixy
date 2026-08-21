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

  # A second, password+fingerprint-enabled node dedicated to Scenario 5
  # (fingerprint, no device). It needs no Home Manager pairing: the harness
  # drives Quickshell.Services.Pam.PamContext directly against the raw
  # omarchy-lock-fingerprint PAM service, never the production lock plugin.
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

    # --- Scenario 1: real PAM conversation, correct password ---
    status, output = run_harness(machine, uid, "single", "omarchy-lock-password", password="${testUserPassword}")
    print("=== SCENARIO 1a: correct password ===")
    print(f"status={status}")
    print(output)
    assert "HARNESS_DONE completed:Success" in output, "correct password must authenticate successfully via real PAM"

    # --- Scenario 1: real PAM conversation, wrong password ---
    status, output = run_harness(machine, uid, "single", "omarchy-lock-password", password="definitely-wrong-password")
    print("=== SCENARIO 1b: wrong password ===")
    print(f"status={status}")
    print(output)
    assert "HARNESS_DONE completed:Failed" in output, "wrong password must fail authentication, not succeed or hang"

    # --- Scenario 2: repeated wrong password (>=20 attempts), then still retryable ---
    t0 = time.time()
    status, output = run_harness(
        machine, uid, "repeat", "omarchy-lock-password",
        password="${testUserPassword}", wrong_password="definitely-wrong-password",
        repeat_count=20, extra_timeout=180, watchdog_ms=170000,
    )
    elapsed = time.time() - t0
    print("=== SCENARIO 2: 20 wrong attempts then correct ===")
    print(f"status={status} elapsed={elapsed:.1f}s")
    print(output)
    assert "HARNESS_DONE repeat-final:Success" in output, "session must remain authenticatable after 20 wrong attempts (no faillock/lockout)"
    attempt_lines = [l for l in output.splitlines() if "HARNESS_EVENT attempt" in l]
    assert len(attempt_lines) >= 20, f"expected at least 20 attempts logged, got {len(attempt_lines)}"

    proc_count = machine.succeed("pgrep -c unix_chkpwd || true").strip()
    print(f"lingering unix_chkpwd helper processes after repeat scenario: {proc_count}")
    log_size = machine.succeed(
        f"du -sb /run/user/{uid}/quickshell 2>/dev/null | tail -1 | cut -f1 || echo 0"
    ).strip()
    print(f"quickshell log directory size after repeat scenario: {log_size} bytes")

    # --- Scenario 3: PAM cancel mid-conversation ---
    t0 = time.time()
    status, output = run_harness(machine, uid, "cancel", "omarchy-lock-password", watchdog_ms=15000, extra_timeout=20)
    elapsed = time.time() - t0
    print("=== SCENARIO 3: cancel mid-conversation ===")
    print(f"status={status} elapsed={elapsed:.1f}s")
    print(output)
    assert "HARNESS_EVENT abort" in output, "harness must have reached the abort() call mid-conversation"
    assert "HARNESS_DONE completed:Success" not in output, "an aborted conversation must never report success"
    assert "HARNESS_DONE completed:Failed" not in output, "an abort is distinct from a normal authentication failure"
    assert "HARNESS_DONE aborted-active-false" in output, "abort() must deterministically drop PamContext.active, not merely be followed by silence until a watchdog fires"
    assert elapsed < 10, f"abort() must release the PAM subprocess promptly, took {elapsed:.1f}s"
    # The bracket trick (qu[i]ckshell) keeps this pattern from matching the
    # literal pgrep/su/bash wrapper command lines that necessarily contain
    # the same search string, so it only matches a real quickshell process.
    leftover = machine.succeed("pgrep -fc 'qu[i]ckshell -n -p' || true").strip()
    print(f"leftover quickshell processes immediately after cancel: {leftover}")
    assert leftover == "0", f"the aborted PAM subprocess must not linger as an orphan process, found {leftover}"

    # --- Scenario 4: missing PAM service (fingerprint disabled on this node -> no /etc/pam.d file) ---
    machine.fail("test -e /etc/pam.d/omarchy-lock-fingerprint")
    status, output = run_harness(machine, uid, "single", "omarchy-lock-fingerprint", password="irrelevant")
    print("=== SCENARIO 4: missing PAM service ===")
    print(f"status={status}")
    print(output)
    assert "HARNESS_DONE completed:Failed" not in output, "a missing PAM service must not be reported as an ordinary auth failure"
    assert (
        "HARNESS_EVENT start-failed" in output or "HARNESS_EVENT error StartFailed" in output
    ), "a missing PAM service must fail PAM start distinctly, never silently fall back"

    # --- Scenario 5: fingerprint, no device, on a NixOS host with the fingerprint capability enabled ---
    fingerprintMachine.wait_for_unit("multi-user.target")
    fingerprintMachine.succeed("id ${testUser}")
    fingerprintMachine.succeed("test -e /etc/pam.d/omarchy-lock-fingerprint")
    fuid = fingerprintMachine.succeed("id -u ${testUser}").strip()
    fingerprintMachine.succeed("loginctl enable-linger ${testUser}")
    fingerprintMachine.wait_for_unit(f"user@{fuid}.service")
    t0 = time.time()
    status, output = run_harness(fingerprintMachine, fuid, "single", "omarchy-lock-fingerprint", password="irrelevant", extra_timeout=30)
    elapsed = time.time() - t0
    print("=== SCENARIO 5: fingerprint, no device ===")
    print(f"status={status} elapsed={elapsed:.1f}s")
    print(output)
    assert "HARNESS_DONE completed:Success" not in output, "fingerprint auth with no device must never grant access"
    assert "HARNESS_DONE timeout" not in output, "fingerprint auth with no device must not hang"
    assert elapsed < 25, f"fingerprint-no-device path took too long ({elapsed:.1f}s), suggesting a hang rather than a fail-closed error"

    # Password authentication must remain available alongside the failed-closed fingerprint path.
    status, output = run_harness(fingerprintMachine, fuid, "single", "omarchy-lock-password", password="${testUserPassword}")
    print("=== SCENARIO 5b: password still available on the fingerprint-enabled host ===")
    print(f"status={status}")
    print(output)
    assert "HARNESS_DONE completed:Success" in output, "password authentication must remain available and functional regardless of the fingerprint capability or hardware state"

    # --- Scenario 6: systemd user-service crash-loop bound (no Wayland compositor present) ---
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
    assert active_state == "failed", f"unit must end in failed (bounded), not stuck restarting forever; got {active_state}"
    assert result_prop == "start-limit-hit", f"unit must fail via StartLimitBurst, not some other reason; got {result_prop}"
    assert n_restarts is not None and int(n_restarts) <= 6, f"NRestarts should be small/bounded (StartLimitBurst=5), got {n_restarts}"

    # Not permanently wedged: reset-failed + start must be re-attemptable.
    reset_status, reset_output = run_su(machine, uid, "systemctl --user reset-failed omanixy-shell")
    print("=== SCENARIO 6c: reset-failed ===")
    print(f"status={reset_status}")
    print(reset_output)
    assert reset_status == 0, "reset-failed must succeed"

    restart_status, restart_output = run_su(machine, uid, "systemctl --user start omanixy-shell")
    print("=== SCENARIO 6d: restart after reset-failed ===")
    print(f"status={restart_status}")
    print(restart_output)
    assert restart_status == 0, "a fresh start attempt after reset-failed must be accepted (not permanently wedged), even though it will fail again for the same Wayland-absence reason"

    print("ALL_SCENARIOS_DONE")
  '';
}
