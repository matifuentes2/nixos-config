{ lib, pkgs }:

# Cua Driver lets agents inspect and operate native desktop applications.
# Use upstream's pinned, checksummed release archives instead of the
# curl-to-shell installer, which mutates ~/.local/bin and self-updates.
let
  version = "0.38.0";
  tag = "cua-driver-rs-v${version}";
  release = "https://github.com/trycua/cua/releases/download/${tag}";
  sources = {
    x86_64-linux = {
      url = "${release}/cua-driver-rs-${version}-linux-x86_64.tar.gz";
      hash = "sha256-owXL1TH5TWQTxdswDDPfaOOtvouSuWBM+OZFxfbLH6M=";
    };
    # Upstream labels Linux arm64 builds as a preview.
    aarch64-linux = {
      url = "${release}/cua-driver-rs-${version}-linux-arm64.tar.gz";
      hash = "sha256-7YpRElreiAfHcXw93hPWK9MeYnXmteJEbPAY0LAdk7M=";
    };
    # The universal archive is the one upstream's installer uses on macOS: it
    # contains the signed CuaDriver.app that owns the TCC grants.
    aarch64-darwin = {
      url = "${release}/cua-driver-rs-${version}-darwin-universal.tar.gz";
      hash = "sha256-EhzyDK/Sz6ad1yDolnNQxkBrIuVYvmiJ3noa4zQ7bUs=";
    };
  };
  system = pkgs.stdenv.hostPlatform.system;
  source = sources.${system} or (throw "Unsupported Cua Driver system: ${system}");
  isDarwin = pkgs.stdenv.hostPlatform.isDarwin;

  # Agent guidance published with the same release; installed as a Pi skill.
  skills = pkgs.fetchurl {
    url = "${release}/${tag}-skills.tar.gz";
    hash = "sha256-D+PWB+chLWxYByokGRYzQgYdz1y4m6EkPepZPX4zvg8=";
  };

  # The binary is pinned by Nix. Disable upstream's self-update check and
  # content-free telemetry for every process this wrapper starts.
  wrapperFlags = [
    "--set-default"
    "CUA_DRIVER_RS_UPDATE_CHECK"
    "false"
    "--set-default"
    "CUA_DRIVER_RS_TELEMETRY_ENABLED"
    "false"
  ]
  ++ lib.optionals (!isDarwin) [
    # Hyprland is Wayland-native. Without this, only XWayland windows are
    # discoverable; with it, the driver selects its Hyprland adapters.
    "--set-default"
    "CUA_DRIVER_RS_ENABLE_WAYLAND"
    "1"
    # Hyprland desktop capture shells out to grim.
    "--prefix"
    "PATH"
    ":"
    (lib.makeBinPath [ pkgs.grim ])
  ];
in
pkgs.stdenv.mkDerivation {
  pname = "cua-driver";
  inherit version;
  src = pkgs.fetchurl { inherit (source) url hash; };

  nativeBuildInputs = [
    pkgs.makeWrapper
  ]
  ++ lib.optionals (!isDarwin) [ pkgs.autoPatchelfHook ];
  buildInputs = lib.optionals (!isDarwin) [
    pkgs.libX11
    pkgs.libXi
    pkgs.libxkbcommon
    pkgs.stdenv.cc.cc.lib
  ];

  dontConfigure = true;
  dontBuild = true;
  # Rewriting Mach-O files would invalidate the bundle's Developer ID
  # signature, and with it every Accessibility/Screen Recording grant.
  dontFixup = isDarwin;

  installPhase = ''
    runHook preInstall
    mkdir -p "$out/libexec/cua-driver" "$out/share/cua-driver"
    cp -R . "$out/libexec/cua-driver/"
    mkdir -p "$out/share/cua-driver/skill"
    tar -xzf ${skills} --strip-components=1 -C "$out/share/cua-driver/skill"
  ''
  + (
    if isDarwin then
      ''
        # The CLI must resolve to /Applications/CuaDriver.app, where the
        # nix-darwin activation installs a copy; the driver only trusts that
        # exact path for its daemon and permission grants.
        # The app is absent inside a clean build sandbox. Wrap an immutable
        # launcher instead, deferring the /Applications lookup until runtime.
        mkdir -p "$out/bin"
        makeWrapper ${pkgs.writeShellScript "cua-driver-app-launcher" ''
          exec /Applications/CuaDriver.app/Contents/MacOS/cua-driver "$@"
        ''} \
          "$out/bin/cua-driver" ${lib.escapeShellArgs wrapperFlags}
      ''
    else
      ''
        makeWrapper "$out/libexec/cua-driver/cua-driver" "$out/bin/cua-driver" \
          ${lib.escapeShellArgs wrapperFlags}
      ''
  )
  + ''
    runHook postInstall
  '';

  meta = {
    description = "Background computer-use driver for AI agents (upstream binary)";
    homepage = "https://github.com/trycua/cua";
    license = lib.licenses.mit;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    mainProgram = "cua-driver";
    platforms = builtins.attrNames sources;
  };
}
