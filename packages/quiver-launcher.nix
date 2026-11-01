{
  lib,
  appimageTools,
  fetchurl,
  makeDesktopItem,
}:

let
  pname = "quiver-launcher";
  version = "3.5.1";
  desktopItem = makeDesktopItem {
    name = pname;
    desktopName = "Quiver Launcher";
    comment = "Download, manage, and play games from GitHub and GitLab";
    exec = pname;
    icon = "applications-games";
    categories = [ "Game" ];
    terminal = false;
  };
in
appimageTools.wrapType2 {
  inherit pname version;

  src = fetchurl {
    url = "https://github.com/tgeorgiadis/quiver-launcher/releases/download/v${version}/QuiverLauncher-linux-x64.AppImage";
    sha256 = "a8cd5398b6dae924bcec09ece1781c03cbfd73298675476f26fc1c072d3c629b";
  };

  extraInstallCommands = ''
    install -Dm444 ${desktopItem}/share/applications/${pname}.desktop \
      $out/share/applications/${pname}.desktop
  '';

  meta = {
    description = "Launcher for games and apps released on GitHub and GitLab";
    homepage = "https://github.com/tgeorgiadis/quiver-launcher";
    license = lib.licenses.mit;
    mainProgram = pname;
    platforms = [ "x86_64-linux" ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}
