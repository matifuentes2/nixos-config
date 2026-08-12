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
    # Orca compiles node-pty on Linux when installing its SSH relay. Keep the
    # native addon toolchain in the SSH user's profile so it is on PATH when
    # Orca reconnects and reinstalls the relay dependencies.
    pkgs.gcc
    pkgs.gnumake
    nodejs
    pkgs.python3
    pkgs.tree
  ];

  home.shellAliases.rebuild = "sudo nixos-rebuild switch --flake /etc/nixos#nixos";
}
