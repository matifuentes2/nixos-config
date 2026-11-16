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
  services.cua-driver.agentDesktop.pool = {
    enable = true;
    slots = 4;
    memoryMax = "8G";
    slotMemoryMax = "3G";
    cpuQuota = "400%";
  };

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

  # T3 Code registers this handler itself. Keep it, because Home Manager now
  # owns mimeapps.list.
  xdg.mimeApps.defaultApplications."x-scheme-handler/t3code" = "com.t3tools.T3Code.desktop";

  # Omarchy's low-battery warning: one critical notification per discharge
  # once the charge reaches 10%.
  systemd.user.services.battery-monitor = {
    Unit.Description = "Warn when the battery is low";
    Service = {
      Type = "oneshot";
      ExecStart = lib.getExe (
        pkgs.writeShellApplication {
          name = "battery-monitor";
          runtimeInputs = [
            pkgs.coreutils
            pkgs.libnotify
          ];
          text = ''
            threshold=10
            notified="''${XDG_RUNTIME_DIR:-/tmp}/battery-monitor-notified"

            for battery in /sys/class/power_supply/BAT*; do
              [ -r "$battery/capacity" ] || continue
              capacity="$(cat "$battery/capacity")"
              status="$(cat "$battery/status")"

              if [ "$status" != Discharging ]; then
                rm -f "$notified"
              elif [ "$capacity" -le "$threshold" ] && [ ! -e "$notified" ]; then
                notify-send -u critical -i battery-caution 'Battery low' "$capacity% remaining. Plug in the charger."
                touch "$notified"
              fi
              exit 0
            done
          '';
        }
      );
    };
  };
  systemd.user.timers.battery-monitor = {
    Unit = {
      Description = "Check the battery level every 30 seconds";
      PartOf = [ "graphical-session.target" ];
    };
    Timer = {
      OnActiveSec = "10s";
      OnUnitActiveSec = "30s";
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };

  home.shellAliases.rebuild = "sudo nixos-rebuild switch --flake ${config.home.homeDirectory}/dev/nixos-config#amd64-lenovo-legion-y720";
  home.shellAliases.rebuild-gaming = "sudo nixos-rebuild switch --flake ${config.home.homeDirectory}/dev/nixos-config#amd64-lenovo-legion-y720 --specialisation steam";
  home.shellAliases.refresh-apps = "${lib.getExe' pkgs.systemd "systemctl"} --user restart elephant.service";
}
