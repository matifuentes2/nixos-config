{
  config,
  lib,
  pkgs,
  ...
}:

let
  t3Cli = pkgs.callPackage ../../packages/t3-cli.nix { };
  # Keep the desktop's ~/.t3 database/port separate from the persistent server.
  t3Headless = pkgs.writeShellApplication {
    name = "t3-headless";
    runtimeInputs = [ t3Cli ];
    text = ''
      export T3CODE_HOME=${lib.escapeShellArg "${config.xdg.dataHome}/t3-headless"}
      exec t3 "$@"
    '';
  };
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

  home.packages = [
    pkgs.tree
    t3Cli
    t3Headless
    pkgs.seahorse # Initialize/manage T3 Code's password-protected login keyring.
    (pkgs.callPackage ../../packages/t3-code.nix { })
  ];

  home.shellAliases.rebuild = "sudo nixos-rebuild switch --flake /etc/nixos#nixos";

  # Access remotely via SSH forwarding, not an unauthenticated public listener.
  # The Pi already enables lingering, so this starts without a desktop login.
  systemd.user.services.t3-server = {
    Unit = {
      Description = "T3 Code headless server";
      After = [ "network.target" ];
    };
    Service = {
      ExecStart = "${lib.getExe t3Headless} serve --host 127.0.0.1 --port 3774 --no-browser ${config.home.homeDirectory}";
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
