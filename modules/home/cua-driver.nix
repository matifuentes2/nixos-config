{
  config,
  lib,
  pkgs,
  ...
}:

# Cua Driver gives Pi and Claude Code computer use: it inspects and operates
# native desktop applications through accessibility APIs, screenshots, and input.
# Import this only on hosts with a desktop session (Linux desktops and macOS),
# not WSL2.
let
  cuaDriver = pkgs.callPackage ../../packages/cua-driver.nix { };
  isLinux = pkgs.stdenv.hostPlatform.isLinux;
  cfg = config.services.cua-driver.agentDesktop;
  agentDesktopEnabled = isLinux && cfg.enable;
  # One runtime per desktop session, shared by Pi's MCP connection and the
  # `cua-driver call` CLI that the skill prefers. This is upstream's default.
  linuxSocket = "${config.home.homeDirectory}/.cache/cua-driver/cua-driver.sock";

  # With services.cua-driver.agentDesktop.enable, the Linux driver operates a
  # dedicated, headless X11 "agent desktop" instead of the user's Hyprland
  # session. Upstream's Wayland input needs the RemoteDesktop portal (libei), which no Hyprland or wlroots portal provides,
  # and its Hyprland window discovery fails on Hyprland 0.57. X11 with Openbox
  # is upstream's most complete Linux baseline: window discovery, per-window
  # capture, XTest keyboard and pointer input, and EWMH window geometry all
  # work. The agent also gets its own focus and pointer, so it never types
  # into the user's windows. See docs/cua-driver.md.
  agent = rec {
    display = ":47";
    geometry = "1920x1080";
    # Holds the VNC socket; relative to the private $XDG_RUNTIME_DIR.
    runtimeDir = "cua-agent";
    # Absolute path computed in Nix, so no unit depends on specifier (%t)
    # expansion and every process agrees on it. The file is mode 0600.
    xauthority = "${config.home.homeDirectory}/.cache/cua-driver/agent.Xauthority";
  };

  # Environment for the driver and every app it launches on the agent desktop.
  # Removing the Wayland variables keeps toolkits from attaching to Hyprland;
  # MOZ_NO_REMOTE stops Firefox from handing URLs to the user's own instance.
  agentEnvironment = {
    DISPLAY = agent.display;
    XDG_SESSION_TYPE = "x11";
    XDG_CURRENT_DESKTOP = "openbox";
    CUA_DRIVER_RS_ENABLE_WAYLAND = "0";
    GDK_BACKEND = "x11";
    QT_QPA_PLATFORM = "xcb";
    SDL_VIDEODRIVER = "x11";
    MOZ_ENABLE_WAYLAND = "0";
    MOZ_NO_REMOTE = "1";
    ELECTRON_OZONE_PLATFORM_HINT = "x11";
  };
  waylandVariables = [
    "WAYLAND_DISPLAY"
    "WAYLAND_SOCKET"
    "HYPRLAND_INSTANCE_SIGNATURE"
    "SWAYSOCK"
    "NIXOS_OZONE_WL"
  ];

  agentSocket = "/tmp/.X11-unix/X${lib.removePrefix ":" agent.display}";
  waitForAgentDisplay = pkgs.writeShellApplication {
    name = "cua-agent-wait";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      for _ in $(seq 100); do
        [ -S "${agentSocket}" ] && exit 0
        sleep 0.1
      done
      echo "agent X display ${agent.display} did not appear" >&2
      exit 1
    '';
  };

  # Xvnc is a complete X server with no physical output. Its VNC endpoint is a
  # 0600 unix socket inside the private runtime directory, never a TCP port.
  agentDesktop = pkgs.writeShellApplication {
    name = "cua-agent-desktop";
    runtimeInputs = [
      pkgs.tigervnc
      pkgs.openbox
      pkgs.xcompmgr
      pkgs.xauth
      pkgs.util-linux
      pkgs.coreutils
    ];
    text = ''
      dir="$XDG_RUNTIME_DIR/${agent.runtimeDir}"
      export XAUTHORITY="${agent.xauthority}"
      mkdir -p "$(dirname "$XAUTHORITY")"
      # A fresh cookie per start; created 0600 so it is never readable by others.
      rm -f "$XAUTHORITY"
      (umask 077 && : > "$XAUTHORITY")
      xauth -q add "${agent.display}" MIT-MAGIC-COOKIE-1 "$(mcookie)"

      Xvnc "${agent.display}" -auth "$XAUTHORITY" \
        -geometry ${agent.geometry} -depth 24 -nolisten tcp \
        -rfbport -1 -rfbunixpath "$dir/vnc.sock" -rfbunixmode 0600 \
        -SecurityTypes None -AlwaysShared &

      ${lib.getExe waitForAgentDisplay}

      export DISPLAY="${agent.display}"
      # Without a compositor the driver's agent-cursor overlay is drawn as an
      # opaque black shape over the screenshots it captures.
      xcompmgr &
      openbox &

      # Restart the whole desktop if any part exits.
      wait -n
      exit 1
    '';
  };

  # Watch (and, if needed, take over) the agent desktop.
  agentView = pkgs.writeShellApplication {
    name = "cua-agent-view";
    runtimeInputs = [ pkgs.tigervnc ];
    text = ''
      exec vncviewer "$@" "$XDG_RUNTIME_DIR/${agent.runtimeDir}/vnc.sock"
    '';
  };

  # Start an app on the agent desktop yourself, for example a browser profile
  # the agent should use: cua-agent-run firefox --profile ~/.mozilla/agent
  agentRun = pkgs.writeShellApplication {
    name = "cua-agent-run";
    text = ''
      unset ${lib.concatStringsSep " " waylandVariables}
      ${lib.concatStrings (
        lib.mapAttrsToList (name: value: "export ${name}=${lib.escapeShellArg value}\n") agentEnvironment
      )}
      export XAUTHORITY="${agent.xauthority}"
      exec "$@"
    '';
  };
in
{
  options.services.cua-driver.agentDesktop.enable = lib.mkEnableOption ''
    a dedicated headless X11 desktop (Xvnc and Openbox on ${agent.display}) that
    Cua Driver operates on Linux instead of the graphical session. It adds the
    cua-agent-desktop user service, the cua-agent-view and cua-agent-run
    helpers, and an agent skill describing the desktop. It has no effect on
    macOS'';

  config = lib.mkMerge [
    {
      home.packages = [ cuaDriver ];

      # On macOS `cua-driver mcp` proxies to /Applications/CuaDriver.app (installed
      # by hosts/macbook) and starts it on demand, so the app keeps its TCC grants.
      # On Linux it attaches to the session daemon below instead of starting a
      # second, separately permissioned runtime.
      pi.mcpServers.cua-driver = {
        command = lib.getExe cuaDriver;
        args = [
          "mcp"
        ]
        ++ lib.optionals isLinux [
          "--socket"
          linuxSocket
        ];
      };

      # Upstream's agent guidance (tool choice, element tokens, verification),
      # pinned to the same release as the binary. Claude Code uses the skill and
      # CLI directly; it does not need an MCP registration.
      home.file.".pi/agent/skills/cua-driver" = {
        source = "${cuaDriver}/share/cua-driver/skill";
        recursive = true;
      };

      home.file.".claude/skills/cua-driver" = {
        source = "${cuaDriver}/share/cua-driver/skill";
        recursive = true;
      };
    }

    # Without the agent desktop, the daemon runs inside the graphical session
    # so it inherits the Wayland/XWayland display and the accessibility
    # (AT-SPI) session bus.
    (lib.mkIf (isLinux && !cfg.enable) {
      systemd.user.services.cua-driver = {
        Unit = {
          Description = "Cua Driver computer-use daemon";
          Documentation = "https://cua.ai/docs/cua-driver";
          PartOf = [ "graphical-session.target" ];
          After = [ "graphical-session.target" ];
        };
        Service = {
          ExecStart = "${lib.getExe cuaDriver} serve --socket ${linuxSocket}";
          Restart = "on-failure";
          RestartSec = 5;
          # Computer use is interactive and should not compete with services.
          Nice = 5;
        };
        Install.WantedBy = [ "graphical-session.target" ];
      };
    })

    (lib.mkIf agentDesktopEnabled {
      home.packages = [
        agentView
        agentRun
      ];

      # Tells agents that computer use here targets the agent desktop rather
      # than the user's screen, and how to start apps on it.
      home.file.".pi/agent/skills/cua-agent-desktop/SKILL.md".source =
        ../../pi-skills/cua-agent-desktop/SKILL.md;
      home.file.".claude/skills/cua-agent-desktop/SKILL.md".source =
        ../../pi-skills/cua-agent-desktop/SKILL.md;

      systemd.user.services = {
        cua-agent-desktop = {
          Unit = {
            Description = "Headless X11 desktop operated by Cua Driver";
            PartOf = [ "graphical-session.target" ];
            After = [ "graphical-session.target" ];
          };
          Service = {
            ExecStart = lib.getExe agentDesktop;
            RuntimeDirectory = agent.runtimeDir;
            RuntimeDirectoryMode = "0700";
            UnsetEnvironment = waylandVariables ++ [ "DISPLAY" ];
            Restart = "on-failure";
            RestartSec = 5;
            Nice = 5;
          };
          Install.WantedBy = [ "graphical-session.target" ];
        };

        # The daemon still runs inside the graphical session so it shares the
        # accessibility (AT-SPI) session bus, but it is bound to the agent desktop.
        cua-driver = {
          Unit = {
            Description = "Cua Driver computer-use daemon";
            Documentation = "https://cua.ai/docs/cua-driver";
            PartOf = [ "graphical-session.target" ];
            BindsTo = [ "cua-agent-desktop.service" ];
            After = [
              "graphical-session.target"
              "cua-agent-desktop.service"
            ];
          };
          Service = {
            Environment = lib.mapAttrsToList (name: value: "${name}=${value}") agentEnvironment ++ [
              "XAUTHORITY=${agent.xauthority}"
            ];
            UnsetEnvironment = waylandVariables;
            # Wait for the agent X server, which the desktop unit starts asynchronously.
            ExecStartPre = lib.getExe waitForAgentDisplay;
            ExecStart = "${lib.getExe cuaDriver} serve --socket ${linuxSocket}";
            Restart = "on-failure";
            RestartSec = 5;
            # Computer use is interactive and should not compete with services.
            Nice = 5;
          };
          Install.WantedBy = [ "graphical-session.target" ];
        };
      };
    })
  ];
}
