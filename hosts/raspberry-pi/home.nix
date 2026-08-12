{ nodejsNixpkgs, pkgs, ... }:

let
  nodejs = import ./nodejs.nix {
    inherit nodejsNixpkgs pkgs;
  };
in
{
  imports = [
    ../../modules/home/common.nix
    ../../modules/home/linux.nix
  ];

  home.username = "pi";
  home.homeDirectory = "/home/pi";

  # Keep this at the version used when Home Manager was first configured.
  home.stateVersion = "25.11";

  home.packages = [
    nodejs
    pkgs.tree
  ];

  home.shellAliases.rebuild = "sudo nixos-rebuild switch --flake /etc/nixos#nixos";
}
