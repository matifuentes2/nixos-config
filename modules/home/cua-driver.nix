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
  poolEnabled = agentDesktopEnabled && cfg.pool.enable;
  pool = "${cfg.pool.clientPackage}/bin/cua-pool";
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

  runtime = import ./cua-runtime.nix {
    inherit lib pkgs;
    inherit (agent)
      display
      geometry
      runtimeDir
      xauthority
      ;
  };
  agentEnvironment = runtime.environment;
  waylandVariables = runtime.unsetEnvironment;
  agentDesktop = runtime.desktop;
  agentRun = pkgs.writeShellApplication {
    name = "cua-agent-run";
    text = ''
      ${lib.optionalString poolEnabled ''
        if [[ -n "''${CUA_POOL_LEASE:-}" ]]; then
          exec ${pool} run "$CUA_POOL_LEASE" -- "$@"
        fi
      ''}
      exec ${lib.getExe runtime.run} "$@"
    '';
  };
  agentView = pkgs.writeShellApplication {
    name = "cua-agent-view";
    text = ''
      ${lib.optionalString poolEnabled ''
        if [[ -n "''${CUA_POOL_LEASE:-}" ]]; then
          exec ${pool} view "$CUA_POOL_LEASE" -- "$@"
        fi
      ''}
      exec ${lib.getExe runtime.view} "$@"
    '';
  };
  waitForAgentDisplay = runtime.waitForDisplay;
  agentBrowser = pkgs.writeShellApplication {
    name = "cua-agent-browser";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      ${lib.optionalString poolEnabled ''
        if [[ -n "''${CUA_POOL_LEASE:-}" ]]; then
          exec ${pool} browser "$CUA_POOL_LEASE" -- "$@"
        fi
      ''}
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
      (if poolEnabled then cfg.pool.clientPackage else cuaDriver)
      agentRun
    ];
    text = ''
      ${lib.optionalString poolEnabled ''
        if [[ -z "''${CUA_POOL_LEASE:-}" && "''${CUA_LEGACY_DESKTOP:-}" != 1 ]]; then
          exec ${pool} exec --name native-smoke -- \
            ${lib.getExe pkgs.python3} ${../../scripts/cua-smoke.py} \
            --zenity ${lib.getExe pkgs.zenity} "$@"
        fi
      ''}
      exec ${lib.getExe pkgs.python3} ${../../scripts/cua-smoke.py} \
        --zenity ${lib.getExe pkgs.zenity} "$@"
    '';
  };
  agentBrowserSmoke = pkgs.writeShellApplication {
    name = "cua-agent-browser-smoke";
    runtimeInputs = [
      (if poolEnabled then cfg.pool.clientPackage else cuaDriver)
      agentRun
    ];
    text = ''
      ${lib.optionalString poolEnabled ''
        if [[ -z "''${CUA_POOL_LEASE:-}" && "''${CUA_LEGACY_DESKTOP:-}" != 1 ]]; then
          exec ${pool} exec --name browser-smoke -- \
            ${lib.getExe pkgs.python3} ${../../scripts/cua-browser-smoke.py} \
            --chromium ${lib.getExe pkgs.chromium} \
            --fixture ${../../tests/cua-browser.html} "$@"
        fi
      ''}
      exec ${lib.getExe pkgs.python3} ${../../scripts/cua-browser-smoke.py} \
        --chromium ${lib.getExe pkgs.chromium} \
        --fixture ${../../tests/cua-browser.html} "$@"
    '';
  };
in
{
  imports = [ ./cua-pool.nix ];
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
      home.packages = [ (if poolEnabled then lib.lowPrio cuaDriver else cuaDriver) ];

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
        agentBrowserSmoke
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
