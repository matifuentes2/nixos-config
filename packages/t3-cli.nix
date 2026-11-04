{
  lib,
  stdenvNoCC,
  fetchurl,
  makeWrapper,
}:

# Headless T3 Code server and CLI (`t3`), from the upstream standalone release.
# The executable embeds its JavaScript payload, so it is installed unmodified:
# patchelf would corrupt the appended payload. It and its native Node add-ons
# (node-pty, keyring, ffi) run through nix-ld, which the host must enable.
let
  release =
    if stdenvNoCC.hostPlatform.isAarch64 then
      {
        arch = "arm64";
        sha256 = "5a528e23af394cc6f359036d3cb8441fda14129d477630fc6c53e4f4a1025bc8";
      }
    else
      {
        arch = "x64";
        sha256 = "c089892bf7922e2e73c6f44a5d1ea125c99f70e378c18361cbbed2fba1920e6c";
      };
in
stdenvNoCC.mkDerivation rec {
  pname = "t3-cli";
  version = "0.1.7";

  src = fetchurl {
    url = "https://github.com/pingdotgg/t3code/releases/download/v${version}/t3-${version}-linux-${release.arch}.tar.gz";
    # Matches the release's published SHA256SUMS.
    inherit (release) sha256;
  };

  nativeBuildInputs = [ makeWrapper ];

  dontConfigure = true;
  dontBuild = true;
  # Keep the binary and prebuilt add-ons byte-for-byte as released.
  dontFixup = true;

  installPhase = ''
    runHook preInstall
    mkdir -p $out/libexec/t3 $out/bin
    cp -r . $out/libexec/t3
    makeWrapper $out/libexec/t3/t3 $out/bin/t3
    runHook postInstall
  '';

  meta = {
    description = "Headless server and CLI for T3 Code";
    homepage = "https://github.com/pingdotgg/t3code";
    license = lib.licenses.mit;
    mainProgram = "t3";
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}
