{ ... }:

{
  # Pin the same upstream release on every host. Checksums come from
  # https://downloads.claude.ai/claude-code-releases/2.1.325/manifest.json.
  nixpkgs.overlays = [
    (final: prev: {
      claude-code = prev.claude-code.override {
        manifest = {
          version = "2.1.325";
          platforms = {
            darwin-arm64.checksum = "84590fefe6338be9087f5814b61f9a54c5f21524163a4c127cb5a808e31009f2";
            linux-arm64.checksum = "7b6e484b1989a5a14a4b354709ccc8672518a3ec5b9ccd7981fc6254327fde67";
            linux-x64.checksum = "0dc4f4a9a165fc60746d7ae8489712e5fc352f1e7ad4eb22e7141bd0812eb0cf";
          };
        };
      };
    })
  ];
}
