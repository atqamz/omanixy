{ lib
, pkgs
, omarchy
, quickshellSrc
}:

let
  inherit (pkgs) stdenvNoCC;

  omarchyRevision = "f0020448ca87329199de7cb12f2015ebc4a3e5e7";
  quickshellRevision = "28771c7c74b42e20afca0b1b63980cb46515537c";

  quickshell = pkgs.quickshell.overrideAttrs (old: {
    pname = "quickshell-omanixy";
    version = "git-${lib.substring 0 7 quickshellRevision}";
    src = quickshellSrc;
    cmakeFlags =
      (lib.filter (flag: !(lib.hasInfix "GIT_REVISION" (toString flag))) (old.cmakeFlags or [ ]))
      ++ [ (lib.cmakeFeature "GIT_REVISION" quickshellRevision) ];
  });

  omarchySource = stdenvNoCC.mkDerivation {
    pname = "omarchy-quattro";
    version = lib.substring 0 12 omarchyRevision;
    src = omarchy;
    dontBuild = true;
    installPhase = ''
      mkdir -p "$out"
      cp -R ./. "$out/"
    '';
    meta = {
      description = "Pinned Omarchy Quattro source used by Omanixy";
      homepage = "https://github.com/basecamp/omarchy";
      license = lib.licenses.mit;
      platforms = lib.platforms.linux;
    };
  };

  theme = stdenvNoCC.mkDerivation {
    pname = "omanixy-shell-theme";
    version = lib.substring 0 12 omarchyRevision;
    src = "${omarchySource}/themes/tokyo-night";
    dontBuild = true;
    installPhase = ''
      mkdir -p "$out"
      install -Dm644 colors.toml "$out/colors.toml"
      cat > "$out/shell.toml" <<'EOF'
      [bar]
      background = "background"
      background-alpha = 1.0
      text = "foreground"
      active = "urgent"

      [font]
      base-size = 12

      [spacing]
      scale = 1.0
      scale-with-font = true
      EOF
    '';
  };

  runtimeInputs = with pkgs; [
    bash
    coreutils
    findutils
    gawk
    gnugrep
    gnused
    inotify-tools
    fontconfig
    hyprland
    procps
    quickshell
  ];

  runtime = pkgs.writeShellApplication {
    name = "omanixy-shell-runtime";
    runtimeInputs = runtimeInputs;
    inheritPath = false;
    text = ''
      export OMARCHY_PATH=${lib.escapeShellArg "${omarchySource}"}
      export QS_DISABLE_FILE_WATCHER=1
      export QS_NO_RELOAD_POPUP=1
      exec quickshell -n -p "$OMARCHY_PATH/shell"
    '';
  };

  ipc = pkgs.writeShellApplication {
    name = "omanixy-shell";
    runtimeInputs = with pkgs; [ coreutils quickshell ];
    inheritPath = false;
    text = builtins.replaceStrings
      [ "@OMARCHY_PATH@" ]
      [ (toString omarchySource) ]
      (builtins.readFile ./ipc-wrapper.bash);
  };
in
pkgs.symlinkJoin {
  name = "omanixy-shell";
  paths = [ ipc runtime ];
  postBuild = ''
    mkdir -p "$out/bin" "$out/share"
    ln -s ${quickshell}/bin/quickshell "$out/bin/quickshell"
    ln -s ${quickshell}/bin/qs "$out/bin/qs"
    ln -s ${pkgs.inotify-tools}/bin/inotifywait "$out/bin/inotifywait"
    ln -s ${pkgs.hyprland}/bin/hyprctl "$out/bin/hyprctl"
    ln -s ${pkgs.procps}/bin/pkill "$out/bin/pkill"
    ln -s ${theme} "$out/share/omarchy-theme"
  '';
  passthru = {
    inherit omarchyRevision quickshellRevision omarchySource quickshell theme;
  };
  meta = {
    description = "Nix-native Omarchy Quattro runtime and IPC client";
    homepage = "https://github.com/atqamz/omanixy";
    license = lib.licenses.mit;
    mainProgram = "omanixy-shell";
    platforms = lib.platforms.linux;
  };
}
