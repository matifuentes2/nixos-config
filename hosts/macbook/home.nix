{
  config,
  omp,
  pkgs,
  username,
  ...
}:

let
  ompPackage = omp.packages.${pkgs.stdenv.hostPlatform.system}.omp;
  ompPiVim = pkgs.callPackage ../../omp-extensions/pi-vim { };
  ompWithNativeChat = pkgs.writeShellApplication {
    name = "omp";
    text = ''
      if [[ -z "''${ORCA_PANE_KEY:-}" ]]; then
        exec ${pkgs.lib.getExe ompPackage} "$@"
      fi

      # Keep OMP's session storage aligned with Orca's Native Chat reader.
      export PI_CODING_AGENT_DIR="$HOME/.omp/agent"

      # Orca's generated OMP hook uses fire-and-forget delivery that OMP 18 can
      # drop before Native Chat receives the provider session. Replace only
      # that managed hook; preserve every user-supplied extension argument.
      args=()
      while (( $# > 0 )); do
        if [[
          ( "$1" == "--extension" || "$1" == "-e" )
          && $# -ge 2
          && -n "''${ORCA_OMP_STATUS_EXTENSION:-}"
          && "$2" == "$ORCA_OMP_STATUS_EXTENSION"
        ]]; then
          shift 2
          continue
        fi
        if [[
          -n "''${ORCA_OMP_STATUS_EXTENSION:-}"
          && "$1" == "--extension=$ORCA_OMP_STATUS_EXTENSION"
        ]]; then
          shift
          continue
        fi
        args+=("$1")
        shift
      done

      exec ${pkgs.lib.getExe ompPackage} \
        "''${args[@]}" \
        --extension ${./omp-orca-status.ts}
    '';
  };
in

{
  imports = [
    ../../modules/home/common.nix
    ../../modules/home/darwin.nix
  ];

  home.username = username;
  home.homeDirectory = "/Users/${username}";

  # This is the first Home Manager version used for this macOS host.
  home.stateVersion = "25.11";

  # Add packages used only on this Mac here.
  home.packages = [
    ompWithNativeChat
  ];

  home.shellAliases.rebuild = "sudo darwin-rebuild switch --flake ~/nixos-config#macbook";

  home.file = {
    # Karabiner-Elements is installed by nix-darwin's Homebrew module. Keep its
    # active configuration and imported complex-modification rule reproducible.
    ".config/karabiner/karabiner.json".source = ./karabiner/karabiner.json;
    ".config/karabiner/assets/complex_modifications/1698155918.json".source =
      ./karabiner/assets/complex_modifications/1698155918.json;

    # OMP loads this patched Pi extension from the immutable Nix store.
    ".omp/agent/extensions/pi-vim" = {
      force = true;
      source = ompPiVim;
    };
    # Kitty is installed as a Homebrew cask, while Home Manager owns its
    # configuration and background image.
    ".config/kitty/background.jpg".source = ./kitty/background.jpg;
    # Replace the pre-existing dotfiles symlink during the first activation.
    ".config/kitty/kitty.conf".force = true;
    ".config/kitty/kitty.conf".text =
      builtins.replaceStrings
        [ "@backgroundImage@" ]
        [ "${config.home.homeDirectory}/.config/kitty/background.jpg" ]
        (builtins.readFile ./kitty/kitty.conf);
  };
}
