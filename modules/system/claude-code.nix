{ ... }:

{
  # Pin the same upstream release on every host. Checksums come from
  # https://downloads.claude.ai/claude-code-releases/2.1.322/manifest.json.
  nixpkgs.overlays = [
    (final: prev: {
      claude-code = prev.claude-code.override {
        manifest = {
          version = "2.1.322";
          platforms = {
            darwin-arm64.checksum = "a9d237949db816a0b7afd88a9a8e1df36b3a597a30f5a41d1c0539eb180a3450";
            linux-arm64.checksum = "f220ca50ea4f3222043ff83cc224a1262e0196e9897acc0871efa94235b0c1fd";
            linux-x64.checksum = "bfb3703ad5380242328459bc62ada4bde8ae7ba57c6e1eeadb9c00e08874c478";
          };
        };
      };
    })
  ];
}
