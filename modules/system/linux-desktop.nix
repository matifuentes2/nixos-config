{ pkgs, ... }:

{
  # Run a Wayland-native Hyprland desktop with an SDDM login screen.
  programs.hyprland.enable = true;

  services.displayManager = {
    defaultSession = "hyprland";
    sddm = {
      enable = true;
      wayland.enable = true;
    };
  };

  # Desktop integration used by the shared Home Manager configuration.
  security.pam.services.hyprlock = { };
  programs.thunar.enable = true;
  services.gvfs.enable = true;
  services.tumbler.enable = true;

  fonts.packages = with pkgs; [
    font-awesome
    nerd-fonts.jetbrains-mono
  ];
}
