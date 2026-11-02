{ pkgs, username, ... }:

{
  imports = [
    ../../modules/system/common.nix
    ../../modules/system/claude-code.nix
  ];

  networking.hostName = "wsl2";

  # T3 Code Desktop is reachable through the Windows-to-WSL port forward.
  networking.firewall.allowedTCPPorts = [ 3773 ];

  # NixOS-WSL supplies the Windows kernel, boot integration, the default user,
  # and Windows executable interoperability.
  wsl = {
    enable = true;
    defaultUser = username;
  };

  # Support dynamically linked tools such as the VS Code Remote server.
  programs.nix-ld.enable = true;

  # The T3 Code wrapper uses libsecret for encrypted credential storage.
  services.gnome.gnome-keyring.enable = true;

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
