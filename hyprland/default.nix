{ lib, pkgs, ... }:

let
  palette = import ./palette.nix;

  terminal = lib.getExe pkgs.kitty;
  launcher = lib.getExe pkgs.fuzzel;
  fileManager = lib.getExe pkgs.thunar;
  lock = lib.getExe pkgs.hyprlock;
  grimblast = lib.getExe pkgs.grimblast;
  hyprpicker = lib.getExe pkgs.hyprpicker;
  pavucontrol = lib.getExe pkgs.pavucontrol;
  nmConnectionEditor = lib.getExe' pkgs.networkmanagerapplet "nm-connection-editor";
  swayosdClient = lib.getExe' pkgs.swayosd "swayosd-client";
  playerctl = lib.getExe pkgs.playerctl;
  makoctl = lib.getExe' pkgs.mako "makoctl";
  loginctl = lib.getExe' pkgs.systemd "loginctl";
  pkill = lib.getExe' pkgs.procps "pkill";

  # Hyprland's own CLI must match the running compositor, so these scripts
  # use the hyprctl on PATH rather than pinning the nixpkgs build.
  windowSwitcher = pkgs.writeShellApplication {
    name = "hypr-window-switcher";
    runtimeInputs = [
      pkgs.fuzzel
      pkgs.jq
    ];
    text = ''
      address="$(
        hyprctl clients -j \
          | jq -r '.[] | [.address, .workspace.name, .class, .title] | @tsv' \
          | fuzzel --dmenu --match-mode=fuzzy --prompt='Window> ' \
              --with-nth='{2}  {3}: {4}' --accept-nth=1 --only-match
      )" || exit 0

      [ -n "$address" ] || exit 0
      exec hyprctl dispatch "hl.dsp.focus({ window = \"address:$address\" })"
    '';
  };

  powerMenu = pkgs.writeShellApplication {
    name = "hypr-power-menu";
    runtimeInputs = [
      pkgs.fuzzel
      pkgs.systemd
    ];
    text = ''
      choice="$(
        printf '%s\n' \
          '  Lock' \
          '󰤄  Suspend' \
          '󰍃  Log out' \
          '󰜉  Restart' \
          '󰐥  Shut down' \
          | fuzzel --dmenu --prompt='System> ' --lines=5 --width=24 --only-match
      )" || exit 0

      case "$choice" in
        *Lock) loginctl lock-session ;;
        *Suspend) systemctl suspend ;;
        *"Log out") hyprctl dispatch 'hl.dsp.exit()' ;;
        *Restart) systemctl reboot ;;
        *"Shut down") systemctl poweroff ;;
      esac
    '';
  };

  # List the described bindings, decoding Hyprland's modifier bitmask and the
  # layout-independent keycodes used for the number row.
  keybindings = pkgs.writeShellApplication {
    name = "hypr-keybindings";
    runtimeInputs = [
      pkgs.fuzzel
      pkgs.jq
      pkgs.util-linux
    ];
    text = ''
      hyprctl -j binds | jq -r '
        def keyname:
          if test("^code:[0-9]+$") then
            (ltrimstr("code:") | tonumber) as $code
            | if $code >= 10 and $code <= 19 then ($code - 9) % 10 | tostring
              elif $code == 20 then "MINUS"
              elif $code == 21 then "EQUAL"
              else . end
          else . end;
        .[]
        | select(.has_description)
        | . as $bind
        | [[64, "SUPER"], [4, "CTRL"], [8, "ALT"], [1, "SHIFT"]]
        | map(select((($bind.modmask / .[0]) | floor) % 2 == 1) | .[1])
        | . + [$bind.key | keyname]
        | "\(join(" + "))\t\($bind.description)"
      ' \
        | column -t -s "$(printf '\t')" \
        | fuzzel --dmenu --prompt='Keys> ' --width=80 --lines=20 >/dev/null || true
    '';
  };

  clipboardHistory = pkgs.writeShellApplication {
    name = "hypr-clipboard";
    runtimeInputs = [
      pkgs.cliphist
      pkgs.fuzzel
      pkgs.wl-clipboard
    ];
    text = ''
      selection="$(cliphist list | fuzzel --dmenu --prompt='Clipboard> ' --width=80)" || exit 0
      [ -n "$selection" ] || exit 0
      printf '%s' "$selection" | cliphist decode | wl-copy
    '';
  };

  toggleIdle = pkgs.writeShellApplication {
    name = "hypr-toggle-idle";
    runtimeInputs = [
      pkgs.libnotify
      pkgs.procps
      pkgs.systemd
    ];
    text = ''
      if systemctl --user is-active --quiet hypridle.service; then
        systemctl --user stop hypridle.service
        notify-send -u low 'Stop locking computer when idle'
      else
        systemctl --user start hypridle.service
        notify-send -u low 'Now locking computer when idle'
      fi
      # Refresh the bar's idle indicator.
      pkill -RTMIN+9 waybar || true
    '';
  };
in
{
  imports = [
    ./desktop.nix
    ./waybar.nix
  ];

  home.packages = [
    pkgs.brightnessctl
    pkgs.btop
    pkgs.grimblast
    pkgs.hyprpicker
    pkgs.libnotify
    pkgs.pavucontrol
    pkgs.playerctl
    pkgs.wl-clipboard
    clipboardHistory
    keybindings
    powerMenu
    toggleIdle
    windowSwitcher
  ];

  # Hyprland 0.57 removed hyprlang configuration support. The Lua files follow
  # Omarchy's split of its Hyprland defaults.
  wayland.windowManager.hyprland = {
    enable = true;
    # Hyprland and its portal are installed by the NixOS module.
    package = null;
    portalPackage = null;
    configType = "lua";

    extraLuaFiles = {
      # Shared helpers imported by the other files.
      "desktop/lib" = {
        autoLoad = false;
        content = ''
          local M = {}

          -- Bind a key with a description so hypr-keybindings can list it.
          -- String actions run as shell commands.
          function M.bind(keys, description, action, opts)
            opts = opts or {}
            opts.description = description
            if type(action) == "string" then
              action = hl.dsp.exec_cmd(action)
            end
            return hl.bind(keys, action, opts)
          end

          -- Apply window rule effects to a class pattern or a match table.
          function M.window(match, effects)
            effects.match = type(match) == "string" and { class = match } or match
            return hl.window_rule(effects)
          end

          return M
        '';
      };

      "desktop/looknfeel" = ''
        local active_border = "rgb(${palette.accent})"
        local inactive_border = "rgba(${palette.muted}aa)"

        hl.config({
          general = {
            gaps_in = 5,
            gaps_out = 10,
            border_size = 2,

            col = {
              active_border = active_border,
              inactive_border = inactive_border,
            },

            resize_on_border = true,
            extend_border_grab_area = 8,
            hover_icon_on_border = true,
            allow_tearing = false,
            layout = "dwindle",
          },

          -- Omarchy's flat look also avoids costly effects on the Raspberry
          -- Pi 4's V3D GPU.
          decoration = {
            rounding = 0,
            shadow = { enabled = false },
            blur = { enabled = false },
          },

          group = {
            col = {
              border_active = active_border,
              border_inactive = inactive_border,
            },

            groupbar = {
              font_size = 12,
              font_family = "JetBrainsMono Nerd Font",
              font_weight_active = "ultraheavy",
              font_weight_inactive = "normal",
              indicator_height = 1,
              indicator_gap = 5,
              height = 22,
              gaps_in = 5,
              gaps_out = 0,
              text_color = "rgb(${palette.brightForeground})",
              text_color_inactive = "rgba(${palette.foreground}90)",
              col = {
                active = "rgba(00000040)",
                inactive = "rgba(00000020)",
              },
              gradients = true,
              gradient_rounding = 0,
              gradient_round_only_edges = false,
            },
          },

          animations = { enabled = true },

          dwindle = {
            preserve_split = true,
            force_split = 2,
          },

          master = { new_status = "master" },

          misc = {
            disable_hyprland_logo = true,
            disable_splash_rendering = true,
            force_default_wallpaper = 0,
            focus_on_activate = true,
            key_press_enables_dpms = true,
            mouse_move_enables_dpms = true,
          },

          cursor = { hide_on_key_press = true },

          binds = { hide_special_on_workspace_change = true },
        })

        -- Omarchy's motion: one strong ease-out, short entrances, shorter exits.
        hl.curve("easeOutQuint", { type = "bezier", points = { { 0.23, 1 }, { 0.32, 1 } } })

        hl.animation({ leaf = "global", enabled = true, speed = 2.5, bezier = "easeOutQuint" })
        hl.animation({ leaf = "border", enabled = true, speed = 1.5, bezier = "easeOutQuint" })
        hl.animation({ leaf = "windows", enabled = true, speed = 2.5, bezier = "easeOutQuint" })
        hl.animation({ leaf = "windowsIn", enabled = true, speed = 2.5, bezier = "easeOutQuint", style = "popin 95%" })
        hl.animation({ leaf = "windowsOut", enabled = true, speed = 1.6, bezier = "easeOutQuint", style = "popin 95%" })
        hl.animation({ leaf = "fadeIn", enabled = true, speed = 1.8, bezier = "easeOutQuint" })
        hl.animation({ leaf = "fadeOut", enabled = true, speed = 1.2, bezier = "easeOutQuint" })
        hl.animation({ leaf = "fade", enabled = true, speed = 2, bezier = "easeOutQuint" })
        hl.animation({ leaf = "fadeSwitch", enabled = false })
        hl.animation({ leaf = "layers", enabled = true, speed = 2.5, bezier = "easeOutQuint" })
        hl.animation({ leaf = "layersIn", enabled = true, speed = 2.5, bezier = "easeOutQuint", style = "fade" })
        hl.animation({ leaf = "layersOut", enabled = true, speed = 1.6, bezier = "easeOutQuint", style = "fade" })
        hl.animation({ leaf = "workspaces", enabled = false })
      '';

      "desktop/input" = ''
        -- Hosts may add specific monitor rules after this fallback.
        hl.monitor({ output = "", mode = "preferred", position = "auto", scale = 1 })

        hl.config({
          input = {
            kb_layout = "us",
            follow_mouse = 1,
            sensitivity = 0,
            repeat_rate = 40,
            repeat_delay = 250,
            numlock_by_default = true,

            touchpad = {
              natural_scroll = true,
              clickfinger_behavior = true,
              scroll_factor = 0.4,
            },
          },
        })

        hl.gesture({ fingers = 3, direction = "horizontal", action = "workspace" })
      '';

      "desktop/rules" = ''
        local d = require("desktop.lib")

        -- Ignore maximize requests; the tiling layout decides window sizes.
        d.window(".*", { suppress_event = "maximize" })

        -- Fix some dragging issues with XWayland.
        d.window({
          class = "^$",
          title = "^$",
          xwayland = true,
          float = true,
          fullscreen = false,
          pin = false,
        }, { no_focus = true })

        -- Small utility windows float centered at a consistent size.
        d.window(
          "(org.pulseaudio.pavucontrol|nm-connection-editor|.blueman-manager-wrapped|xdg-desktop-portal-gtk|imv|mpv|btop)",
          { tag = "+floating-window" }
        )
        d.window({
          class = "(thunar|Thunar)",
          title = "^(File Operation Progress|Rename .*|Confirm to replace files)$",
        }, { tag = "+floating-window" })
        d.window({ tag = "floating-window" }, { float = true, center = true, size = { 875, 600 } })

        -- Terminals get Omarchy's light transparency.
        d.window("kitty", { opacity = "0.97 0.9" })
      '';

      "desktop/bindings" = ''
        local d = require("desktop.lib")

        -- Applications.
        d.bind("SUPER + RETURN", "Terminal", "${terminal}")
        d.bind("SUPER + SPACE", "Launch apps", "${launcher}")
        d.bind("SUPER + ALT + SPACE", "Switch to a window", "${lib.getExe windowSwitcher}")
        d.bind("SUPER + SHIFT + B", "Browser", "firefox")
        d.bind("SUPER + SHIFT + F", "File manager", "${fileManager}")
        d.bind("SUPER + SHIFT + T", "Activity", "${terminal} --class btop -e btop")

        -- System menus and utilities.
        d.bind("SUPER + ESCAPE", "System menu", "${lib.getExe powerMenu}")
        d.bind("SUPER + K", "Show key bindings", "${lib.getExe keybindings}")
        d.bind("SUPER + CTRL + V", "Clipboard history", "${lib.getExe clipboardHistory}")
        d.bind("SUPER + CTRL + A", "Audio controls", "${pavucontrol}")
        d.bind("SUPER + CTRL + N", "Network connections", "${nmConnectionEditor}")
        d.bind("SUPER + CTRL + I", "Toggle locking on idle", "${lib.getExe toggleIdle}")
        d.bind("SUPER + CTRL + L", "Lock system", "${loginctl} lock-session")
        d.bind("SUPER + SHIFT + SPACE", "Toggle top bar", "${pkill} -SIGUSR1 waybar")

        -- Notifications.
        d.bind("SUPER + comma", "Dismiss last notification", "${makoctl} dismiss")
        d.bind("SUPER + SHIFT + comma", "Dismiss all notifications", "${makoctl} dismiss --all")
        d.bind("SUPER + ALT + comma", "Restore last notification", "${makoctl} restore")
        d.bind("SUPER + CTRL + comma", "Toggle do not disturb", "${makoctl} mode -t do-not-disturb && ${pkill} -RTMIN+10 waybar")

        -- Screenshots and color picking.
        d.bind("PRINT", "Screenshot area to clipboard", "${grimblast} --notify copy area")
        d.bind("SHIFT + PRINT", "Screenshot area to file", "${grimblast} --notify copysave area")
        d.bind("CTRL + PRINT", "Screenshot display to file", "${grimblast} --notify copysave output")
        d.bind("SUPER + PRINT", "Color picker", "${pkill} hyprpicker || ${hyprpicker} -a")

        -- Windows.
        d.bind("SUPER + W", "Close window", hl.dsp.window.close())
        d.bind("SUPER + Q", "Close window", hl.dsp.window.close())
        d.bind("SUPER + J", "Toggle window split", hl.dsp.layout("togglesplit"))
        d.bind("SUPER + P", "Pseudo window", hl.dsp.window.pseudo())
        d.bind("SUPER + T", "Toggle window floating/tiling", hl.dsp.window.float({ action = "toggle" }))
        d.bind("SUPER + F", "Full screen", hl.dsp.window.fullscreen({ mode = "fullscreen" }))
        d.bind("SUPER + ALT + F", "Full width", hl.dsp.window.fullscreen({ mode = "maximized" }))

        for _, dir in ipairs({ { "LEFT", "l", "left" }, { "RIGHT", "r", "right" }, { "UP", "u", "up" }, { "DOWN", "d", "down" } }) do
          local key, short, name = dir[1], dir[2], dir[3]
          d.bind("SUPER + " .. key, "Focus window " .. name, hl.dsp.focus({ direction = short }))
          d.bind("SUPER + SHIFT + " .. key, "Swap window " .. name, hl.dsp.window.swap({ direction = short }))
          d.bind("SUPER + ALT + " .. key, "Move window into group " .. name, hl.dsp.window.move({ into_group = short }))
        end

        d.bind("ALT + TAB", "Focus next window", hl.dsp.window.cycle_next())
        d.bind("ALT + SHIFT + TAB", "Focus previous window", hl.dsp.window.cycle_next({ next = false }))
        hl.bind("ALT + TAB", hl.dsp.window.bring_to_top())
        hl.bind("ALT + SHIFT + TAB", hl.dsp.window.bring_to_top())

        -- Resize with the minus and equals keys, which keep their keycodes
        -- across keyboard layouts.
        d.bind("SUPER + code:20", "Expand window left", hl.dsp.window.resize({ x = -100, y = 0, relative = true }), { repeating = true })
        d.bind("SUPER + code:21", "Shrink window left", hl.dsp.window.resize({ x = 100, y = 0, relative = true }), { repeating = true })
        d.bind("SUPER + SHIFT + code:20", "Shrink window up", hl.dsp.window.resize({ x = 0, y = -100, relative = true }), { repeating = true })
        d.bind("SUPER + SHIFT + code:21", "Expand window down", hl.dsp.window.resize({ x = 0, y = 100, relative = true }), { repeating = true })

        d.bind("SUPER + mouse:272", "Move window", hl.dsp.window.drag(), { mouse = true })
        d.bind("SUPER + mouse:273", "Resize window", hl.dsp.window.resize(), { mouse = true })

        -- Groups.
        d.bind("SUPER + G", "Toggle window grouping", hl.dsp.group.toggle())
        d.bind("SUPER + ALT + G", "Move window out of group", hl.dsp.window.move({ out_of_group = true }))
        d.bind("SUPER + ALT + TAB", "Next window in group", hl.dsp.group.next())
        d.bind("SUPER + ALT + SHIFT + TAB", "Previous window in group", hl.dsp.group.prev())

        -- Workspaces. Number-row keycodes 10-19 work on any keyboard layout.
        for workspace = 1, 10 do
          local key = "code:" .. tostring(workspace + 9)
          d.bind("SUPER + " .. key, "Switch to workspace " .. workspace, hl.dsp.focus({ workspace = workspace }))
          d.bind("SUPER + SHIFT + " .. key, "Move window to workspace " .. workspace, hl.dsp.window.move({ workspace = workspace }))
          d.bind(
            "SUPER + SHIFT + ALT + " .. key,
            "Move window silently to workspace " .. workspace,
            hl.dsp.window.move({ workspace = workspace, follow = false })
          )
        end

        d.bind("SUPER + TAB", "Next workspace", hl.dsp.focus({ workspace = "m+1" }))
        d.bind("SUPER + SHIFT + TAB", "Previous workspace", hl.dsp.focus({ workspace = "m-1" }))
        d.bind("SUPER + CTRL + TAB", "Former workspace", hl.dsp.focus({ workspace = "previous" }))
        d.bind("SUPER + mouse_down", "Next workspace", hl.dsp.focus({ workspace = "e+1" }))
        d.bind("SUPER + mouse_up", "Previous workspace", hl.dsp.focus({ workspace = "e-1" }))

        d.bind("SUPER + S", "Toggle scratchpad", hl.dsp.workspace.toggle_special("scratchpad"))
        d.bind("SUPER + ALT + S", "Move window to scratchpad", hl.dsp.window.move({ workspace = "special:scratchpad", follow = false }))

        -- Volume and brightness show Omarchy's on-screen display.
        local media = { locked = true, repeating = true }
        d.bind("XF86AudioRaiseVolume", "Volume up", "${swayosdClient} --output-volume raise", media)
        d.bind("XF86AudioLowerVolume", "Volume down", "${swayosdClient} --output-volume lower", media)
        d.bind("XF86AudioMute", "Mute", "${swayosdClient} --output-volume mute-toggle", { locked = true })
        d.bind("XF86AudioMicMute", "Mute microphone", "${swayosdClient} --input-volume mute-toggle", { locked = true })
        d.bind("XF86MonBrightnessUp", "Brightness up", "${swayosdClient} --brightness raise", media)
        d.bind("XF86MonBrightnessDown", "Brightness down", "${swayosdClient} --brightness lower", media)

        d.bind("XF86AudioPlay", "Play or pause", "${playerctl} play-pause", { locked = true })
        d.bind("XF86AudioPause", "Play or pause", "${playerctl} play-pause", { locked = true })
        d.bind("XF86AudioNext", "Next track", "${playerctl} next", { locked = true })
        d.bind("XF86AudioPrev", "Previous track", "${playerctl} previous", { locked = true })
      '';
    };
  };
}
