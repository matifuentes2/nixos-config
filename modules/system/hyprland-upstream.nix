{ hyprland, pkgs, ... }:

let
  system = pkgs.stdenv.hostPlatform.system;
  hyprlandPackages = hyprland.packages.${system};
  # Hyprland is built against its own nixpkgs revision.
  hyprlandPkgs = hyprland.inputs.nixpkgs.legacyPackages.${system};
in
{
  # Run the pinned upstream Hyprland release instead of the nixpkgs build.
  # Hyprland's Cachix publishes x86-64 binaries; other platforms would compile
  # Hyprland locally, so only import this module on x86-64 hosts.
  nix.settings = {
    substituters = [ "https://hyprland.cachix.org" ];
    trusted-public-keys = [ "hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIBMioiJM7ypFP8PwtkuGc=" ];
  };

  programs.hyprland = {
    package = hyprlandPackages.hyprland;
    portalPackage = hyprlandPackages.xdg-desktop-portal-hyprland;
  };

  # Match Mesa to Hyprland's nixpkgs to avoid mismatched graphics drivers.
  hardware.graphics = {
    package = hyprlandPkgs.mesa;
    package32 = hyprlandPkgs.pkgsi686Linux.mesa;
  };
}
