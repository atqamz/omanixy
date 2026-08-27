{ lib, ... }:
{
  services.mako.enable = true;

  programs.omanixy = {
    enable = true;
    features = [
      "audio"
      "bluetooth"
      "launcher"
      "monitor"
      "network"
      "notification"
      "power"
      "screenshot"
      "weather"
    ];
    shell.config = {
      custom = true;
      disabledPlugins = [ "omarchy.audio" "omarchy.bluetooth" ];
    };
    security = {
      lock.enable = lib.mkDefault false;
      idle.enable = lib.mkDefault false;
      polkit.agent.enable = lib.mkDefault false;
      notifications.daemon.enable = lib.mkDefault false;
    };
  };
}
