{
  networking.hostName = "omanixy-example";
  networking.networkmanager.enable = true;

  hardware.bluetooth.enable = true;

  services.pipewire = {
    enable = true;
    pulse.enable = true;
  };
  services.upower.enable = true;
  services.power-profiles-daemon.enable = true;

  programs.hyprland.enable = true;
  programs.omanixy.security.pam.password.enable = true;

  fileSystems."/" = {
    device = "/dev/null";
    fsType = "ext4";
  };
  boot.loader.grub.devices = [ "/dev/null" ];

  system.stateVersion = "26.11";
}
