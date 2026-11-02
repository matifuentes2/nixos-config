{ ... }:

{
  # Share the reviewed x86-64 Linux release between Lenovo and WSL2.
  nixpkgs.overlays = [
    (final: prev: {
      claude-code = prev.claude-code.override {
        manifest = {
          version = "2.1.316";
          platforms.linux-x64.checksum = "fd13c70000fec3f2116dfbcbb6121210b4a29328bf0e46210a59dd594a67d824";
        };
      };
    })
  ];
}
