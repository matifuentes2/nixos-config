{ lib, pkgs, ... }:

let
  palette = import ./palette.nix;

  terminal = lib.getExe pkgs.kitty;
  launcher = lib.getExe pkgs.walker;
  fileManager = lib.getExe pkgs.thunar;
  lock = lib.getExe pkgs.hyprlock;
  grimblast = lib.getExe pkgs.grimblast;
  hyprpicker = lib.getExe pkgs.hyprpicker;
  pavucontrol = lib.getExe pkgs.pavucontrol;
  networkManager = lib.getExe pkgs.nmgui;
  bluetoothManager = lib.getExe pkgs.overskride;
  swayosdClient = lib.getExe' pkgs.swayosd "swayosd-client";
  playerctl = lib.getExe pkgs.playerctl;
  makoctl = lib.getExe' pkgs.mako "makoctl";
  loginctl = lib.getExe' pkgs.systemd "loginctl";
  pkill = lib.getExe' pkgs.procps "pkill";

  annotateScreenshot = pkgs.writeShellApplication {
    name = "hypr-annotate-screenshot";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.grimblast
      pkgs.satty
      pkgs.wl-clipboard
    ];
    text = ''
      screenshot="$(mktemp --suffix=.png)"
      trap 'rm -f "$screenshot"' EXIT
      grimblast save area "$screenshot"
      # Cancelling region selection must not open an empty image.
      [ -s "$screenshot" ] || exit 0
      satty --filename "$screenshot" --copy-command wl-copy
    '';
  };

  # Hyprland's own CLI must match the running compositor, so these scripts
  # use the hyprctl on PATH rather than pinning the nixpkgs build.
  windowSwitcher = pkgs.writeShellApplication {
    name = "hypr-window-switcher";
    text = ''
      exec ${launcher} --provider windows --placeholder 'Search open windows…'
    '';
  };

  # Toggle screen recording with wf-recorder. Recordings are saved to ~/Videos.
  # Hyprland's CLI must match the running compositor, so hyprctl comes from PATH.
  screenrecord = pkgs.writeShellApplication {
    name = "hypr-screenrecord";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.jq
      pkgs.libnotify
      pkgs.procps
      pkgs.slurp
      pkgs.util-linux
      pkgs.wf-recorder
    ];
    text = ''
      state="''${XDG_RUNTIME_DIR:-/tmp}/hypr-screenrecord"

      recording() { pgrep -x wf-recorder >/dev/null; }
      # Refresh the bar's recording indicator.
      refresh() { pkill -RTMIN+8 waybar || true; }

      start() {
        local -a args
        case "$1" in
          region)
            # Cancelling the selection must not start a recording.
            geometry="$(slurp)" || exit 0
            args=(-g "$geometry")
            ;;
          display)
            args=(-o "$(hyprctl -j monitors | jq -r '.[] | select(.focused) | .name')")
            ;;
        esac

        dir="$HOME/Videos"
        mkdir -p "$dir"
        file="$dir/screenrecording-$(date +%Y-%m-%d_%H-%M-%S).mp4"
        printf '%s\n' "$file" >"$state"
        setsid -f wf-recorder "''${args[@]}" -f "$file" >/dev/null 2>&1 </dev/null
        sleep 0.5
        refresh

        if recording; then
          notify-send -u low 'Screen recording started' 'Press Alt+Print or click the red dot in the top bar to stop'
        else
          rm -f "$state"
          notify-send -u critical 'Screen recording failed to start'
        fi
      }

      stop() {
        pkill -INT -x wf-recorder || true
        # wf-recorder finishes writing the file after SIGINT.
        for _ in $(seq 50); do
          recording || break
          sleep 0.1
        done
        refresh
        file="$(cat "$state" 2>/dev/null || true)"
        rm -f "$state"
        notify-send 'Screen recording saved' "''${file:-$HOME/Videos}"
      }

      case "''${1:-}" in
        region | display) recording || start "$1" ;;
        stop) stop ;;
        status) recording ;;
        *)
          echo 'usage: hypr-screenrecord region|display|stop|status' >&2
          exit 2
          ;;
      esac
    '';
  };

  # Omarchy-style menu in Walker's dmenu mode. Pass a submenu name to open it
  # directly; cancelling a submenu opened from the main menu goes back to it.
  menu = pkgs.writeShellApplication {
    name = "hypr-menu";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.gnused
      pkgs.libnotify
      pkgs.mako
      pkgs.procps
      pkgs.systemd
      pkgs.xdg-utils
    ];
    text = ''
      pick() {
        local prompt="$1"
        shift
        printf '%s\n' "$@" \
          | ${launcher} --dmenu --width 295 --minheight 1 --maxheight 600 --placeholder "$prompt…" 2>/dev/null \
          || true
      }

      # Let Walker close before capturing the screen.
      settle() { sleep 0.2; }

      # Each submenu returns non-zero when cancelled.
      learn_menu() {
        case "$(pick Learn '󰌌  Keybindings' '󰂺  Hyprland wiki' '  NixOS options' '󰋜  Home Manager options')" in
          *Keybindings) ${lib.getExe keybindings} ;;
          *"Hyprland wiki") xdg-open https://wiki.hypr.land/ ;;
          *"NixOS options") xdg-open https://search.nixos.org/options ;;
          *"Home Manager options") xdg-open https://home-manager-options.extranix.com/ ;;
          *) return 1 ;;
        esac
      }

      screenrecord_menu() {
        if ${lib.getExe screenrecord} status; then
          case "$(pick 'Screen recording' '󰓛  Stop recording')" in
            *"Stop recording") ${lib.getExe screenrecord} stop ;;
            *) return 1 ;;
          esac
        else
          case "$(pick 'Screen recording' '󰆞  Record area' '󰍹  Record display')" in
            *"Record area") settle && ${lib.getExe screenrecord} region ;;
            *"Record display") settle && ${lib.getExe screenrecord} display ;;
            *) return 1 ;;
          esac
        fi
      }

      capture_menu() {
        case "$(pick Capture '󰆞  Screenshot area' '󰆓  Screenshot area to file' '󰍹  Screenshot display to file' '󰏫  Annotate screenshot' '󰑊  Screen recording' '󰈊  Color picker')" in
          *"Screenshot area") settle && ${grimblast} --notify copy area ;;
          *"Screenshot area to file") settle && ${grimblast} --notify copysave area ;;
          *"Screenshot display to file") settle && ${grimblast} --notify copysave output ;;
          *"Annotate screenshot") settle && ${lib.getExe annotateScreenshot} ;;
          *"Screen recording") screenrecord_menu || capture_menu ;;
          *"Color picker") settle && ${hyprpicker} -a ;;
          *) return 1 ;;
        esac
      }

      toggle_menu() {
        case "$(pick Toggle '󰍜  Top bar' '󱫖  Idle locking' '󰂛  Do not disturb')" in
          *"Top bar") pkill -SIGUSR1 waybar ;;
          *"Idle locking") ${lib.getExe toggleIdle} ;;
          *"Do not disturb")
            makoctl mode -t do-not-disturb >/dev/null
            pkill -RTMIN+10 waybar || true
            ;;
          *) return 1 ;;
        esac
      }

      power_menu() {
        local current profile
        local -a options=()
        command -v powerprofilesctl >/dev/null || return 1
        current="$(powerprofilesctl get)"
        while IFS= read -r profile; do
          if [[ "$profile" == "$current" ]]; then
            options+=("󰄬  $profile")
          else
            options+=("   $profile")
          fi
        done < <(powerprofilesctl list | sed -n 's/^[* ] \([a-z-]*\):$/\1/p')

        profile="$(pick 'Power profile' "''${options[@]}")"
        [[ -n "$profile" ]] || return 1
        profile="''${profile##* }"
        powerprofilesctl set "$profile"
        notify-send -u low "Power profile: $profile"
      }

      setup_menu() {
        local -a options=('󰕾  Audio' '󰖩  Wi-Fi' '󰂯  Bluetooth')
        if command -v powerprofilesctl >/dev/null; then
          options+=('󰓅  Power profile')
        fi
        if command -v nwg-displays >/dev/null; then
          options+=('󰍹  Displays')
        fi

        case "$(pick Setup "''${options[@]}")" in
          *Audio) ${pavucontrol} ;;
          *Wi-Fi) ${networkManager} ;;
          *Bluetooth) ${bluetoothManager} ;;
          *"Power profile") power_menu || setup_menu ;;
          *Displays) nwg-displays ;;
          *) return 1 ;;
        esac
      }

      system_menu() {
        case "$(pick System '  Lock' '󰤄  Suspend' '󰍃  Log out' '󰜉  Restart' '󰐥  Shut down')" in
          *Lock) loginctl lock-session ;;
          *Suspend) systemctl suspend ;;
          *"Log out") hyprctl dispatch 'hl.dsp.exit()' ;;
          *Restart) systemctl reboot ;;
          *"Shut down") systemctl poweroff ;;
          *) return 1 ;;
        esac
      }

      main_menu() {
        case "$(pick Go '󰀻  Apps' '󰑴  Learn' '󰄀  Capture' '󰔡  Toggle' '󰒓  Setup' '󰐥  System')" in
          *Apps) ${launcher} ;;
          *Learn) learn_menu || main_menu ;;
          *Capture) capture_menu || main_menu ;;
          *Toggle) toggle_menu || main_menu ;;
          *Setup) setup_menu || main_menu ;;
          *System) system_menu || main_menu ;;
        esac
      }

      case "''${1:-main}" in
        main) main_menu ;;
        learn) learn_menu || true ;;
        capture) capture_menu || true ;;
        screenrecord) screenrecord_menu || true ;;
        toggle) toggle_menu || true ;;
        setup) setup_menu || true ;;
        power) power_menu || true ;;
        system) system_menu || true ;;
        *)
          echo 'usage: hypr-menu [main|learn|capture|screenrecord|toggle|setup|power|system]' >&2
          exit 2
          ;;
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
    menu
    screenrecord
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
            kb_options = "compose:ralt",
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
          "(org.pulseaudio.pavucontrol|com.network.manager|io.github.kaii_lb.Overskride|nm-connection-editor|.blueman-manager-wrapped|xdg-desktop-portal-gtk|imv|mpv|btop)",
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
        d.bind("SUPER + M", "Menu", "${lib.getExe menu}")
        d.bind("SUPER + ESCAPE", "System menu", "${lib.getExe menu} system")
        d.bind("SUPER + slash", "Show key bindings", "${lib.getExe keybindings}")
        d.bind("SUPER + CTRL + V", "Clipboard history", "${lib.getExe clipboardHistory}")
        d.bind("SUPER + CTRL + A", "Audio controls", "${pavucontrol}")
        d.bind("SUPER + CTRL + N", "Manage Wi-Fi", "${networkManager}")
        d.bind("SUPER + CTRL + B", "Manage Bluetooth", "${bluetoothManager}")
        d.bind("SUPER + CTRL + I", "Toggle locking on idle", "${lib.getExe toggleIdle}")
        d.bind("SUPER + CTRL + L", "Lock system", "${loginctl} lock-session")
        d.bind("SUPER + SHIFT + SPACE", "Toggle top bar", "${pkill} -SIGUSR1 waybar")
        d.bind("SUPER + SHIFT + E", "Log out", hl.dsp.exit())

        -- Notifications.
        d.bind("SUPER + comma", "Dismiss last notification", "${makoctl} dismiss")
        d.bind("SUPER + SHIFT + comma", "Dismiss all notifications", "${makoctl} dismiss --all")
        d.bind("SUPER + ALT + comma", "Restore last notification", "${makoctl} restore")
        d.bind("SUPER + CTRL + comma", "Toggle do not disturb", "${makoctl} mode -t do-not-disturb && ${pkill} -RTMIN+10 waybar")

        -- Screenshots, screen recording, and color picking.
        d.bind("PRINT", "Screenshot area to clipboard", "${grimblast} --notify copy area")
        d.bind("SHIFT + PRINT", "Screenshot area to file", "${grimblast} --notify copysave area")
        d.bind("CTRL + PRINT", "Screenshot display to file", "${grimblast} --notify copysave output")
        d.bind("SUPER + PRINT", "Color picker", "${pkill} hyprpicker || ${hyprpicker} -a")
        d.bind("SUPER + SHIFT + PRINT", "Annotate screenshot", "${lib.getExe annotateScreenshot}")
        d.bind("ALT + PRINT", "Start or stop screen recording", "${lib.getExe menu} screenrecord")

        -- Windows.
        d.bind("SUPER + W", "Close window", hl.dsp.window.close())
        d.bind("SUPER + Q", "Close window", hl.dsp.window.close())
        d.bind("SUPER + CTRL + J", "Toggle window split", hl.dsp.layout("togglesplit"))
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

        -- Vim-style focus and movement.
        for _, dir in ipairs({ { "H", "left" }, { "J", "down" }, { "K", "up" }, { "L", "right" } }) do
          local key, name = dir[1], dir[2]
          d.bind("SUPER + " .. key, "Focus window " .. name, hl.dsp.focus({ direction = name }))
          d.bind("SUPER + SHIFT + " .. key, "Move window " .. name, hl.dsp.window.move({ direction = name }))
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
