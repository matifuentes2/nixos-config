{ lib, pkgs, ... }:

let
  palette = import ./palette.nix;

  terminal = lib.getExe pkgs.kitty;
  launcher = lib.getExe pkgs.fuzzel;
  pavucontrol = lib.getExe pkgs.pavucontrol;
  nmConnectionEditor = lib.getExe' pkgs.networkmanagerapplet "nm-connection-editor";
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
      ];
      modules-right = [
        "group/tray-expander"
        "bluetooth"
        "network"
        "pulseaudio"
        "cpu"
        "battery"
      ];

      "custom/nixos" = {
        format = "";
        on-click = launcher;
        on-click-right = terminal;
        tooltip-format = "Launch apps\n\nSuper + Space";
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
        format = "";
        format-off = "󰂲";
        format-disabled = "󰂲";
        format-connected = "󰂱";
        format-no-controller = "";
        tooltip-format = "Devices connected: {num_connections}";
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
        tooltip-format-wifi = "{essid} ({frequency} GHz)";
        tooltip-format-ethernet = "Connected";
        tooltip-format-disconnected = "Disconnected";
        interval = 3;
        on-click = nmConnectionEditor;
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
        on-click = "hypr-power-menu";
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
      #custom-silencing-indicator {
        min-width: 12px;
        margin-left: 5px;
        margin-right: 0;
        font-size: 10px;
        padding-bottom: 1px;
      }

      #custom-idle-indicator.active,
      #custom-silencing-indicator.active,
      #battery.warning,
      #battery.critical {
        color: #${palette.red};
      }
    '';
  };
}
