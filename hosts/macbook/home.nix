{ pkgs, username, ... }:

{
  imports = [
    ../../modules/home/common.nix
    ../../modules/home/darwin.nix
  ];

  home.username = username;
  home.homeDirectory = "/Users/${username}";

  # This is the first Home Manager version used for this macOS host.
  home.stateVersion = "25.11";

  # Add packages used only on this Mac here.
  home.packages = with pkgs; [
  ];

  home.shellAliases.rebuild = "sudo darwin-rebuild switch --flake ~/nixos-config#macbook";
}
