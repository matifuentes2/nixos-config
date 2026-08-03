{ config, lib, pkgs, ... }:

{
  imports = [
    ./hyprland
    ./neovim
  ];

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

  programs.zoxide = {
    enable = true;
    enableBashIntegration = true;
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
      set -o vi

      # Example:
      # mkcd() { mkdir -p "$1" && cd "$1"; }
    '';
  };

  # Ported from https://github.com/matifuentes2/dotfiles. The original prompt
  # uses an Apple glyph; use the NixOS glyph on this host instead.
  programs.starship = {
    enable = true;
    enableBashIntegration = true;

    settings = {
      format = lib.concatStrings [
        "[░▒▓](#a3aed2)"
        "[  ](bg:#a3aed2 fg:#090c0c)"
        "[](bg:#3f5683 fg:#a3aed2)"
        "$directory"
        "[](fg:#3f5683 bg:#394260)"
        "$git_branch"
        "$git_status"
        "[](fg:#394260 bg:#212736)"
        "$nodejs"
        "$rust"
        "$golang"
        "$php"
        "[](fg:#212736 bg:#1d2230)"
        "$time"
        "[ ](fg:#1d2230)"
        "\n$character"
      ];

      directory = {
        style = "fg:#e3e5e5 bg:#3f5683";
        format = "[ $path ]($style)";
        truncation_length = 3;
        truncation_symbol = "…/";
        substitutions = {
          Documents = "󰈙 ";
          Downloads = " ";
          Music = " ";
          Pictures = " ";
        };
      };

      git_branch = {
        symbol = "";
        style = "bg:#394260";
        format = "[[ $symbol $branch ](fg:#769ff0 bg:#394260)]($style)";
      };

      git_status = {
        style = "bg:#394260";
        format = "[[($all_status$ahead_behind )](fg:#769ff0 bg:#394260)]($style)";
      };

      nodejs = {
        symbol = "";
        style = "bg:#212736";
        format = "[[ $symbol ($version) ](fg:#769ff0 bg:#212736)]($style)";
      };

      rust = {
        symbol = "";
        style = "bg:#212736";
        format = "[[ $symbol ($version) ](fg:#769ff0 bg:#212736)]($style)";
      };

      golang = {
        symbol = "";
        style = "bg:#212736";
        format = "[[ $symbol ($version) ](fg:#769ff0 bg:#212736)]($style)";
      };

      php = {
        symbol = "";
        style = "bg:#212736";
        format = "[[ $symbol ($version) ](fg:#769ff0 bg:#212736)]($style)";
      };

      time = {
        disabled = false;
        time_format = "%R";
        style = "bg:#1d2230";
        format = "[[  $time ](fg:#a0a9cb bg:#1d2230)]($style)";
      };

      character.vicmd_symbol = "N >";
    };
  };

  # Lets Home Manager manage itself for this user.
  programs.home-manager.enable = true;
}
