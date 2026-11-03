{ pkgs, ... }:

{
  imports = [
    ../../hyprland
  ];

  home.packages = [ pkgs.satty ];

  # Start the PipeWire effects processor with the graphical session.
  services.easyeffects.enable = true;

  services.elephant.enable = true;
  services.walker = {
    enable = true;
    enableElephantIntegration = true;
    systemd.enable = true;
  };
}
