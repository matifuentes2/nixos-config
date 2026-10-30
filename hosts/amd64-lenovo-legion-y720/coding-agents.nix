{ ... }:

{
  # Override only this host's package set, including Codex inherited by Home
  # Manager from common.nix. Keep other hosts and the shared nixpkgs lock intact.
  nixpkgs.overlays = [
    (final: prev: {
      codex = final.callPackage ../../packages/codex-linux.nix { };
      claude-code = prev.claude-code.override {
        manifest = {
          version = "2.1.312";
          platforms.linux-x64.checksum = "4f4178ce41d83e23341ebfbaecdbcf8ea6bf7baea0690025abe49eeec3a5d01d";
        };
      };
    })
  ];
}
