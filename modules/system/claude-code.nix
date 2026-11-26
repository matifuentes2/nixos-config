{ ... }:

{
  # Pin the same upstream release on every host. Checksums come from
  # https://downloads.claude.ai/claude-code-releases/2.1.332/manifest.json.
  nixpkgs.overlays = [
    (final: prev: {
      claude-code = prev.claude-code.override {
        manifest = {
          version = "2.1.332";
          platforms = {
            darwin-arm64.checksum = "5b8214f8f082f3187420b27b4063b9b4f4d9412cd66ea436d6d1966ad582700f";
            linux-arm64.checksum = "50c305fcb8912851ce774429131d94ed6f84edbe3d8d0ed7a59dade5d893acc0";
            linux-x64.checksum = "a2df1f41bb00250992926420d0063f89b127cb81abdd284dbefb80c50ff1d026";
          };
        };
      };
    })
  ];
}
