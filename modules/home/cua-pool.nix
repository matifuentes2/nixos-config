{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.cua-driver.agentDesktop.pool;
  desktopCfg = config.services.cua-driver.agentDesktop;
  enabled = pkgs.stdenv.hostPlatform.isLinux && desktopCfg.enable && cfg.enable;
  target = if desktopCfg.headless then "default.target" else "graphical-session.target";
  driver = pkgs.callPackage ../../packages/cua-driver.nix { };
  ids = lib.range 1 cfg.slots;
  runtimeFor =
    id:
    import ./cua-runtime.nix {
      inherit lib pkgs driver;
      display = ":${toString (cfg.firstDisplay + id - 1)}";
    };
  unitFor = id: "cua-pool-slot-${toString id}.service";
  sliceFor = id: "cua-pool-slot${toString id}.slice";
  unset = [
    "WAYLAND_DISPLAY"
    "WAYLAND_SOCKET"
    "HYPRLAND_INSTANCE_SIGNATURE"
    "SWAYSOCK"
    "NIXOS_OZONE_WL"
    "AT_SPI_BUS_ADDRESS"
  ];
  manifest = pkgs.writeText "cua-pool-config.json" (
    builtins.toJSON {
      runtimeDirectory = "cua-pool";
      workspaceRoot = "${config.xdg.stateHome}/cua-pool/tasks";
      idleSeconds = cfg.idleSeconds;
      driver = lib.getExe driver;
      guide = "${driver}/share/cua-driver/skill/SKILL.md";
      chromium = lib.getExe pkgs.chromium;
      viewer = lib.getExe' pkgs.tigervnc "vncviewer";
      unsetEnvironment = unset;
      slots = map (id: {
        inherit id;
        unit = unitFor id;
        slice = sliceFor id;
        run = lib.getExe (runtimeFor id).run;
        environment = (runtimeFor id).environment;
      }) ids;
    }
  );
  pool = pkgs.writeShellApplication {
    name = "cua-pool";
    runtimeInputs = [ pkgs.systemd ];
    text = ''
      exec ${lib.getExe pkgs.python3} ${../../scripts/cua-pool.py} --config ${manifest} "$@"
    '';
  };
  routing = pkgs.writeShellApplication {
    name = "cua-driver";
    text = ''
      if [[ -n "''${CUA_POOL_LEASE:-}" ]]; then
        exec ${lib.getExe pool} driver -- "$@"
      fi
      if [[ "''${1:-}" == mcp && $# == 1 ]]; then
        exec ${lib.getExe pool} mcp
      fi
      if [[ "''${1:-}" == call && "''${CUA_LEGACY_DESKTOP:-}" != 1 ]]; then
        explicit_socket=false
        for arg in "$@"; do
          if [[ "$arg" == --socket || "$arg" == --socket=* ]]; then explicit_socket=true; fi
        done
        if [[ "$explicit_socket" != true ]]; then
          echo 'GUI calls need a desktop lease: use cua-pool exec or cua-pool acquire/call. Set CUA_LEGACY_DESKTOP=1 only for intentional shared legacy use.' >&2
          exit 2
        fi
      fi
      exec ${lib.getExe driver} "$@"
    '';
  };
  smoke = pkgs.writeShellApplication {
    name = "cua-pool-smoke";
    runtimeInputs = [ pool ];
    text = ''
      exec ${lib.getExe pkgs.python3} ${../../scripts/cua-pool-smoke.py} \
        --zenity ${lib.getExe pkgs.zenity} "$@"
    '';
  };
  # This package has no dependency on the legacy desktop helpers. Their small
  # dispatch branches can therefore refer to the pool without recursive builds.
  client = pkgs.symlinkJoin {
    name = "cua-pool-client";
    paths = [
      pool
      routing
      smoke
    ];
  };
in
{
  options.services.cua-driver.agentDesktop.pool = {
    enable = lib.mkEnableOption "on-demand leased Cua desktops for concurrent GUI tasks";
    slots = lib.mkOption {
      type = lib.types.ints.between 1 16;
      default = 2;
      description = "Maximum simultaneously leased desktops; idle slots run no processes.";
    };
    firstDisplay = lib.mkOption {
      type = lib.types.ints.between 48 100;
      default = 48;
      description = "First X11 display in the pool; display 47 remains the legacy desktop.";
    };
    idleSeconds = lib.mkOption {
      type = lib.types.ints.between 10 86400;
      default = 3600;
      description = "Release a manual lease after this many seconds without use or renewal. exec and mcp renew automatically.";
    };
    memoryMax = lib.mkOption {
      type = lib.types.str;
      default = "4G";
      description = "Aggregate systemd MemoryMax for all pool desktops and task apps.";
    };
    swapMax = lib.mkOption {
      type = lib.types.str;
      default = "512M";
      description = "Aggregate MemorySwapMax, limiting pool pressure on host swap.";
    };
    slotMemoryMax = lib.mkOption {
      type = lib.types.str;
      default = "2G";
      description = "MemoryMax for one leased desktop and its apps.";
    };
    cpuQuota = lib.mkOption {
      type = lib.types.str;
      default = "200%";
      description = "Aggregate CPUQuota for the pool (100% is one CPU).";
    };
    slotCPUQuota = lib.mkOption {
      type = lib.types.str;
      default = "200%";
      description = "CPUQuota for one leased desktop and its apps.";
    };
    clientPackage = lib.mkOption {
      type = lib.types.package;
      readOnly = true;
      default = if pkgs.stdenv.hostPlatform.isLinux then client else driver;
      internal = true;
    };
  };
  config = lib.mkIf enabled {
    home.packages = [ client ];
    pi.mcpServers.cua-driver = lib.mkForce {
      command = "${client}/bin/cua-pool";
      args = [ "mcp" ];
    };
    systemd.user.slices = {
      cua-pool = {
        Slice = {
          MemoryMax = cfg.memoryMax;
          MemorySwapMax = cfg.swapMax;
          CPUQuota = cfg.cpuQuota;
          TasksMax = 4096;
        };
      };
    }
    // lib.listToAttrs (
      map (
        id:
        lib.nameValuePair "cua-pool-slot${toString id}" {
          Slice = {
            MemoryMax = cfg.slotMemoryMax;
            CPUQuota = cfg.slotCPUQuota;
            TasksMax = 1024;
          };
        }
      ) ids
    );
    systemd.user.services = {
      cua-pool-manager = {
        Unit = {
          Description = "Lease broker for concurrent Cua desktops";
          PartOf = lib.optional (!desktopCfg.headless) target;
          After = [ "dbus.socket" ];
        };
        Service = {
          ExecStart = "${client}/bin/cua-pool serve";
          ExecStopPost = "${pkgs.systemd}/bin/systemctl --user stop ${
            lib.concatMapStringsSep " " sliceFor ids
          }";
          Environment = [
            "CUA_POOL_ROOT=%t/cua-pool"
            "CUA_POOL_USER_RUNTIME=%t"
            "CUA_POOL_CLIENT_PATH=${client}/bin:${config.home.profileDirectory}/bin:/run/current-system/sw/bin"
          ];
          RuntimeDirectory = "cua-pool";
          RuntimeDirectoryMode = "0700";
          UMask = "0077";
          Restart = "on-failure";
          RestartSec = 2;
          TimeoutStopSec = 45;
          NoNewPrivileges = true;
        };
        Install.WantedBy = [ target ];
      };
    }
    // lib.listToAttrs (
      map (
        id:
        lib.nameValuePair "cua-pool-slot-${toString id}" {
          Unit = {
            Description = "Isolated Cua desktop ${toString id}";
            Requires = [ "cua-pool-manager.service" ];
            BindsTo = [ "cua-pool-manager.service" ];
            After = [ "cua-pool-manager.service" ];
            PartOf = [ "cua-pool-manager.service" ];
          };
          Service = {
            ExecStart = lib.getExe (runtimeFor id).desktop;
            Type = "notify";
            NotifyAccess = "all";
            EnvironmentFile = "%t/cua-pool/slots/${toString id}/lease.env";
            RuntimeDirectory = "cua-pool/slots/${toString id}";
            RuntimeDirectoryMode = "0700";
            Slice = sliceFor id;
            UnsetEnvironment = unset;
            UMask = "0077";
            NoNewPrivileges = true;
            KillMode = "control-group";
            TimeoutStartSec = 60;
            TimeoutStopSec = 10;
            Restart = "no";
          };
        }
      ) ids
    );
  };
}
