{ lib, pkgs }:

let
  version = "0.166.0";
  sources = {
    aarch64-linux = {
      target = "aarch64-unknown-linux-musl";
      hash = "sha256-eCG3fdouYoP7H2PzFlF3onHaiDPoV89nPGyhyds7/MY=";
    };
    x86_64-linux = {
      target = "x86_64-unknown-linux-musl";
      hash = "sha256-HUSyi8SsmTfX01MiZLqmilB842SVag1Ou4VvMxze4lQ=";
    };
    aarch64-darwin = {
      target = "aarch64-apple-darwin";
      hash = "sha256-VaRAy1eflwq+fHmrGB5UsOpMQZvpnzM7vYaO66ycIfA=";
    };
    x86_64-darwin = {
      target = "x86_64-apple-darwin";
      hash = "sha256-HLZWkCML5ZgsZUuiZV46O1lNzpxVt4Dni/3+/4Kdetk=";
    };
  };
  source = sources.${pkgs.stdenv.hostPlatform.system};
in
# Pin the complete upstream package rather than nixpkgs' older Codex release.
# Preserve its layout and signed Darwin binaries, including helper resources.
# Linux core binaries are static; patch the bundled dynamic voice runtime.
pkgs.stdenvNoCC.mkDerivation {
  pname = "codex";
  inherit version;
  src = pkgs.fetchurl {
    url = "https://github.com/openai/codex/releases/download/rust-v${version}/codex-package-${source.target}.tar.gz";
    inherit (source) hash;
  };
  sourceRoot = ".";
  dontBuild = true;
  dontFixup = pkgs.stdenv.hostPlatform.isDarwin;
  dontStrip = true;
  nativeBuildInputs = lib.optionals pkgs.stdenv.hostPlatform.isLinux [
    pkgs.autoPatchelfHook
    pkgs.makeWrapper
  ];
  buildInputs = lib.optionals pkgs.stdenv.hostPlatform.isLinux [ pkgs.alsa-lib ];
  installPhase = ''
    runHook preInstall
    mkdir -p "$out"
    cp -R bin codex-package.json codex-path codex-resources "$out/"
    ${lib.optionalString pkgs.stdenv.hostPlatform.isLinux ''
      wrapProgram "$out/bin/codex" --prefix PATH : ${
        lib.makeBinPath [
          pkgs.ripgrep
          pkgs.bubblewrap
        ]
      }
    ''}
    runHook postInstall
  '';
  meta = {
    description = "OpenAI coding agent (upstream release)";
    homepage = "https://github.com/openai/codex";
    license = lib.licenses.asl20;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    mainProgram = "codex";
    platforms = [
      "aarch64-linux"
      "x86_64-linux"
      "aarch64-darwin"
      "x86_64-darwin"
    ];
  };
}
