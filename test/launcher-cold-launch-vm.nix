{ pkgs, self, home-manager }:

let
  system = pkgs.system;
  runtime = self.packages.${system}.omanixy-shell;
  compatibilityRoot = runtime.passthru.omarchyCompatibilityRoot;
  quickshell = runtime.passthru.quickshell;
  testUser = "omanixy-launcher-test";
  appId = "org.omanixy.LauncherColdLaunch";
  terminalAppId = "org.omanixy.LauncherTerminal";
  missingId = "org.omanixy.Missing";
  harness = pkgs.writeText "omanixy-launcher-cold-launch-harness.qml" ''
    import QtQuick
    import Quickshell
    import Quickshell.Wayland

    ShellRoot {
      id: root

      property bool launchRequested: false
      property int attempts: 0

      Loader {
        id: appLibrary
        source: "${compatibilityRoot}/shell/services/AppLibrary.qml"
      }

      Timer {
        interval: 100
        repeat: true
        running: true
        onTriggered: {
          root.attempts++
          var entries = DesktopEntries.applications.values || []
          var found = false
          for (var i = 0; i < entries.length; i++) {
            if (entries[i] && String(entries[i].id || "") === "${appId}") {
              found = true
              break
            }
          }
          if (appLibrary.status === Loader.Ready && found && !root.launchRequested) {
            appLibrary.item.launch("${missingId}", "missing test entry")
            appLibrary.item.launch("${appId}", "cold launch test app")
            appLibrary.item.launch("${terminalAppId}", "terminal launch test app")
            root.launchRequested = true
          }

          var toplevels = ToplevelManager.toplevels.values || []
          for (var j = 0; j < toplevels.length; j++) {
            var toplevel = toplevels[j]
            if (toplevel && String(toplevel.appId || "") === "${appId}") {
              console.log("COLD_LAUNCH_TOPLEVEL_READY")
              Qt.quit()
              return
            }
          }

          if (root.attempts >= 300) {
            console.log("COLD_LAUNCH_TOPLEVEL_TIMEOUT")
            Qt.quit()
          }
        }
      }
    }
  '';
in
pkgs.testers.runNixOSTest {
  name = "launcher-cold-launch-vm";

  nodes.machine = { ... }: {
    imports = [ home-manager.nixosModules.home-manager ];

    users.users.${testUser} = {
      isNormalUser = true;
    };

    environment.etc."omanixy/launcher-cold-launch-harness.qml".source = harness;
    environment.systemPackages = [
      pkgs.gtk3
      pkgs.sway
      pkgs.uwsm
    ];

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

  testScript = ''
    import shlex

    test_user = "${testUser}"
    app_id = "${appId}"
    terminal_app_id = "${terminalAppId}"
    missing_id = "${missingId}"
    compatibility_root = "${compatibilityRoot}"
    quickshell_path = "${quickshell}/bin/quickshell"
    foot_path = "${pkgs.foot}/bin/foot"

    start_all()
    machine.wait_for_unit("multi-user.target")
    machine.succeed(f"loginctl enable-linger {test_user}")
    uid = machine.succeed(f"id -u {test_user}").strip()
    machine.wait_for_unit(f"user@{uid}.service")

    runtime_dir = f"/run/user/{uid}"
    home = f"/home/{test_user}"
    app_dir = f"{home}/.local/share/applications"
    data_home = f"{home}/.local/share"
    desktop = f"{app_dir}/{app_id}.desktop"
    app_script = f"{home}/launcher-cold-launch-app"
    app_pid = f"{home}/launcher-cold-launch.pid"
    terminal_app_script = f"{home}/launcher-terminal-app"
    terminal_app_pid = f"{home}/launcher-terminal.pid"
    compositor_pid = f"{home}/launcher-cold-launch-compositor.pid"
    compositor_config = f"{home}/launcher-cold-launch-compositor.conf"
    qml_import_root = "/tmp/omanixy-launcher-qml"

    def as_user(command):
        environment = f"XDG_RUNTIME_DIR={runtime_dir} DBUS_SESSION_BUS_ADDRESS=unix:path={runtime_dir}/bus"
        return f"su -l {test_user} -c {shlex.quote(environment + ' ' + command)}"

    machine.succeed(f"mkdir -p {shlex.quote(app_dir)} {shlex.quote(qml_import_root)}")
    machine.succeed(
      f"ln -s {shlex.quote(compatibility_root + '/shell')} "
      f"{shlex.quote(qml_import_root + '/qs')}"
    )

    app_contents = chr(10).join([
      "#!/bin/sh",
      "printf '%s' \"$$\" > \"$HOME/launcher-cold-launch.pid\"",
      f"exec {foot_path} --app-id={app_id} --title='Omanixy cold launch test'",
      "",
    ])
    machine.succeed(f"printf %s {shlex.quote(app_contents)} > {shlex.quote(app_script)}")
    machine.succeed(f"chmod 755 {shlex.quote(app_script)}")

    terminal_app_contents = chr(10).join([
      "#!/bin/sh",
      f"printf '%s' $$ > {terminal_app_pid}",
      "sleep 60",
      "",
    ])
    machine.succeed(
      f"printf %s {shlex.quote(terminal_app_contents)} > {shlex.quote(terminal_app_script)}"
    )
    machine.succeed(f"chmod 755 {shlex.quote(terminal_app_script)}")

    desktop_contents = chr(10).join([
      "[Desktop Entry]",
      "Type=Application",
      "Name=Omanixy cold launch test",
      f"Exec={app_script}",
      f"StartupWMClass={app_id}",
      "",
    ])
    machine.succeed(f"printf %s {shlex.quote(desktop_contents)} > {shlex.quote(desktop)}")

    terminal_desktop = f"{app_dir}/{terminal_app_id}.desktop"
    terminal_desktop_contents = chr(10).join([
      "[Desktop Entry]",
      "Type=Application",
      "Name=Omanixy terminal launch test",
      f"Exec={terminal_app_script}",
      "Terminal=true",
      "",
    ])
    machine.succeed(
      f"printf %s {shlex.quote(terminal_desktop_contents)} > {shlex.quote(terminal_desktop)}"
    )

    compositor_contents = chr(10).join([
      "output HEADLESS-1 mode 1024x768",
      "default_border none",
      "",
    ])
    machine.succeed(
      f"printf %s {shlex.quote(compositor_contents)} > {shlex.quote(compositor_config)}"
    )
    compositor_command = (
      f"WLR_BACKENDS=headless WLR_RENDERER=pixman WLR_HEADLESS_OUTPUTS=1 "
      f"XDG_CURRENT_DESKTOP=sway XDG_SESSION_TYPE=wayland "
      f"nohup sway --config {shlex.quote(compositor_config)} "
      f">{home}/launcher-cold-launch-compositor.log 2>&1 & echo $! > {shlex.quote(compositor_pid)}"
    )
    machine.succeed(as_user(compositor_command))
    machine.wait_until_succeeds(f"test -S {runtime_dir}/wayland-1")
    machine.succeed(
      as_user(
        "WAYLAND_DISPLAY=wayland-1 XDG_CURRENT_DESKTOP=omarchy "
        "systemctl --user import-environment WAYLAND_DISPLAY XDG_CURRENT_DESKTOP"
      )
    )
    machine.succeed(as_user("command -v uwsm && command -v gtk-launch"))
    machine.succeed(as_user(f"grep -Fxq foot.desktop {shlex.quote(home + '/.config/xdg-terminals.list')}"))

    machine.succeed(f"rm -f {shlex.quote(app_pid)}")
    harness_command = (
      f"WAYLAND_DISPLAY=wayland-1 XDG_DATA_HOME={shlex.quote(data_home)} "
      f"OMARCHY_PATH={shlex.quote(compatibility_root)} "
      f"QML2_IMPORT_PATH={qml_import_root} timeout 40s "
      f"{shlex.quote(quickshell_path)} -n -p /etc/omanixy/launcher-cold-launch-harness.qml"
    )
    status, output = machine.execute(as_user(harness_command))
    print(output)
    assert status == 0, f"launcher harness exited with {status}"
    assert "COLD_LAUNCH_TOPLEVEL_READY" in output, output
    assert f"desktop entry not found: {missing_id}" in output, output

    machine.wait_until_succeeds(f"test -s {shlex.quote(app_pid)}")
    pid = machine.succeed(f"cat {shlex.quote(app_pid)}").strip()
    machine.succeed(f"kill -0 {shlex.quote(pid)}")
    cgroup = machine.succeed(
      f"awk -F: '$1 == \"0\" {{ print $3 }}' /proc/{shlex.quote(pid)}/cgroup"
    ).strip()
    assert "/app-graphical.slice/" in cgroup, cgroup
    assert cgroup.endswith(".service"), cgroup
    unit = cgroup.rsplit("/", 1)[-1]
    unit_status = machine.succeed(
      as_user(f"systemctl --user show {shlex.quote(unit)} -p ActiveState -p ExitType")
    )
    assert "ActiveState=active" in unit_status, unit_status
    assert "ExitType=cgroup" in unit_status, unit_status

    machine.wait_until_succeeds(f"test -s {shlex.quote(terminal_app_pid)}", timeout=30)
    terminal_pid = machine.succeed(f"cat {shlex.quote(terminal_app_pid)}").strip()
    machine.succeed(f"kill -0 {shlex.quote(terminal_pid)}")
    terminal_cgroup = machine.succeed(
      f"awk -F: '$1 == \"0\" {{ print $3 }}' /proc/{shlex.quote(terminal_pid)}/cgroup"
    ).strip()
    assert "/app-graphical.slice/" in terminal_cgroup, terminal_cgroup
    assert terminal_cgroup.endswith(".service"), terminal_cgroup
    terminal_unit = terminal_cgroup.rsplit("/", 1)[-1]
    terminal_unit_status = machine.succeed(
      as_user(f"systemctl --user show {shlex.quote(terminal_unit)} -p ActiveState -p ExitType")
    )
    assert "ActiveState=active" in terminal_unit_status, terminal_unit_status
    assert "ExitType=cgroup" in terminal_unit_status, terminal_unit_status

    machine.succeed(as_user(f"systemctl --user stop {shlex.quote(unit)}"))
    machine.succeed(as_user(f"systemctl --user stop {shlex.quote(terminal_unit)}"))
    machine.succeed(as_user(f"kill $(cat {shlex.quote(compositor_pid)}) 2>/dev/null || true"))
  '';
}
