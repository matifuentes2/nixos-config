# GlazeWM configuration for the Windows host underneath WSL2. Bindings mirror
# hyprland/default.nix where GlazeWM has an equivalent, using the left Windows
# key as SUPER. Windows reserves a few combinations that GlazeWM cannot
# intercept (notably Win+L, which always locks), so those Hyprland bindings are
# reachable only through their arrow-key alternatives.
{ lib, pkgs }:

let
  palette = import ../../../hyprland/palette.nix;

  bind = bindings: commands: { inherit bindings commands; };

  # Hyprland's workspace keys are the number row, with 0 selecting workspace 10.
  workspaceKeys = map (n: {
    name = toString n;
    key = toString (lib.mod n 10);
  }) (lib.range 1 10);

  directions = [
    {
      name = "left";
      keys = [
        "left"
        "h"
      ];
    }
    {
      name = "down";
      keys = [
        "down"
        "j"
      ];
    }
    {
      name = "up";
      keys = [
        "up"
        "k"
      ];
    }
    # Win+L is reserved by Windows for locking the session.
    {
      name = "right";
      keys = [ "right" ];
    }
  ];

  withMod = mod: map (key: "lwin+${mod}${key}");

  config = {
    general = {
      startup_commands = [ "shell-exec zebar" ];
      shutdown_commands = [ "shell-exec taskkill /IM zebar.exe /F" ];
      config_reload_commands = [ ];
      focus_follows_cursor = false;
      toggle_workspace_on_refocus = false;
      cursor_jump = {
        enabled = true;
        trigger = "monitor_focus";
      };
      hide_method = "cloak";
      show_all_in_taskbar = false;
    };

    # Hyprland uses gaps_in = 5 per side and gaps_out = 10. The top edge also
    # leaves room for Zebar.
    gaps = {
      scale_with_dpi = true;
      inner_gap = "10px";
      outer_gap = {
        top = "50px";
        right = "10px";
        bottom = "10px";
        left = "10px";
      };
    };

    window_effects =
      let
        effects = color: {
          border = {
            enabled = true;
            color = "#${color}";
          };
          hide_title_bar.enabled = false;
          corner_style = {
            enabled = true;
            style = "square";
          };
          transparency.enabled = false;
        };
      in
      {
        focused_window = effects palette.accent;
        other_windows = effects palette.muted;
      };

    window_behavior = {
      initial_state = "tiling";
      state_defaults = {
        floating = {
          centered = true;
          shown_on_top = false;
        };
        fullscreen = {
          maximized = false;
          shown_on_top = false;
        };
      };
    };

    workspaces = map (ws: { inherit (ws) name; }) workspaceKeys;

    # Upstream's default ignore rules for overlays that must not be tiled.
    window_rules = [
      {
        commands = [ "ignore" ];
        match = [
          # WSLg windows are RDP RemoteApp windows drawn by msrdc. Every resize
          # round-trips through Weston and the Linux app, so tiling shows stale
          # frames and fights Linux-side maximize even with GPU rendering.
          { window_process.equals = "msrdc"; }
          { window_process.equals = "zebar"; }
          {
            window_title.regex = "[Pp]icture.in.[Pp]icture";
            window_class.regex = "Chrome_WidgetWin_1|MozillaDialogClass";
          }
          {
            window_process.equals = "PowerToys";
            window_class.regex = "HwndWrapper\\[PowerToys\\.PowerAccent.*?\\]";
          }
          {
            window_title.equals = "Command Palette";
            window_class.equals = "WinUIDesktopWin32WindowClass";
          }
          {
            window_process.equals = "PowerToys";
            window_title.regex = ".*? - Peek";
          }
          {
            window_process.equals = "EXCEL";
            window_class.not_regex = "XLMAIN";
          }
          {
            window_process.equals = "WINWORD";
            window_class.not_regex = "OpusApp";
          }
          {
            window_process.equals = "POWERPNT";
            window_class.not_regex = "PPTFrameClass";
          }
        ];
      }
    ];

    binding_modes = [
      {
        name = "resize";
        keybindings = [
          (bind [ "h" "left" ] [ "resize --width -2%" ])
          (bind [ "l" "right" ] [ "resize --width +2%" ])
          (bind [ "k" "up" ] [ "resize --height +2%" ])
          (bind [ "j" "down" ] [ "resize --height -2%" ])
          (bind [ "escape" "enter" "lwin+r" ] [ "wm-disable-binding-mode --name resize" ])
        ];
      }
    ];

    keybindings = [
      # Applications.
      (bind [ "lwin+enter" ] [ "shell-exec wt" ])
      (bind [ "lwin+shift+f" ] [ "shell-exec explorer" ])

      # Window state.
      (bind [ "lwin+w" "lwin+q" ] [ "close" ])
      (bind [ "lwin+ctrl+j" ] [ "toggle-tiling-direction" ])
      (bind [ "lwin+t" ] [ "toggle-floating --centered" ])
      (bind [ "lwin+f" ] [ "toggle-fullscreen" ])
      (bind [ "lwin+alt+f" ] [ "toggle-fullscreen --maximized" ])

      # Resizing. oem_minus/oem_plus are the keys Hyprland binds as code:20/21.
      (bind [ "lwin+oem_minus" ] [ "resize --width -5%" ])
      (bind [ "lwin+oem_plus" ] [ "resize --width +5%" ])
      (bind [ "lwin+shift+oem_minus" ] [ "resize --height -5%" ])
      (bind [ "lwin+shift+oem_plus" ] [ "resize --height +5%" ])
      (bind [ "lwin+r" ] [ "wm-enable-binding-mode --name resize" ])

      # Workspace cycling.
      (bind [ "lwin+tab" ] [ "focus --next-active-workspace" ])
      (bind [ "lwin+shift+tab" ] [ "focus --prev-active-workspace" ])
      (bind [ "lwin+ctrl+tab" ] [ "focus --recent-workspace" ])

      # Window manager control. Pausing hands every key back to Windows.
      (bind [ "lwin+shift+p" ] [ "wm-toggle-pause" ])
      (bind [ "lwin+shift+r" ] [ "wm-reload-config" ])
      (bind [ "lwin+shift+e" ] [ "wm-exit" ])
    ]
    ++ lib.concatMap (dir: [
      (bind (withMod "" dir.keys) [ "focus --direction ${dir.name}" ])
      (bind (withMod "shift+" dir.keys) [ "move --direction ${dir.name}" ])
    ]) directions
    ++ lib.concatMap (ws: [
      (bind [ "lwin+${ws.key}" ] [ "focus --workspace ${ws.name}" ])
      (bind
        [ "lwin+shift+${ws.key}" ]
        [
          "move --workspace ${ws.name}"
          "focus --workspace ${ws.name}"
        ]
      )
      (bind [ "lwin+shift+alt+${ws.key}" ] [ "move --workspace ${ws.name}" ])
    ]) workspaceKeys;
  };
in
(pkgs.formats.yaml { }).generate "glazewm-config.yaml" config
