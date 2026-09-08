{
  config,
  lib,
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
    pkgs.awww
    pkgs.webcord
    pkgs.nwg-displays
    pkgs.rofi
    pkgs.tree
    pkgs.wlinhibit
  ];

  services.cliphist.enable = true;

  # Seed writable files on a fresh installation. nwg-displays owns subsequent
  # edits, so later activations must preserve both regular files and symlinks.
  home.activation.initializeDisplayConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    display_dir=${lib.escapeShellArg "${config.xdg.configHome}/hypr"}
    run mkdir -p "$display_dir"
    for name in monitors workspaces; do
      display_file="$display_dir/$name.conf"
      if [[ ! -e "$display_file" && ! -L "$display_file" ]]; then
        run ${lib.getExe' pkgs.coreutils "install"} -m 0644 \
          ${./display-default.conf} "$display_file"
      fi
    done
  '';

  # Let nwg-displays manage the local monitor layout without making the
  # connected display topology part of the declarative host configuration.
  # Start the wallpaper daemon with the Hyprland session.
  wayland.windowManager.hyprland.extraConfig = ''
    exec-once = awww-daemon
    source = ~/.config/hypr/monitors.conf
    source = ~/.config/hypr/workspaces.conf
  '';

  home.shellAliases.rebuild = "sudo nixos-rebuild switch --flake /etc/nixos#amd64-lenovo-legion-y720";
}
