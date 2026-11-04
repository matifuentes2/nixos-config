{
  config,
  lib,
  pkgs,
  ...
}:

# Cua Driver gives Pi and Claude Code computer use: it inspects and operates
# native desktop applications through accessibility APIs, screenshots, and input.
# Import this only on hosts with a desktop session (Linux desktops and macOS),
# not WSL2.
let
  cuaDriver = pkgs.callPackage ../../packages/cua-driver.nix { };
  isLinux = pkgs.stdenv.hostPlatform.isLinux;
  # One runtime per desktop session, shared by Pi's MCP connection and the
  # `cua-driver call` CLI that the skill prefers. This is upstream's default.
  linuxSocket = "${config.home.homeDirectory}/.cache/cua-driver/cua-driver.sock";
in
{
  home.packages = [ cuaDriver ];

  # On macOS `cua-driver mcp` proxies to /Applications/CuaDriver.app (installed
  # by hosts/macbook) and starts it on demand, so the app keeps its TCC grants.
  # On Linux it attaches to the session daemon below instead of starting a
  # second, separately permissioned runtime.
  pi.mcpServers.cua-driver = {
    command = lib.getExe cuaDriver;
    args = [
      "mcp"
    ]
    ++ lib.optionals isLinux [
      "--socket"
      linuxSocket
    ];
  };

  # Upstream's agent guidance (tool choice, element tokens, verification),
  # pinned to the same release as the binary. Claude Code uses the skill and
  # CLI directly; it does not need an MCP registration.
  home.file.".pi/agent/skills/cua-driver" = {
    source = "${cuaDriver}/share/cua-driver/skill";
    recursive = true;
  };

  home.file.".claude/skills/cua-driver" = {
    source = "${cuaDriver}/share/cua-driver/skill";
    recursive = true;
  };

  # The daemon must run inside the graphical session so it inherits the
  # Wayland/XWayland display and the accessibility (AT-SPI) session bus.
  systemd.user.services.cua-driver = lib.mkIf isLinux {
    Unit = {
      Description = "Cua Driver computer-use daemon";
      Documentation = "https://cua.ai/docs/cua-driver";
      PartOf = [ "graphical-session.target" ];
      After = [ "graphical-session.target" ];
    };
    Service = {
      ExecStart = "${lib.getExe cuaDriver} serve --socket ${linuxSocket}";
      Restart = "on-failure";
      RestartSec = 5;
      # Computer use is interactive and should not compete with services.
      Nice = 5;
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };
}
