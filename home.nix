{ config, pkgs, ... }:

{
  imports = [ ./neovim ];

  home.username = "pi";
  home.homeDirectory = "/home/pi";

  # Keep this at the version used when Home Manager was first configured.
  home.stateVersion = "25.11";

  # Packages installed only for this user.
  home.packages = with pkgs; [
    ripgrep
    fd
    jq
  ];

  home.sessionVariables = {
    EDITOR = "nvim";
    VISUAL = "nvim";
  };

  programs.bash = {
    enable = true;

    shellAliases = {
      ll = "ls -alh";
      la = "ls -A";
      gs = "git status";
      rebuild = "sudo nixos-rebuild switch --flake /etc/nixos#nixos";
    };

    # Put Bash-specific functions and other interactive setup here.
    initExtra = ''
      # Example:
      # mkcd() { mkdir -p "$1" && cd "$1"; }
    '';
  };

  # Lets Home Manager manage itself for this user.
  programs.home-manager.enable = true;
}
