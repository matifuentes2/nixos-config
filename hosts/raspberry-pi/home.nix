{
  config,
  lib,
  pkgs,
  ...
}:

let
  t3Cli = pkgs.callPackage ../../packages/t3-cli.nix { };
in
{
  imports = [
    ../../modules/home/common.nix
    ../../modules/home/linux.nix
  ];

  home.username = "pi";
  home.homeDirectory = "/home/pi";

  # Keep this at the version used when Home Manager was first configured.
  home.stateVersion = "25.11";

  # GTK's Vulkan renderer crashes in the Pi's Broadcom driver when Walker opens.
  systemd.user.services.walker.Service.Environment = [
    "GSK_RENDERER=ngl"
  ];

  # Load after the shared look-and-feel module. Keep Pi window movement cheap;
  # the other Linux desktops retain their animations.
  wayland.windowManager.hyprland.extraLuaFiles."desktop/zz-pi" = ''
    hl.config({ animations = { enabled = false } })
  '';

  programs.hyprlock.settings.background = lib.mkForce [
    {
      monitor = "";
      path = "${pkgs.callPackage ../../hyprland/wallpaper.nix { }}";
      blur_passes = 0;
    }
  ];

  home.packages = [
    pkgs.tree
    t3Cli
    pkgs.seahorse # Initialize/manage T3 Code's password-protected login keyring.
    (pkgs.callPackage ../../packages/t3-code.nix { })
  ];

  home.shellAliases.rebuild = "sudo nixos-rebuild switch --flake /etc/nixos#nixos";

  # One-time migration from the old isolated server. Move the entire directory
  # only after stopping the service (SQLite WAL files must move with the DB).
  # Preserve any desktop state rather than trying to merge two databases.
  home.activation.unifyT3State = lib.hm.dag.entryBetween [ "reloadSystemd" ] [ "linkGeneration" ] ''
    legacy=${lib.escapeShellArg "${config.xdg.dataHome}/t3-headless"}
    target=${lib.escapeShellArg "${config.home.homeDirectory}/.t3"}
    if [ -d "$legacy" ]; then
      if [ -L "$legacy" ] || [ -L "$target" ]; then
        echo "Refusing T3 migration through symlinks; migrate the state manually." >&2
        exit 1
      fi
      if ${pkgs.psmisc}/bin/fuser "$target"/{userdata,dev}/statev2.sqlite >/dev/null 2>&1; then
        echo "Close the local T3 desktop/server before migrating its default state." >&2
        exit 1
      fi
      run env XDG_RUNTIME_DIR="''${XDG_RUNTIME_DIR:-/run/user/$(${pkgs.coreutils}/bin/id -u)}" \
        ${pkgs.systemd}/bin/systemctl --user stop t3-server.service
      if [ -e "$target" ]; then
        if [ -n "''${DRY_RUN:-}" ]; then
          echo "Would back up $target before migrating T3 server state"
        else
          backup="$(${pkgs.coreutils}/bin/mktemp -d "$target-before-unification.XXXXXXXX")"
          ${pkgs.coreutils}/bin/mv -- "$target" "$backup/state"
          echo "Previous T3 default state preserved in $backup/state"
        fi
      fi
      run ${pkgs.coreutils}/bin/mv -- "$legacy" "$target"
    fi
  '';

  # Access remotely via SSH forwarding, not an unauthenticated public listener.
  # The Pi already enables lingering, so this starts without a desktop login.
  systemd.user.services.t3-server = {
    Unit = {
      Description = "T3 Code headless server";
      After = [ "network.target" ];
    };
    Service = {
      ExecStart = "${lib.getExe t3Cli} serve --host 127.0.0.1 --port 3774 --no-browser ${config.home.homeDirectory}";
      WorkingDirectory = config.home.homeDirectory;
      Environment = [
        "PATH=${config.home.profileDirectory}/bin:/run/current-system/sw/bin:/run/wrappers/bin"
      ];
      Restart = "on-failure";
      RestartSec = 5;
      UMask = "0077";
    };
    Install.WantedBy = [ "default.target" ];
  };
}
