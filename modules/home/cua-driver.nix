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
  agentTarget = if cfg.headless then "default.target" else "graphical-session.target";
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
    GTK_A11Y = "atspi";
    # The virtual X server has no accelerated presentation path.
    GSK_RENDERER = "cairo";
    # dbus-broker delegates service activation to the user manager, which is
    # outside this private bus. dbus-daemon can activate its AT-SPI registry.
    ATSPI_DBUS_IMPLEMENTATION = "dbus-daemon";
  };
  waylandVariables = [
    "WAYLAND_DISPLAY"
    "WAYLAND_SOCKET"
    "HYPRLAND_INSTANCE_SIGNATURE"
    "SWAYSOCK"
    "NIXOS_OZONE_WL"
  ];

  waitForAgentDisplay = pkgs.writeShellApplication {
    name = "cua-agent-wait";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.xdpyinfo
      pkgs.xprop
      pkgs.gnugrep
    ];
    text = ''
      for _ in $(seq 100); do
        if DISPLAY=${agent.display} XAUTHORITY=${lib.escapeShellArg agent.xauthority} xdpyinfo >/dev/null 2>&1; then
          if [[ "''${1:-}" == --server-only ]] || \
            DISPLAY=${agent.display} XAUTHORITY=${lib.escapeShellArg agent.xauthority} \
              xprop -root _NET_SUPPORTING_WM_CHECK 2>/dev/null | grep -q 'window id # 0x'; then
            exit 0
          fi
        fi
        sleep 0.1
      done
      echo "agent X display ${agent.display} did not appear" >&2
      exit 1
    '';
  };

  # A private session bus keeps AT-SPI discovery on the agent desktop as well.
  # Publish only its address, never shell code, for the driver and launch helper.
  agentSession = pkgs.writeShellApplication {
    name = "cua-agent-session";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.glib
      pkgs.openbox
      pkgs.xcompmgr
      pkgs.systemd
    ];
    text = ''
      umask 077
      dir="$XDG_RUNTIME_DIR/${agent.runtimeDir}"
      xcompmgr &
      openbox --config-file ${pkgs.openbox}/etc/xdg/openbox/rc.xml &
      ${lib.getExe waitForAgentDisplay}
      atspi_address="$(gdbus call --session --dest org.a11y.Bus --object-path /org/a11y/bus \
        --method org.a11y.Bus.GetAddress | cut -d "'" -f2)"
      gdbus call --address "$atspi_address" --dest org.a11y.atspi.Registry \
        --object-path /org/a11y/atspi/accessible/root \
        --method org.a11y.atspi.Accessible.GetChildren >/dev/null
      printf '%s\n' "$DBUS_SESSION_BUS_ADDRESS" > "$dir/bus-address"
      systemd-notify --ready
      wait -n
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
      pkgs.dbus
    ];
    text = ''
      dir="$XDG_RUNTIME_DIR/${agent.runtimeDir}"
      rm -f -- "$dir/bus-address"
      export XAUTHORITY="${agent.xauthority}"
      mkdir -p "$(dirname "$XAUTHORITY")"
      # A fresh cookie per start; created 0600 so it is never readable by others.
      rm -f "$XAUTHORITY"
      (umask 077 && : > "$XAUTHORITY")
      xauth -q add "${agent.display}" MIT-MAGIC-COOKIE-1 "$(mcookie)"

      # Xvnc can notify systemd itself; only our full-session readiness probe
      # may release the dependent driver.
      env -u NOTIFY_SOCKET Xvnc "${agent.display}" -auth "$XAUTHORITY" \
        -geometry ${agent.geometry} -depth 24 -nolisten tcp \
        -rfbport -1 -rfbunixpath "$dir/vnc.sock" -rfbunixmode 0600 \
        -SecurityTypes None -AlwaysShared &

      ${lib.getExe waitForAgentDisplay} --server-only

      export DISPLAY="${agent.display}"
      # Supply the AT-SPI D-Bus activation file even before any desktop login.
      export XDG_DATA_DIRS="${pkgs.at-spi2-core}/share:''${XDG_DATA_DIRS:-/run/current-system/sw/share}"
      dbus-run-session -- ${lib.getExe agentSession} &

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
    # Cua's optional Linux video recorder launches ffmpeg from the daemon PATH.
    # The default ffmpeg omits x11grab; full also provides cursor capture and x264.
    runtimeInputs = [ pkgs.ffmpeg-full ];
    text = ''
      unset ${lib.concatStringsSep " " waylandVariables}
      ${lib.concatStrings (
        lib.mapAttrsToList (name: value: "export ${name}=${lib.escapeShellArg value}\n") agentEnvironment
      )}
      export XAUTHORITY="${agent.xauthority}"
      dir="$XDG_RUNTIME_DIR/${agent.runtimeDir}"
      if [[ ! -r "$dir/bus-address" ]]; then
        echo "agent desktop is not ready; check cua-agent-desktop.service" >&2
        exit 1
      fi
      DBUS_SESSION_BUS_ADDRESS="$(< "$dir/bus-address")"
      export DBUS_SESSION_BUS_ADDRESS
      unset AT_SPI_BUS_ADDRESS
      exec "$@"
    '';
  };
  agentBrowser = pkgs.writeShellApplication {
    name = "cua-agent-browser";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      umask 077
      profile="$HOME/.local/share/cua-driver/chromium"
      mkdir -p "$profile"
      exec ${lib.getExe agentRun} ${lib.getExe pkgs.chromium} \
        --user-data-dir="$profile" --force-renderer-accessibility \
        --ozone-platform=x11 --password-store=gnome-libsecret \
        --no-first-run --no-default-browser-check "$@"
    '';
  };
  agentEditor = pkgs.writeShellApplication {
    name = "cua-agent-editor";
    text = ''
      exec ${lib.getExe agentRun} ${lib.getExe pkgs.mousepad} --disable-server "$@"
    '';
  };
  agentSmoke = pkgs.writeShellApplication {
    name = "cua-agent-smoke";
    runtimeInputs = [
      cuaDriver
      agentRun
    ];
    text = ''
      exec ${lib.getExe pkgs.python3} ${../../scripts/cua-smoke.py} \
        --zenity ${lib.getExe pkgs.zenity} "$@"
    '';
  };
in
{
  options.services.cua-driver.agentDesktop = {
    enable = lib.mkEnableOption ''
      a dedicated headless X11 desktop (Xvnc and Openbox on ${agent.display}) that
      Cua Driver operates on Linux instead of the graphical session. It adds the
      cua-agent-desktop user service, the cua-agent-view and cua-agent-run
      helpers, and an agent skill describing the desktop. It has no effect on
      macOS'';
    headless = lib.mkEnableOption ''
      start the agent desktop with the user manager, independently of graphical
      login or logout. The host must enable user lingering for boot-time startup'';
  };

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
      home.file.".agents/skills/cua-driver" = {
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
        agentBrowser
        agentEditor
        agentSmoke
      ];

      # Tells agents that computer use here targets the agent desktop rather
      # than the user's screen, and how to start apps on it.
      home.file.".pi/agent/skills/cua-agent-desktop/SKILL.md".source =
        ../../pi-skills/cua-agent-desktop/SKILL.md;
      home.file.".claude/skills/cua-agent-desktop/SKILL.md".source =
        ../../pi-skills/cua-agent-desktop/SKILL.md;
      home.file.".agents/skills/cua-agent-desktop/SKILL.md".source =
        ../../pi-skills/cua-agent-desktop/SKILL.md;

      systemd.user.services = {
        cua-agent-desktop = {
          Unit = {
            Description = "Headless X11 desktop operated by Cua Driver";
            Upholds = [ "cua-driver.service" ];
            PartOf = lib.optional (!cfg.headless) agentTarget;
            After = [ "dbus.socket" ] ++ lib.optional (!cfg.headless) agentTarget;
          };
          Service = {
            ExecStart = lib.getExe agentDesktop;
            Type = "notify";
            NotifyAccess = "all";
            TimeoutStartSec = 30;
            Environment = lib.mapAttrsToList (name: value: "${name}=${value}") agentEnvironment;
            RuntimeDirectory = agent.runtimeDir;
            RuntimeDirectoryMode = "0700";
            UnsetEnvironment = waylandVariables ++ [ "AT_SPI_BUS_ADDRESS" ];
            Restart = "on-failure";
            RestartSec = 5;
            Nice = 5;
            UMask = "0077";
          };
          Install.WantedBy = [ agentTarget ];
        };

        # Read the desktop's private D-Bus address at every daemon start.
        cua-driver = {
          Unit = {
            Description = "Cua Driver computer-use daemon";
            Documentation = "https://cua.ai/docs/cua-driver";
            PartOf = [ "cua-agent-desktop.service" ];
            Requires = [ "cua-agent-desktop.service" ];
            After = [ "cua-agent-desktop.service" ];
          };
          Service = {
            Environment = lib.mapAttrsToList (name: value: "${name}=${value}") agentEnvironment ++ [
              "XAUTHORITY=${agent.xauthority}"
            ];
            UnsetEnvironment = waylandVariables;
            # Wait for the agent X server, which the desktop unit starts asynchronously.
            ExecStartPre = lib.getExe waitForAgentDisplay;
            ExecStart = "${lib.getExe agentRun} ${lib.getExe cuaDriver} serve --socket ${linuxSocket}";
            Restart = "on-failure";
            RestartSec = 5;
            # Computer use is interactive and should not compete with services.
            Nice = 5;
            UMask = "0077";
          };
          Install.WantedBy = [ agentTarget ];
        };
      };
    })
  ];
}
