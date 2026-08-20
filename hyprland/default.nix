{ lib, pkgs, ... }:

let
  wallpaper = pkgs.nixos-artwork.wallpapers.simple-dark-gray.gnomeFilePath;

  terminal = lib.getExe pkgs.kitty;
  launcher = lib.getExe pkgs.fuzzel;
  fileManager = lib.getExe pkgs.thunar;
  lock = lib.getExe pkgs.hyprlock;
  grimblast = lib.getExe pkgs.grimblast;
  pavucontrol = lib.getExe pkgs.pavucontrol;
  nmConnectionEditor = lib.getExe' pkgs.networkmanagerapplet "nm-connection-editor";
  wpctl = lib.getExe' pkgs.wireplumber "wpctl";
  brightnessctl = lib.getExe pkgs.brightnessctl;
  playerctl = lib.getExe pkgs.playerctl;
  loginctl = lib.getExe' pkgs.systemd "loginctl";
  hyprctl = lib.getExe' pkgs.hyprland "hyprctl";
  pgrep = lib.getExe' pkgs.procps "pgrep";
  jq = lib.getExe pkgs.jq;

  windowSwitcher = pkgs.writeShellApplication {
    name = "hypr-window-switcher";
    text = ''
      address="$(
        ${hyprctl} clients -j \
          | ${jq} -r '.[] | [.address, .workspace.name, .class, .title] | @tsv' \
          | ${launcher} --dmenu --match-mode=fuzzy --prompt='Window> ' \
              --with-nth='{2}  {3}: {4}' --accept-nth=1 --only-match
      )" || exit 0

      [ -n "$address" ] || exit 0
      exec ${hyprctl} dispatch focuswindow "address:$address"
    '';
  };
in
{
  home.packages = [
    pkgs.brightnessctl
    pkgs.grimblast
    pkgs.pavucontrol
    pkgs.playerctl
    pkgs.wl-clipboard
  ];

  wayland.windowManager.hyprland = {
    enable = true;
    # Hyprland and its portal are installed by the NixOS module.
    package = null;
    portalPackage = null;
    configType = "hyprlang";

    settings = {
      "$mod" = "SUPER";
      "$terminal" = terminal;
      "$menu" = launcher;
      "$fileManager" = fileManager;

      monitor = [ ", preferred, auto, 1" ];

      input = {
        kb_layout = "us";
        follow_mouse = 1;
        repeat_delay = 300;
        repeat_rate = 35;

        touchpad = {
          natural_scroll = true;
          tap-to-click = true;
        };
      };

      general = {
        gaps_in = 5;
        gaps_out = 10;
        border_size = 2;
        "col.active_border" = "rgba(89b4faff) rgba(cba6f7ff) 45deg";
        "col.inactive_border" = "rgba(45475aaa)";
        layout = "dwindle";
        resize_on_border = true;
      };

      decoration = {
        rounding = 10;
        active_opacity = 1.0;
        inactive_opacity = 0.96;

        # Avoid costly effects on the Raspberry Pi 4's V3D GPU.
        blur.enabled = false;
        shadow.enabled = false;
      };

      animations = {
        enabled = true;
        bezier = [
          "easeOutQuint, 0.23, 1, 0.32, 1"
          "easeInOutCubic, 0.65, 0.05, 0.36, 1"
        ];
        animation = [
          "windows, 1, 4, easeOutQuint"
          "windowsOut, 1, 4, easeInOutCubic, popin 80%"
          "border, 1, 6, default"
          "fade, 1, 4, default"
          "workspaces, 1, 5, easeOutQuint"
        ];
      };

      dwindle.preserve_split = true;

      misc = {
        disable_hyprland_logo = true;
        force_default_wallpaper = 0;
      };

      bind = [
        "$mod, RETURN, exec, $terminal"
        "$mod, R, exec, $menu"
        "$mod, W, exec, ${lib.getExe windowSwitcher}"
        "$mod, E, exec, $fileManager"
        "$mod SHIFT, V, exec, ${pavucontrol}"
        "$mod, N, exec, ${nmConnectionEditor}"
        "$mod CTRL, L, exec, ${lock}"

        "$mod, Q, killactive"
        "$mod SHIFT, E, exit"
        "$mod, V, togglefloating"
        "$mod, F, fullscreen"
        "$mod, P, pseudo"
        "$mod, T, layoutmsg, togglesplit"

        "$mod, H, movefocus, l"
        "$mod, J, movefocus, d"
        "$mod, K, movefocus, u"
        "$mod, L, movefocus, r"
        "$mod, left, movefocus, l"
        "$mod, down, movefocus, d"
        "$mod, up, movefocus, u"
        "$mod, right, movefocus, r"

        "$mod SHIFT, H, movewindow, l"
        "$mod SHIFT, J, movewindow, d"
        "$mod SHIFT, K, movewindow, u"
        "$mod SHIFT, L, movewindow, r"

        "$mod, 1, workspace, 1"
        "$mod, 2, workspace, 2"
        "$mod, 3, workspace, 3"
        "$mod, 4, workspace, 4"
        "$mod, 5, workspace, 5"
        "$mod, 6, workspace, 6"
        "$mod, 7, workspace, 7"
        "$mod, 8, workspace, 8"
        "$mod, 9, workspace, 9"
        "$mod, 0, workspace, 10"

        "$mod SHIFT, 1, movetoworkspace, 1"
        "$mod SHIFT, 2, movetoworkspace, 2"
        "$mod SHIFT, 3, movetoworkspace, 3"
        "$mod SHIFT, 4, movetoworkspace, 4"
        "$mod SHIFT, 5, movetoworkspace, 5"
        "$mod SHIFT, 6, movetoworkspace, 6"
        "$mod SHIFT, 7, movetoworkspace, 7"
        "$mod SHIFT, 8, movetoworkspace, 8"
        "$mod SHIFT, 9, movetoworkspace, 9"
        "$mod SHIFT, 0, movetoworkspace, 10"

        ", Print, exec, ${grimblast} copy area"
        "SHIFT, Print, exec, ${grimblast} save area"
      ];

      bindel = [
        ", XF86AudioRaiseVolume, exec, ${wpctl} set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+"
        ", XF86AudioLowerVolume, exec, ${wpctl} set-volume @DEFAULT_AUDIO_SINK@ 5%-"
        ", XF86AudioMute, exec, ${wpctl} set-mute @DEFAULT_AUDIO_SINK@ toggle"
        ", XF86AudioMicMute, exec, ${wpctl} set-mute @DEFAULT_AUDIO_SOURCE@ toggle"
        ", XF86MonBrightnessUp, exec, ${brightnessctl} set 5%+"
        ", XF86MonBrightnessDown, exec, ${brightnessctl} set 5%-"
      ];

      bindl = [
        ", XF86AudioPlay, exec, ${playerctl} play-pause"
        ", XF86AudioNext, exec, ${playerctl} next"
        ", XF86AudioPrev, exec, ${playerctl} previous"
      ];

      bindm = [
        "$mod, mouse:272, movewindow"
        "$mod, mouse:273, resizewindow"
      ];
    };
  };

  programs.kitty = {
    enable = true;
    font = {
      name = "JetBrainsMono Nerd Font";
      size = 11;
    };
    settings = {
      background = "#1e1e2e";
      foreground = "#cdd6f4";
      selection_background = "#585b70";
      selection_foreground = "#cdd6f4";
      cursor = "#f5e0dc";
      background_opacity = "1.0";
      window_padding_width = 8;
      confirm_os_window_close = 0;
      enable_audio_bell = false;
    };
  };

  programs.fuzzel = {
    enable = true;
    settings = {
      main = {
        terminal = terminal;
        layer = "overlay";
        font = "JetBrainsMono Nerd Font:size=11";
        lines = 10;
        width = 40;
        horizontal-pad = 20;
        vertical-pad = 12;
        inner-pad = 8;
      };
      colors = {
        background = "1e1e2eff";
        text = "cdd6f4ff";
        match = "89b4faff";
        selection = "313244ff";
        selection-text = "cdd6f4ff";
        selection-match = "f5c2e7ff";
        border = "89b4faff";
      };
      border = {
        width = 2;
        radius = 10;
      };
    };
  };

  programs.waybar = {
    enable = true;
    systemd.enable = true;

    settings.mainBar = {
      layer = "top";
      position = "top";
      height = 34;
      spacing = 4;

      modules-left = [
        "hyprland/workspaces"
        "hyprland/window"
      ];
      modules-center = [ "clock" ];
      modules-right = [
        "pulseaudio"
        "network"
        "cpu"
        "memory"
        "tray"
      ];

      "hyprland/workspaces" = {
        on-click = "activate";
        sort-by-number = true;
        persistent-workspaces."*" = 5;
      };

      "hyprland/window" = {
        max-length = 60;
        separate-outputs = true;
      };

      clock = {
        format = "{:%a %d %b  %H:%M}";
        tooltip-format = "<big>{:%Y %B}</big>\n<tt><small>{calendar}</small></tt>";
      };

      pulseaudio = {
        format = "VOL {volume}%";
        format-muted = "MUTED";
        scroll-step = 5;
        on-click = pavucontrol;
      };

      network = {
        format-wifi = "{essid} {signalStrength}%";
        format-ethernet = "Ethernet";
        format-disconnected = "Offline";
        tooltip-format = "{ifname}: {ipaddr}/{cidr}";
        on-click = nmConnectionEditor;
      };

      cpu = {
        format = "CPU {usage}%";
        interval = 5;
      };

      memory = {
        format = "RAM {percentage}%";
        interval = 5;
      };

      tray.spacing = 8;
    };

    style = ''
      * {
        border: none;
        border-radius: 0;
        font-family: "JetBrainsMono Nerd Font", sans-serif;
        font-size: 13px;
        min-height: 0;
      }

      window#waybar {
        background: rgba(30, 30, 46, 0.96);
        color: #cdd6f4;
        border-bottom: 2px solid #313244;
      }

      #workspaces button {
        padding: 0 9px;
        color: #a6adc8;
        background: transparent;
        border-radius: 8px;
        margin: 4px 2px;
      }

      #workspaces button.active {
        color: #1e1e2e;
        background: #89b4fa;
      }

      #workspaces button.urgent {
        color: #1e1e2e;
        background: #f38ba8;
      }

      #window,
      #clock,
      #pulseaudio,
      #network,
      #cpu,
      #memory,
      #tray {
        padding: 0 10px;
        margin: 4px 2px;
        border-radius: 8px;
        background: #313244;
      }

      #window {
        background: transparent;
      }

      #pulseaudio.muted,
      #network.disconnected {
        color: #f38ba8;
      }
    '';
  };

  services.mako = {
    enable = true;
    settings = {
      anchor = "top-right";
      font = "JetBrainsMono Nerd Font 11";
      background-color = "#1e1e2e";
      text-color = "#cdd6f4";
      border-color = "#89b4fa";
      border-size = 2;
      border-radius = 10;
      default-timeout = 5000;
      width = 360;
      height = 120;
      margin = "12";
      padding = "12";
      icons = true;
      max-icon-size = 48;
    };
  };

  services.hyprpaper = {
    enable = true;
    settings = {
      ipc = "on";
      splash = false;
      preload = [ wallpaper ];
      wallpaper = [
        {
          monitor = "";
          path = wallpaper;
          fit_mode = "cover";
        }
      ];
    };
  };

  programs.hyprlock = {
    enable = true;
    settings = {
      general.hide_cursor = true;

      background = [
        {
          monitor = "";
          path = wallpaper;
        }
      ];

      label = [
        {
          monitor = "";
          text = "$TIME";
          color = "rgb(cdd6f4)";
          font_size = 64;
          font_family = "JetBrainsMono Nerd Font";
          position = "0, 120";
          halign = "center";
          valign = "center";
        }
      ];

      input-field = [
        {
          monitor = "";
          size = "260, 50";
          position = "0, -60";
          dots_center = true;
          fade_on_empty = false;
          font_color = "rgb(cdd6f4)";
          inner_color = "rgb(313244)";
          outer_color = "rgb(89b4fa)";
          outline_thickness = 3;
          placeholder_text = ''<span foreground="##a6adc8">Password</span>'';
          shadow_passes = 2;
        }
      ];
    };
  };

  services.hypridle = {
    enable = true;
    settings = {
      general = {
        lock_cmd = "${pgrep} -x hyprlock || ${lock}";
        before_sleep_cmd = "${loginctl} lock-session";
        after_sleep_cmd = "${hyprctl} dispatch dpms on";
        ignore_dbus_inhibit = false;
      };

      listener = [
        {
          timeout = 600;
          on-timeout = "${loginctl} lock-session";
        }
        {
          timeout = 660;
          on-timeout = "${hyprctl} dispatch dpms off";
          on-resume = "${hyprctl} dispatch dpms on";
        }
      ];
    };
  };

  services.hyprpolkitagent.enable = true;
  services.network-manager-applet.enable = true;
}
