{
  config,
  lib,
  pkgs,
  ...
}:

let
  codex = import ../../packages/codex.nix { inherit lib pkgs; };
  pool = config.services.cua-driver.agentDesktop.pool.clientPackage;
in
{
  imports = [
    ../../modules/home/pi-mcp.nix
    ../../modules/home/cua-driver.nix
  ];

  home.username = "coding-agent";
  home.homeDirectory = "/home/coding-agent";
  home.stateVersion = "26.11";

  services.cua-driver.agentDesktop = {
    enable = true;
    headless = true;
    pool = {
      enable = true;
      slots = 2;
      memoryMax = "4G";
      slotMemoryMax = "2G";
      swapMax = "512M";
      cpuQuota = "200%";
      slotCPUQuota = "200%";
    };
  };

  # Only the broker starts at boot. Desktop slots are started by leases; keep
  # the shared legacy desktop available solely for explicit administration.
  systemd.user.services.cua-agent-desktop.Install.WantedBy = lib.mkForce [ ];
  systemd.user.services.cua-driver.Install.WantedBy = lib.mkForce [ ];

  # Update just the managed MCP entry, preserving the user's model settings,
  # project trust, and credentials in the existing writable Codex config.
  home.activation.configureCuaMcp = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    run ${lib.getExe codex} mcp add cua-driver -- ${pool}/bin/cua-pool mcp
  '';
}
