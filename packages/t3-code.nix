{
  lib,
  appimageTools,
  fetchurl,
  makeDesktopItem,
  makeWrapper,
}:

let
  pname = "t3-code";
  version = "0.1.5";
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
    url = "https://github.com/pingdotgg/t3code/releases/download/v${version}/T3-Code-${version}-x86_64.AppImage";
    sha256 = "933ff9dc4c650a75aa4087c98f2ae6c6540c233f0e2feb32ebff950b09be849d";
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
    platforms = [ "x86_64-linux" ];
  };
}
