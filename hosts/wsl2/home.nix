{ pkgs, username, ... }:

{
  # The Linux module currently owns the Raspberry Pi's Hyprland desktop, so a
  # terminal-oriented WSL environment imports only the portable shared module.
  imports = [
    ../../modules/home/common.nix
  ];

  home.username = username;
  home.homeDirectory = "/home/${username}";

  # Keep this at the Home Manager version used for the first WSL2 activation.
  home.stateVersion = "26.11";

  home.packages = [
    pkgs.tree
  ];

  home.shellAliases.rebuild = "sudo nixos-rebuild switch --flake ~/nixos-config#wsl2";
}
