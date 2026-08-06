{ username, ... }:

{
  imports = [
    ../../modules/system/common.nix
  ];

  networking.hostName = "macbook";
  networking.computerName = "MacBook";

  # Required by user-scoped nix-darwin options and Home Manager.
  system.primaryUser = username;
  users.users.${username}.home = "/Users/${username}";

  # Configure the shell shipped with macOS. User-level zsh configuration lives
  # in modules/home/darwin.nix.
  programs.zsh.enable = true;

  homebrew = {
    enable = true;
    casks = [
      "betterdisplay"
      "docker-desktop"
      "hiddenbar"
      "karabiner-elements"
      "raycast"
      "rectangle"
    ];
  };

  # Keep this value when upgrading nix-darwin; it controls compatibility
  # defaults rather than the installed macOS version.
  system.stateVersion = 6;
}
