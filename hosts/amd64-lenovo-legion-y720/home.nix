{
  pkgs,
  username,
  ...
}:

{
  imports = [
    ../../modules/home/common.nix
    ../../modules/home/linux.nix
  ];

  home.username = username;
  home.homeDirectory = "/home/${username}";

  # Keep this at the version used when Home Manager was first configured.
  home.stateVersion = "26.11";

  home.packages = [
    pkgs.discord
    pkgs.nwg-displays
    pkgs.tree
  ];

  # Let nwg-displays manage the local monitor layout without making the
  # connected display topology part of the declarative host configuration.
  wayland.windowManager.hyprland.extraConfig = ''
    source = ~/.config/hypr/monitors.conf
    source = ~/.config/hypr/workspaces.conf
  '';

  home.shellAliases.rebuild = "sudo nixos-rebuild switch --flake /etc/nixos#amd64-lenovo-legion-y720";
}
