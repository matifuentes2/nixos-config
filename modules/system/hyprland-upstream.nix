{ hyprland, pkgs, ... }:

let
  hyprlandPackages = hyprland.packages.${pkgs.stdenv.hostPlatform.system};
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

  # Keep the system Mesa. Hyprland's nixpkgs may use a newer glibc, and its
  # Mesa then fails to load in system programs such as SDDM's Weston greeter.
}
