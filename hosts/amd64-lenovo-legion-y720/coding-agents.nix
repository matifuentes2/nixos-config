{ ... }:

{
  # Keep system consumers on the same pinned Codex release as Home Manager.
  nixpkgs.overlays = [
    (final: prev: {
      codex = import ../../packages/codex.nix {
        pkgs = final;
        inherit (final) lib;
      };
    })
  ];
}
