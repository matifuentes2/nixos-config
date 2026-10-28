{ lib, pkgs }:

let
  version = "0.165.0";
  sources = {
    aarch64-darwin = {
      target = "aarch64-apple-darwin";
      hash = "sha256-NNEjhNkPjgmwuauqvyoKwCpSCTsTFQSuryghB/VKRLI=";
    };
    x86_64-darwin = {
      target = "x86_64-apple-darwin";
      hash = "sha256-eS7KsFlgBr2fKGQwsnkKpIf9QPyi81HKMTrYWZFyAiY=";
    };
  };
  source = sources.${pkgs.stdenv.hostPlatform.system};
in
# Pin the complete upstream package rather than nixpkgs' older Codex release.
# Preserve its layout and signed binaries, including bundled helper resources.
pkgs.stdenvNoCC.mkDerivation {
  pname = "codex";
  inherit version;
  src = pkgs.fetchurl {
    url = "https://github.com/openai/codex/releases/download/rust-v${version}/codex-package-${source.target}.tar.gz";
    inherit (source) hash;
  };
  sourceRoot = ".";
  dontBuild = true;
  dontFixup = true;
  installPhase = ''
    runHook preInstall
    mkdir -p "$out"
    cp -R bin codex-package.json codex-path codex-resources "$out/"
    runHook postInstall
  '';
  meta = {
    description = "OpenAI coding agent (upstream release)";
    homepage = "https://github.com/openai/codex";
    license = lib.licenses.asl20;
    mainProgram = "codex";
    platforms = [
      "aarch64-darwin"
      "x86_64-darwin"
    ];
  };
}
