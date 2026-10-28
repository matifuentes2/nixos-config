{ lib, pkgs, ... }:

let
  palette = import ./palette.nix;

  # Omarchy's Tokyo Night background, pinned to an immutable release.
  wallpaper = pkgs.fetchurl {
    name = "omarchy-tokyo-night-sunset-lake.png";
    url = "https://raw.githubusercontent.com/basecamp/omarchy/8fcc9d6048af4cb0e3af8512c78049857a3b53dd/themes/tokyo-night/backgrounds/1-sunset-lake.png";
    hash = "sha256-Bt+5/OAp7DWttA6jk5KWd3wrFA0SMrWhaXsVBS1XU2I=";
  };

  terminal = lib.getExe pkgs.kitty;
  lock = lib.getExe pkgs.hyprlock;
  loginctl = lib.getExe' pkgs.systemd "loginctl";
  pidof = lib.getExe' pkgs.procps "pidof";
  # Use the compositor's own hyprctl; the Lua dispatch syntax is version-bound.
  hyprctl = "/run/current-system/sw/bin/hyprctl";

  font = "JetBrainsMono Nerd Font";
in
{
  programs.kitty = {
    enable = true;
    themeFile = "tokyo_night_night";
    font = {
      name = font;
      size = 11;
    };
    settings = {
      window_padding_width = 14;
      confirm_os_window_close = 0;
      enable_audio_bell = false;
    };
  };

  # Fuzzel stands in for Omarchy's Walker launcher with the same look.
  programs.fuzzel = {
    enable = true;
    settings = {
      main = {
        terminal = terminal;
        layer = "overlay";
        font = "${font}:size=13";
        prompt = "\"  \"";
        icons-enabled = false;
        lines = 10;
        width = 50;
        horizontal-pad = 20;
        vertical-pad = 14;
        inner-pad = 10;
      };
      colors = {
        background = "${palette.background}fa";
        text = "${palette.foreground}ff";
        prompt = "${palette.accent}ff";
        input = "${palette.brightForeground}ff";
        match = "${palette.accent}ff";
        selection = "${palette.selection}ff";
        selection-text = "${palette.brightForeground}ff";
        selection-match = "${palette.accent}ff";
        border = "${palette.accent}ff";
      };
      border = {
        width = 2;
        radius = 0;
      };
    };
  };

  services.mako = {
    enable = true;
    settings = {
      anchor = "top-right";
      font = "${font} 11";
      background-color = "#${palette.background}";
      text-color = "#${palette.foreground}";
      border-color = "#${palette.accent}";
      progress-color = "over #${palette.selection}";
      border-size = 2;
      border-radius = 0;
      default-timeout = 5000;
      group-by = "app-name,summary,body";
      width = 420;
      outer-margin = 20;
      padding = "10,15";
      icons = true;
      max-icon-size = 32;

      "urgency=critical" = {
        border-color = "#${palette.red}";
        default-timeout = 0;
        layer = "overlay";
      };
      "mode=do-not-disturb" = {
        invisible = true;
      };
    };
  };

  # On-screen display for volume and brightness changes.
  services.swayosd = {
    enable = true;
    topMargin = 0.85;
    stylePath = pkgs.writeText "swayosd.css" ''
      window {
        border-radius: 0;
        opacity: 0.97;
        border: 2px solid #${palette.accent};
        background-color: #${palette.background};
      }

      label {
        font-family: "${font}";
        font-size: 11pt;
        color: #${palette.foreground};
      }

      image {
        color: #${palette.foreground};
      }

      progressbar {
        border-radius: 0;
      }

      progress {
        background-color: #${palette.accent};
      }
    '';
  };

  services.hyprpaper = {
    enable = true;
    settings = {
      ipc = "on";
      splash = false;
      preload = [ "${wallpaper}" ];
      wallpaper = [
        {
          monitor = "";
          path = "${wallpaper}";
          fit_mode = "cover";
        }
      ];
    };
  };

  programs.hyprlock = {
    enable = true;
    settings = {
      general = {
        hide_cursor = true;
        ignore_empty_input = true;
      };

      animations.enabled = false;

      background = [
        {
          monitor = "";
          color = "rgb(${palette.background})";
          path = "${wallpaper}";
          blur_passes = 3;
        }
      ];

      input-field = [
        {
          monitor = "";
          size = "650, 100";
          position = "0, 0";
          halign = "center";
          valign = "center";
          inner_color = "rgba(${palette.background}cc)";
          outer_color = "rgb(${palette.brightForeground})";
          outline_thickness = 4;
          font_family = font;
          font_color = "rgb(${palette.brightForeground})";
          check_color = "rgb(${palette.accent})";
          fail_color = "rgb(${palette.red})";
          placeholder_text = "Enter Password";
          fail_text = "<i>$FAIL ($ATTEMPTS)</i>";
          rounding = 0;
          shadow_passes = 0;
          fade_on_empty = false;
        }
      ];
    };
  };

  services.hypridle = {
    enable = true;
    settings = {
      general = {
        lock_cmd = "${pidof} hyprlock || ${lock}";
        before_sleep_cmd = "${loginctl} lock-session";
        after_sleep_cmd = "${hyprctl} dispatch 'hl.dsp.dpms({ action = \"on\" })'";
        ignore_dbus_inhibit = false;
      };

      # Lock after five minutes, then turn off the displays shortly after.
      listener = [
        {
          timeout = 300;
          on-timeout = "${loginctl} lock-session";
        }
        {
          timeout = 330;
          on-timeout = "${hyprctl} dispatch 'hl.dsp.dpms({ action = \"off\" })'";
          on-resume = "${hyprctl} dispatch 'hl.dsp.dpms({ action = \"on\" })'";
        }
      ];
    };
  };

  # Dark GTK applications, matching the rest of the desktop.
  gtk = {
    enable = true;
    theme = {
      name = "Adwaita-dark";
      package = pkgs.gnome-themes-extra;
    };
    gtk3.extraConfig.gtk-application-prefer-dark-theme = true;
    # libadwaita ignores GTK themes; request its dark style instead.
    gtk4 = {
      theme = null;
      extraConfig.gtk-application-prefer-dark-theme = true;
    };
  };

  services.cliphist.enable = true;
  services.hyprpolkitagent.enable = true;
  services.network-manager-applet.enable = true;
}
