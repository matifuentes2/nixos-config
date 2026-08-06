{
  config,
  pkgs,
  username,
  ...
}:

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
  home.packages = with pkgs; [
  ];

  home.shellAliases.rebuild = "sudo darwin-rebuild switch --flake ~/nixos-config#macbook";

  home.file = {
    # Karabiner-Elements is installed by nix-darwin's Homebrew module. Keep its
    # active configuration and imported complex-modification rule reproducible.
    ".config/karabiner/karabiner.json".source = ./karabiner/karabiner.json;
    ".config/karabiner/assets/complex_modifications/1698155918.json".source =
      ./karabiner/assets/complex_modifications/1698155918.json;

    # Kitty is installed as a Homebrew cask, while Home Manager owns its
    # configuration and background image.
    ".config/kitty/background.jpg".source = ./kitty/background.jpg;
    # Replace the pre-existing dotfiles symlink during the first activation.
    ".config/kitty/kitty.conf".force = true;
    ".config/kitty/kitty.conf".text = builtins.replaceStrings
      [ "@backgroundImage@" ]
      [ "${config.home.homeDirectory}/.config/kitty/background.jpg" ]
      (builtins.readFile ./kitty/kitty.conf);
  };
}
