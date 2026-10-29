{
  lib,
  stdenvNoCC,
  fetchurl,
  autoPatchelfHook,
  alsa-lib,
}:

stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "codex";
  version = "0.165.0";

  src = fetchurl {
    url = "https://github.com/openai/codex/releases/download/rust-v${finalAttrs.version}/codex-package-x86_64-unknown-linux-musl.tar.gz";
    sha256 = "e97c4463d7f146692a955d7b0e1c8cf48f97cd4d616cd45c5dcab2e8d9743316";
  };

  sourceRoot = ".";
  dontBuild = true;
  dontStrip = true;
  nativeBuildInputs = [ autoPatchelfHook ];
  buildInputs = [ alsa-lib ];

  # Keep the complete upstream layout so Codex can find its code-mode host,
  # ripgrep, sandbox helper and voice resources relative to the executable.
  # The core binaries are static; patch the bundled dynamic voice runtime.
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
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    mainProgram = "codex";
    platforms = [ "x86_64-linux" ];
  };
})
