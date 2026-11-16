{ lib, pkgs, ... }:

let
  palette = import ./palette.nix;

  terminal = lib.getExe pkgs.kitty;
  pavucontrol = lib.getExe pkgs.pavucontrol;
  nmConnectionEditor = lib.getExe' pkgs.networkmanagerapplet "nm-connection-editor";
  networkManager = lib.getExe pkgs.nmgui;
  bluetoothManager = lib.getExe pkgs.overskride;
  wpctl = lib.getExe' pkgs.wireplumber "wpctl";

  # Omarchy's centre indicators appear only while a non-default mode is on.
  idleIndicator = pkgs.writeShellApplication {
    name = "waybar-idle-indicator";
    runtimeInputs = [ pkgs.systemd ];
    text = ''
      if systemctl --user is-active --quiet hypridle.service; then
        printf '{"text": ""}\n'
      else
        printf '{"text": "󱫖", "tooltip": "Idle locking disabled", "class": "active"}\n'
      fi
    '';
  };

  silencingIndicator = pkgs.writeShellApplication {
    name = "waybar-silencing-indicator";
    runtimeInputs = [ pkgs.mako ];
    text = ''
      if makoctl mode | grep -qx do-not-disturb; then
        printf '{"text": "󰂛", "tooltip": "Notifications silenced", "class": "active"}\n'
      else
        printf '{"text": ""}\n'
      fi
    '';
  };

  screenrecordIndicator = pkgs.writeShellApplication {
    name = "waybar-screenrecord-indicator";
    runtimeInputs = [ pkgs.procps ];
    text = ''
      if pgrep -x wf-recorder >/dev/null; then
        printf '{"text": "󰑊", "tooltip": "Stop screen recording", "class": "active"}\n'
      else
        printf '{"text": ""}\n'
      fi
    '';
  };
in
{
  programs.waybar = {
    enable = true;
    systemd.enable = true;

    settings.mainBar = {
      reload_style_on_change = true;
      layer = "top";
      position = "top";
      height = 26;
      spacing = 0;

      modules-left = [
        "custom/nixos"
        "hyprland/workspaces"
      ];
      modules-center = [
        "clock"
        "custom/idle-indicator"
        "custom/silencing-indicator"
        "custom/screenrecord-indicator"
      ];
      modules-right = [
        "group/tray-expander"
        "bluetooth"
        "network"
        "pulseaudio"
        "custom/easyeffects"
        "cpu"
        "battery"
      ];

      "custom/nixos" = {
        format = "";
        on-click = "hypr-menu";
        on-click-right = terminal;
        tooltip-format = "Menu\n\nSuper + M";
      };

      "hyprland/workspaces" = {
        on-click = "activate";
        format = "{icon}";
        format-icons = {
          default = "";
          "1" = "1";
          "2" = "2";
          "3" = "3";
          "4" = "4";
          "5" = "5";
          "6" = "6";
          "7" = "7";
          "8" = "8";
          "9" = "9";
          "10" = "0";
          active = "󱓻";
        };
        persistent-workspaces = {
          "1" = [ ];
          "2" = [ ];
          "3" = [ ];
          "4" = [ ];
          "5" = [ ];
        };
      };

      clock = {
        format = "{:L%A %H:%M}";
        format-alt = "{:L%d %B W%V %Y}";
        tooltip = false;
      };

      "custom/idle-indicator" = {
        exec = lib.getExe idleIndicator;
        return-type = "json";
        interval = 30;
        signal = 9;
        on-click = "hypr-toggle-idle";
      };

      "custom/silencing-indicator" = {
        exec = lib.getExe silencingIndicator;
        return-type = "json";
        interval = 30;
        signal = 10;
      };

      "custom/screenrecord-indicator" = {
        exec = lib.getExe screenrecordIndicator;
        return-type = "json";
        interval = 30;
        signal = 8;
        on-click = "hypr-screenrecord stop";
      };

      "group/tray-expander" = {
        orientation = "inherit";
        drawer = {
          transition-duration = 600;
          children-class = "tray-group-item";
        };
        modules = [
          "custom/expand-icon"
          "tray"
        ];
      };

      "custom/expand-icon" = {
        format = "";
        tooltip = false;
      };

      tray = {
        icon-size = 12;
        spacing = 17;
      };

      bluetooth = {
        format = "󰂯";
        format-off = "󰂲";
        format-disabled = "󰂲";
        format-connected = "󰂱";
        format-no-controller = "";
        tooltip-format = "Devices connected: {num_connections}";
        on-click = bluetoothManager;
      };

      network = {
        format-icons = [
          "󰤯"
          "󰤟"
          "󰤢"
          "󰤥"
          "󰤨"
        ];
        format = "{icon}";
        format-wifi = "{icon}";
        format-ethernet = "󰀂";
        format-disconnected = "󰤮";
        tooltip-format-wifi = "{essid} · {signalStrength}%\nClick to manage Wi-Fi\nRight-click for connection profiles";
        tooltip-format-ethernet = "Ethernet connected\nClick to manage Wi-Fi\nRight-click for connection profiles";
        tooltip-format-disconnected = "Disconnected\nClick to connect to Wi-Fi\nRight-click for connection profiles";
        interval = 3;
        on-click = networkManager;
        on-click-right = nmConnectionEditor;
      };

      pulseaudio = {
        format = "{icon}";
        format-muted = "";
        format-icons = {
          headphone = "";
          headset = "";
          default = [
            ""
            ""
            ""
          ];
        };
        tooltip-format = "Playing at {volume}%";
        scroll-step = 5;
        on-click = pavucontrol;
        on-click-right = "${wpctl} set-mute @DEFAULT_AUDIO_SINK@ toggle";
      };

      "custom/easyeffects" = {
        format = "󰺢"; # Nerd Font waveform.
        tooltip-format = "Open EasyEffects";
        on-click = lib.getExe pkgs.easyeffects;
      };

      cpu = {
        interval = 5;
        format = "󰍛";
        on-click = "${terminal} --class btop -e btop";
      };

      battery = {
        format = "{capacity}% {icon}";
        format-discharging = "{icon}";
        format-charging = "{icon}";
        format-plugged = "";
        format-full = "󰂅";
        format-icons = {
          charging = [
            "󰢜"
            "󰂆"
            "󰂇"
            "󰂈"
            "󰢝"
            "󰂉"
            "󰢞"
            "󰂊"
            "󰂋"
            "󰂅"
          ];
          default = [
            "󰁺"
            "󰁻"
            "󰁼"
            "󰁽"
            "󰁾"
            "󰁿"
            "󰂀"
            "󰂁"
            "󰂂"
            "󰁹"
          ];
        };
        tooltip-format-discharging = "{power:>1.0f}W↓ {capacity}%";
        tooltip-format-charging = "{power:>1.0f}W↑ {capacity}%";
        interval = 5;
        on-click = "hypr-menu power";
        states = {
          warning = 20;
          critical = 10;
        };
      };
    };

    style = ''
      * {
        background-color: #${palette.background};
        color: #${palette.foreground};
        border: none;
        border-radius: 0;
        min-height: 0;
        font-family: "JetBrainsMono Nerd Font";
        font-size: 12px;
      }

      .modules-left {
        margin-left: 8px;
      }

      .modules-right {
        margin-right: 8px;
      }

      #workspaces button {
        all: initial;
        padding: 0 6px;
        margin: 0 1.5px;
        min-width: 9px;
      }

      #workspaces button.empty {
        opacity: 0.5;
      }

      #workspaces button.urgent {
        color: #${palette.red};
      }

      #cpu,
      #battery,
      #pulseaudio,
      #custom-easyeffects,
      #custom-nixos {
        min-width: 12px;
        margin: 0 7.5px;
      }

      #custom-nixos {
        color: #${palette.accent};
        font-size: 14px;
      }

      #tray {
        margin-right: 16px;
      }

      #bluetooth {
        margin-right: 17px;
      }

      #network {
        margin-right: 13px;
      }

      #custom-expand-icon {
        margin-right: 18px;
      }

      tooltip {
        padding: 2px;
      }

      #clock {
        margin-left: 8.75px;
      }

      #custom-idle-indicator,
      #custom-silencing-indicator,
      #custom-screenrecord-indicator {
        min-width: 12px;
        margin-left: 5px;
        margin-right: 0;
        font-size: 10px;
        padding-bottom: 1px;
      }

      #custom-idle-indicator.active,
      #custom-silencing-indicator.active,
      #custom-screenrecord-indicator.active,
      #battery.warning,
      #battery.critical {
        color: #${palette.red};
      }
    '';
  };
}
