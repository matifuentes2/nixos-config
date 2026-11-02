{ lib, pkgs }:

let
  version = "0.72.0";
  sources = {
    x86_64-linux = {
      url = "https://github.com/max-sixty/worktrunk/releases/download/v${version}/worktrunk-x86_64-unknown-linux-musl.tar.xz";
      hash = "sha256-6RvHzrBiOUKnlzF/VlQagl1qNuJNBVmFqCmdMDRb40Y=";
    };
    aarch64-linux = {
      url = "https://github.com/max-sixty/worktrunk/releases/download/v${version}/worktrunk-aarch64-unknown-linux-musl.tar.xz";
      hash = "sha256-L2tF/QWS5LD2bKPDTLr5DHZDp+qr+KnEsOEtSCUaCGw=";
    };
    aarch64-darwin = {
      url = "https://github.com/max-sixty/worktrunk/releases/download/v${version}/worktrunk-aarch64-apple-darwin.tar.xz";
      hash = "sha256-fmz3mj72dVkkBDGq6TwTfZorKKjM21W2Tt6tkEsh/3M=";
    };
    x86_64-darwin = {
      url = "https://github.com/max-sixty/worktrunk/releases/download/v${version}/worktrunk-x86_64-apple-darwin.tar.xz";
      hash = "sha256-I1a+5DpmiKA9JLJ90Yzg2x9GZvER7gbzyCnR8khHJAE=";
    };
  };
  source = sources.${pkgs.stdenv.hostPlatform.system};
in
# Use pinned upstream binaries to avoid local Rust (and Herdr Zig) builds.
pkgs.stdenvNoCC.mkDerivation {
  pname = "worktrunk";
  inherit version;
  src = pkgs.fetchurl { inherit (source) url hash; };
  dontBuild = true;
  # Preserve upstream binaries, including Darwin code signatures.
  dontFixup = true;
  installPhase = ''
    runHook preInstall
    install -Dm755 wt "$out/bin/wt"
    install -Dm755 git-wt "$out/bin/git-wt"
    install -Dm644 LICENSE "$out/share/licenses/worktrunk/LICENSE"
    runHook postInstall
  '';
  meta = {
    description = "CLI for Git worktree management (upstream binary)";
    homepage = "https://github.com/max-sixty/worktrunk";
    license = [
      lib.licenses.mit
      lib.licenses.asl20
    ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    mainProgram = "wt";
    platforms = builtins.attrNames sources;
  };
}
