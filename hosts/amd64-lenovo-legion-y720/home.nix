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

  # Codex and Claude Code are already provided by modules/home/common.nix.
  home.packages = [
    pkgs.awww
    pkgs.webcord
    pkgs.nwg-displays
    pkgs.rofi
    pkgs.seahorse # Initialize/manage the password-protected login keyring.
    (pkgs.callPackage ../../packages/t3-code.nix { })
    pkgs.tree
    pkgs.wlinhibit
  ];

  # Seed writable files on a fresh installation. nwg-displays owns subsequent
  # edits, so later activations must preserve both regular files and symlinks.
  home.activation.initializeDisplayConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    display_dir=${lib.escapeShellArg "${config.xdg.configHome}/hypr"}
    run mkdir -p "$display_dir"
    for name in monitors workspaces; do
      display_file="$display_dir/$name.lua"
      if [[ ! -e "$display_file" && ! -L "$display_file" ]]; then
        run ${lib.getExe' pkgs.coreutils "install"} -m 0644 \
          ${./display-default.lua} "$display_file"
      fi
    done
  '';

  # Let nwg-displays manage the local monitor layout without making the
  # connected display topology part of the declarative host configuration.
  # Start the wallpaper daemon with the Hyprland session.
  wayland.windowManager.hyprland.extraConfig = ''
    hl.on("hyprland.start", function()
      hl.exec_cmd("awww-daemon")
    end)

    for _, name in ipairs({ "monitors", "workspaces" }) do
      if package.searchpath(name, package.path) then
        require(name)
      end
    end
  '';

  home.shellAliases.rebuild = "sudo nixos-rebuild switch --flake /etc/nixos#amd64-lenovo-legion-y720";
}
