{
  lib,
  appimageTools,
  fetchurl,
  makeDesktopItem,
  makeWrapper,
  stdenv,
}:

let
  pname = "t3-code";
  version = "0.1.8";
  release =
    if stdenv.hostPlatform.isAarch64 then
      {
        arch = "arm64";
        hash = "sha256-ai63kc+2C3hPFVGqbR4i0IcMweFVToFXSEYoFvEhZj4=";
      }
    else
      {
        arch = "x86_64";
        hash = "sha256-4Rdpi+TMWeXsFBbFHf1EKlPvoxQZd7wgy9DYH9P9WCQ=";
      };
  desktopItem = makeDesktopItem {
    name = pname;
    desktopName = "T3 Code";
    comment = "A minimal web GUI for coding agents";
    exec = pname;
    icon = "applications-development";
    categories = [ "Development" ];
    terminal = false;
  };
in
appimageTools.wrapType2 {
  inherit pname version;

  src = fetchurl {
    url = "https://github.com/pingdotgg/t3code/releases/download/v${version}/T3-Code-${version}-${release.arch}.AppImage";
    hash = release.hash;
  };

  nativeBuildInputs = [ makeWrapper ];

  # wrapType2 creates a symlink to its FHS launcher. wrapProgram moves that
  # symlink aside (without modifying its store target), then forwards all args.
  # Both the terminal command and desktop Exec=t3-code use this same wrapper.
  # Hyprland is not reliably auto-detected by Chromium's password-store logic.
  extraInstallCommands = ''
    wrapProgram $out/bin/${pname} --add-flags "--password-store=gnome-libsecret"
    install -Dm444 ${desktopItem}/share/applications/${pname}.desktop \
      $out/share/applications/${pname}.desktop
  '';

  meta = {
    description = "Desktop interface for coding agents";
    homepage = "https://github.com/pingdotgg/t3code";
    license = lib.licenses.mit;
    mainProgram = pname;
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
  };
}
