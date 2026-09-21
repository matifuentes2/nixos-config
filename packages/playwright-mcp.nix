{ lib, pkgs }:
let
  manifest = builtins.fromJSON (builtins.readFile ./playwright-mcp/package.json);
  server = pkgs.buildNpmPackage {
    pname = "playwright-mcp-package";
    version = manifest.version;
    src = ./playwright-mcp;
    npmDepsHash = "sha256-1ZleO0PO+7BEZKo7W+rh5qvwW7Rl+iX22ks0Y1T/ixM=";
    dontNpmBuild = true;
    # Extension mode uses the user's browser; never download bundled browsers.
    PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD = "1";
  };
in
pkgs.writeShellApplication {
  name = "playwright-mcp";
  text = ''
    # Read the optional browser-profile secret only at runtime. Never copy its
    # contents into the Nix store or source it as executable shell code.
    token_file="$HOME/.config/playwright-mcp/token"
    if [[ -r "$token_file" ]]; then
      PLAYWRIGHT_MCP_EXTENSION_TOKEN="$(< "$token_file")"
      export PLAYWRIGHT_MCP_EXTENSION_TOKEN
    fi

    exec ${lib.getExe pkgs.nodejs_22} \
      ${server}/lib/node_modules/${manifest.name}/node_modules/@playwright/mcp/cli.js "$@"
  '';
}
