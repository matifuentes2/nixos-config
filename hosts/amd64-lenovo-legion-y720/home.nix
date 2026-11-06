{
  config,
  lib,
  pkgs,
  username,
  ...
}:

let
  laptopMonitor = "eDP-1";
  externalMonitor = "HDMI-A-1";
in
{
  imports = [
    ../../modules/home/common.nix
    ../../modules/home/linux.nix
  ];

  home.username = username;
  home.homeDirectory = "/home/${username}";

  # Keep this at the version used when Home Manager was first configured.
  home.stateVersion = "26.11";

  # Run computer use on a headless X11 desktop; Cua Driver cannot type on
  # Hyprland. See docs/cua-driver.md.
  services.cua-driver.agentDesktop.enable = true;

  # Codex and Claude Code are already provided by modules/home/common.nix.
  home.packages = [
    pkgs.awww
    pkgs.webcord
    pkgs.nwg-displays
    pkgs.rofi
    pkgs.rustdesk-flutter
    pkgs.seahorse # Initialize/manage the password-protected login keyring.
    (pkgs.callPackage ../../packages/t3-code.nix { })
    pkgs.tree
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

    -- Pin workspaces 1-5 to the external HDMI display and 7-9 to the laptop panel.
    -- Without HDMI, Hyprland cannot resolve that rule and opens 1-5 on the laptop.
    -- Hotplugging moves 1-5 to HDMI and back; unplugging moves everything to eDP-1.
    for ws = 1, 5 do
      hl.workspace_rule({ workspace = tostring(ws), monitor = "${externalMonitor}", default = ws == 1 })
    end
    for ws = 7, 9 do
      hl.workspace_rule({ workspace = tostring(ws), monitor = "${laptopMonitor}" })
    end
  '';

  # Show the pinned 1-5 only on the external bar. The laptop bar lists the
  # workspaces that exist there, so it never offers buttons for the other screen.
  programs.waybar.settings.mainBar."hyprland/workspaces".persistent-workspaces = lib.mkForce {
    ${externalMonitor} = map toString (lib.range 1 5);
  };

  home.shellAliases.rebuild = "sudo nixos-rebuild switch --flake ${config.home.homeDirectory}/dev/nixos-config#amd64-lenovo-legion-y720";
  home.shellAliases.rebuild-gaming = "sudo nixos-rebuild switch --flake ${config.home.homeDirectory}/dev/nixos-config#amd64-lenovo-legion-y720 --specialisation steam";
  home.shellAliases.refresh-apps = "${lib.getExe' pkgs.systemd "systemctl"} --user restart elephant.service";
}
