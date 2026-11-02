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
          version = "2.1.316";
          platforms.linux-x64.checksum = "fd13c70000fec3f2116dfbcbb6121210b4a29328bf0e46210a59dd594a67d824";
        };
      };
    })
  ];
}
