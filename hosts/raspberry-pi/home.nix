{ pkgs, ... }:

{
  imports = [
    ../../modules/home/common.nix
    ../../modules/home/linux.nix
  ];

  home.username = "pi";
  home.homeDirectory = "/home/pi";

  # Keep this at the version used when Home Manager was first configured.
  home.stateVersion = "25.11";

  # GTK's Vulkan renderer crashes in the Pi's Broadcom driver when Walker opens.
  systemd.user.services.walker.Service.Environment = [
    "GSK_RENDERER=ngl"
  ];

  home.packages = [
    pkgs.tree
    pkgs.seahorse # Initialize/manage T3 Code's password-protected login keyring.
    (pkgs.callPackage ../../packages/t3-code.nix { })
  ];

  home.shellAliases.rebuild = "sudo nixos-rebuild switch --flake /etc/nixos#nixos";
}
