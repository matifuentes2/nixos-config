{ lib, pkgs, ... }:

let
  palette = import ../../hyprland/palette.nix;
in
{
  imports = [
    ../../hyprland
    ./cua-driver.nix
  ];

  home.file.".XCompose".source = ./XCompose;

  # Omarchy's default applications: imv for images, mpv for audio and video,
  # Papers for documents, Thunar for folders, and Firefox for the web.
  xdg.mimeApps = {
    enable = true;
    defaultApplications =
      let
        associate = app: types: lib.genAttrs types (_: app);
      in
      associate "imv.desktop" [
        "image/avif"
        "image/bmp"
        "image/gif"
        "image/heic"
        "image/jpeg"
        "image/png"
        "image/svg+xml"
        "image/tiff"
        "image/webp"
      ]
      // associate "mpv.desktop" [
        "audio/aac"
        "audio/flac"
        "audio/mpeg"
        "audio/ogg"
        "audio/opus"
        "audio/wav"
        "video/mp4"
        "video/mpeg"
        "video/ogg"
        "video/quicktime"
        "video/webm"
        "video/x-matroska"
        "video/x-msvideo"
      ]
      // associate "org.gnome.Papers.desktop" [ "application/pdf" ]
      // associate "thunar.desktop" [ "inode/directory" ]
      // associate "firefox.desktop" [
        "text/html"
        "x-scheme-handler/http"
        "x-scheme-handler/https"
      ];
  };
  # Applications sometimes write their own mimeapps.list; Home Manager owns it.
  xdg.configFile."mimeapps.list".force = true;

  home.packages = [
    pkgs.imv
    pkgs.mpv
    pkgs.papers
    pkgs.satty
    pkgs.nmgui
    pkgs.overskride
    pkgs.wlinhibit
  ];

  # Keep the Wayland session awake and suppress logind's lid handling until Ctrl+C.
  home.shellAliases.keep-awake = "${lib.getExe' pkgs.systemd "systemd-inhibit"} --what=sleep:handle-lid-switch --mode=block --who=keep-awake --why='Keep awake until interrupted' ${lib.getExe' pkgs.wlinhibit "wlinhibit"} ${lib.getExe' pkgs.coreutils "sleep"} infinity";

  # Start the PipeWire effects processor with the graphical session.
  services.easyeffects.enable = true;

  services.elephant.enable = true;
  services.walker = {
    enable = true;
    enableElephantIntegration = true;
    systemd.enable = true;
    settings = {
      placeholders.windows = {
        input = "Search open windows…";
        list = "No matching windows";
      };
      keybinds = {
        next = [
          "Down"
          "ctrl j"
          "ctrl n"
        ];
        previous = [
          "Up"
          "ctrl k"
          "ctrl p"
        ];
      };
    };
    # Inherit Walker's native layouts for icons and application subtitles.
    theme = {
      name = "tokyo-night";
      style = ''
        @define-color window_bg_color #${palette.background};
        @define-color accent_bg_color #${palette.accent};
        @define-color theme_fg_color #${palette.brightForeground};
        @define-color error_bg_color #${palette.red};
        @define-color error_fg_color #${palette.darkBackground};

        * {
          all: unset;
          font-family: "JetBrainsMono Nerd Font";
          font-size: 14px;
        }
        scrollbar { opacity: 0; }
        .normal-icons { -gtk-icon-size: 20px; }
        .large-icons { -gtk-icon-size: 32px; }
        .box-wrapper {
          background: @window_bg_color;
          border: 1px solid #${palette.muted};
          border-radius: 16px;
          padding: 18px;
          box-shadow: 0 12px 32px rgba(0, 0, 0, 0.35);
        }
        .input {
          background: #${palette.lighterBackground};
          color: @theme_fg_color;
          caret-color: @accent_bg_color;
          border-radius: 10px;
          padding: 14px;
          margin-bottom: 12px;
        }
        .input placeholder { color: #${palette.comment}; }
        .input selection { background: #${palette.selection}; }
        .list, .placeholder, .preview-box, .elephant-hint {
          color: @theme_fg_color;
        }
        .item-box {
          padding: 12px;
          border-radius: 10px;
        }
        child:selected .item-box, row:selected .item-box {
          background: #${palette.selection};
        }
        .item-subtext {
          color: #${palette.foreground};
          font-size: 12px;
        }
        .item-quick-activation {
          color: @accent_bg_color;
          padding: 4px 8px;
        }
        .keybinds {
          color: #${palette.foreground};
          border-top: 1px solid #${palette.muted};
          margin-top: 12px;
          padding-top: 10px;
        }
        .keybind-label {
          color: @accent_bg_color;
          padding: 2px 6px;
          border-radius: 4px;
          background: #${palette.lighterBackground};
        }
        .keybind-bind, .keybind-button { opacity: 0.65; }
        .error {
          background: @error_bg_color;
          color: @error_fg_color;
          padding: 10px;
          border-radius: 8px;
        }
      '';
    };
  };
}
