{ lib, pkgs, ... }:

let
  t3Cli = pkgs.callPackage ../../packages/t3-cli.nix { };
  codex = import ../../packages/codex.nix { inherit lib pkgs; };
  agentHome = "/home/coding-agent";
in
{
  # Keep repository execution separate from the passwordless-sudo administrator.
  users.users.coding-agent = {
    isNormalUser = true;
    createHome = true;
    home = agentHome;
    group = "coding-agent";
    linger = true;
    packages = with pkgs; [
      t3Cli
      codex
      git
      gh
      nodejs
      python3
      ripgrep
      curl
      jq
    ];
  };
  users.groups.coding-agent = { };

  # T3's standalone executable and native add-ons must remain unmodified.
  programs.nix-ld = {
    enable = true;
    libraries = [
      pkgs.libsecret
      pkgs.libffi
    ];
  };

  # A user service provides a user bus and the same HOME as interactive T3
  # commands. ConditionUser prevents its global unit from running for admins.
  systemd.user.services.t3-server = {
    description = "T3 Code coding-agent orchestration server";
    wantedBy = [ "default.target" ];
    unitConfig.ConditionUser = "coding-agent";
    serviceConfig = {
      ExecStart = "${lib.getExe t3Cli} serve --host 127.0.0.1 --port 3773 --no-browser ${agentHome}";
      WorkingDirectory = agentHome;
      Environment = [
        "PATH=/etc/profiles/per-user/coding-agent/bin:/run/current-system/sw/bin:/run/wrappers/bin"
      ];
      Restart = "on-failure";
      RestartSec = 5;
      UMask = "0077";
    };
  };

  # No public listener or firewall exception. Remote access is through an SSH
  # tunnel or an explicitly configured Tailscale Serve mapping, plus T3 pairing.
}
