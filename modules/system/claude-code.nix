{ ... }:

{
  # Pin the same upstream release on every host. Checksums come from
  # https://downloads.claude.ai/claude-code-releases/2.1.330/manifest.json.
  nixpkgs.overlays = [
    (final: prev: {
      claude-code = prev.claude-code.override {
        manifest = {
          version = "2.1.330";
          platforms = {
            darwin-arm64.checksum = "f7c5093b9dd6560d08af28bc27b123fb55091deae3180ac39df199522da86815";
            linux-arm64.checksum = "6016f90cac783e367fb1aa97c768a2efb94a0128a5b46b70fb3d8fcbbd9dd444";
            linux-x64.checksum = "f390eaa0814e6a1bff74cbb47acb74cb9c89d30ced809fe0af5af00c7bfe8ebb";
          };
        };
      };
    })
  ];
}
