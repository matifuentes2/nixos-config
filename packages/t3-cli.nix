{
  lib,
  stdenvNoCC,
  fetchurl,
  makeWrapper,
  pkgs,
}:

# Headless T3 Code server and CLI (`t3`), from the upstream standalone release.
# The executable embeds its JavaScript payload, so it is installed unmodified:
# patchelf would corrupt the appended payload. It and its native Node add-ons
# (node-pty, keyring, ffi) run through nix-ld, which the host must enable.
let
  # T3 pins and verifies Chrome Headless Shell's archive itself. Its downloaded
  # ELF and the ldd-based startup diagnostic both need this environment on NixOS.
  browserLibraries = with pkgs; [
    glib
    nspr
    nss
    atk
    dbus
    libX11
    libXcomposite
    libXdamage
    libXext
    libXfixes
    libXrandr
    libgbm
    expat
    libxcb
    libxkbcommon
    systemd
    alsa-lib
    at-spi2-core
  ];
  release =
    if stdenvNoCC.hostPlatform.isAarch64 then
      {
        arch = "arm64";
        sha256 = "52023bc5728a4dee4de361ad6fef7c236f1efb2742ff25e29d5c55e2fb662eea";
      }
    else
      {
        arch = "x64";
        sha256 = "0141025335da334759cecd8db3483e09772f3600ca03674698524e7d94291362";
      };
in
stdenvNoCC.mkDerivation rec {
  pname = "t3-cli";
  version = "0.1.9";

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
    makeWrapper $out/libexec/t3/t3 $out/bin/t3 \
      --prefix LD_LIBRARY_PATH : ${lib.makeLibraryPath browserLibraries}
    runHook postInstall
  '';

  passthru.browserLibraryPath = lib.makeLibraryPath browserLibraries;

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
