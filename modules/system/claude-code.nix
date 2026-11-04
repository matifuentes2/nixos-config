{ ... }:

{
  # Pin the same upstream release on every host. Checksums come from
  # https://downloads.claude.ai/claude-code-releases/2.1.318/manifest.json.
  nixpkgs.overlays = [
    (final: prev: {
      claude-code = prev.claude-code.override {
        manifest = {
          version = "2.1.318";
          platforms = {
            darwin-arm64.checksum = "677a2ea7bf576cedd20e191d973914ed8a41796f53a63b1923381ddc4d5b5e7d";
            linux-arm64.checksum = "53a0d7e219d7b0804ecba5dbc002745e89f786cc946d2de85a6470d5b2d1fb06";
            linux-x64.checksum = "708c77b204db30086ff6f1ed34577bda03e1be74ced80557cbf7b54249ebf0bd";
          };
        };
      };
    })
  ];
}
