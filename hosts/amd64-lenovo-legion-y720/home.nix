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
    pkgs.tree
  ];

  home.shellAliases.rebuild = "sudo nixos-rebuild switch --flake /etc/nixos#amd64-lenovo-legion-y720";
}
