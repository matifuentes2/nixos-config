{ config, lib, ... }:

# Owns Pi's native MCP configuration so platform modules can contribute
# servers without importing each other (for example, Cua Driver on desktops
# but not on WSL2).
{
  options.pi.mcpServers = lib.mkOption {
    type = lib.types.attrsOf (lib.types.attrsOf lib.types.anything);
    default = { };
    description = "Servers written to ~/.pi/agent/mcp.json for Pi's builtin:mcp extension.";
  };

  # Pi's native MCP extension reads these pinned servers. It connects enabled
  # servers in the background; tools use native codemode exposure by default.
  config.home.file.".pi/agent/mcp.json" = {
    force = true;
    text = builtins.toJSON { inherit (config.pi) mcpServers; };
  };
}
