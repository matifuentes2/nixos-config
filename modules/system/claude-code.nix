{ ... }:

{
  # Pin the same upstream release on every host. Checksums come from
  # https://downloads.claude.ai/claude-code-releases/2.1.327/manifest.json.
  nixpkgs.overlays = [
    (final: prev: {
      claude-code = prev.claude-code.override {
        manifest = {
          version = "2.1.327";
          platforms = {
            darwin-arm64.checksum = "76d48205c926c8a6978cfc2171b631bcd01e20bbadd085638bb2ec57bea91c5b";
            linux-arm64.checksum = "acf0ef2f9da8d5ab08f193f007e19a06cbfb608b96a2f1f758d63a92a386cff8";
            linux-x64.checksum = "343c744baa14bfd38286a7cb90871051f04379956da6c5b803a9e66019a76ac9";
          };
        };
      };
    })
  ];
}
