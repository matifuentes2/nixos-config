{ ... }:

{
  # Keep system consumers on the same pinned Codex release as Home Manager.
  # The Claude Code version override remains specific to this host.
  nixpkgs.overlays = [
    (final: prev: {
      codex = import ../../packages/codex.nix {
        pkgs = final;
        inherit (final) lib;
      };
      claude-code = prev.claude-code.override {
        manifest = {
          version = "2.1.312";
          platforms.linux-x64.checksum = "4f4178ce41d83e23341ebfbaecdbcf8ea6bf7baea0690025abe49eeec3a5d01d";
        };
      };
    })
  ];
}
