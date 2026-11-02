{ lib, pkgs }:

let
  version = "0.9.1";
  sources = {
    x86_64-linux = {
      url = "https://github.com/herdrdev/herdr/releases/download/v${version}/herdr-linux-x86_64";
      hash = "sha256-KgL+0WvrZR7wBuHUPwSPZSyk3FitBTzS1ERQVj1cVLc=";
    };
    aarch64-linux = {
      url = "https://github.com/herdrdev/herdr/releases/download/v${version}/herdr-linux-aarch64";
      hash = "sha256-9Mz03nRfLLmjmpg+m6NwPa1Q7CpY3qgwJs6rchu9jZ4=";
    };
    aarch64-darwin = {
      url = "https://github.com/herdrdev/herdr/releases/download/v${version}/herdr-macos-aarch64";
      hash = "sha256-X8en5636ylb6gKqJ3LAlaTNXJo2rgoW5zi0IojE8id4=";
    };
    x86_64-darwin = {
      url = "https://github.com/herdrdev/herdr/releases/download/v${version}/herdr-macos-x86_64";
      hash = "sha256-BTvgY5k1/lSrXvvbRmUQVOT2p1OltDFTyIvWkSvOHpQ=";
    };
  };
  source = sources.${pkgs.stdenv.hostPlatform.system};
in
# Use pinned upstream binaries to avoid local Rust (and Herdr Zig) builds.
pkgs.stdenvNoCC.mkDerivation {
  pname = "herdr";
  inherit version;
  src = pkgs.fetchurl { inherit (source) url hash; };
  dontUnpack = true;
  dontBuild = true;
  # Preserve upstream binaries, including Darwin code signatures.
  dontFixup = true;
  installPhase = ''
    runHook preInstall
    install -Dm755 "$src" "$out/bin/herdr"
    runHook postInstall
  '';
  meta = {
    description = "Terminal workspace manager for AI coding agents (upstream binary)";
    homepage = "https://github.com/herdrdev/herdr";
    license = lib.licenses.asl20;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    mainProgram = "herdr";
    platforms = builtins.attrNames sources;
  };
}
