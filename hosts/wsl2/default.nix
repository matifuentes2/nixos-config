{ pkgs, username, ... }:

{
  imports = [
    ../../modules/system/common.nix
  ];

  networking.hostName = "wsl2";

  # NixOS-WSL supplies the Windows kernel, boot integration, the default user,
  # and Windows executable interoperability.
  wsl = {
    enable = true;
    defaultUser = username;
  };

  # Support dynamically linked tools such as the VS Code Remote server.
  programs.nix-ld.enable = true;

  # System administration tools belong to the host; user-facing tools are
  # shared through Home Manager.
  environment.systemPackages = with pkgs; [
    vim
    wget
    git
    gh
  ];

  # This is the first NixOS version used for this WSL2 host. Do not change it
  # during normal upgrades; it controls compatibility defaults.
  system.stateVersion = "26.11";
}
