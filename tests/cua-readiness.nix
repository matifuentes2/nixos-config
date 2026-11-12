{ pkgs, home-manager }:
let
  # The NixOS package normally finds this through /run/current-system. A
  # sandbox has no activated system, so use its exact declared dependency.
  sandboxAtSpi = pkgs.at-spi2-core.overrideAttrs (old: {
    mesonFlags = builtins.filter (flag: !(pkgs.lib.hasPrefix "-Ddbus_daemon=" flag)) old.mesonFlags ++ [
      "-Ddbus_daemon=${pkgs.dbus}/bin/dbus-daemon"
    ];
  });
  # Delay the real session bus and provide a failure case without changing the
  # production module. Its own READY=1 must never reach the notify socket.
  delayedDbus = pkgs.symlinkJoin {
    name = "cua-delayed-dbus";
    paths = [ pkgs.dbus ];
    postBuild = ''
      rm "$out/bin/dbus-run-session"
      cat > "$out/bin/dbus-run-session" <<'SH'
      #!${pkgs.runtimeShell}
      if [[ "''${CUA_READINESS_TEST_FAIL:-}" == 1 ]]; then exit 7; fi
      ${pkgs.coreutils}/bin/sleep 2
      exec ${pkgs.dbus}/bin/dbus-run-session \
        --config-file=${pkgs.dbus}/share/dbus-1/session.conf "$@"
      SH
      chmod +x "$out/bin/dbus-run-session"
    '';
  };
  home =
    (home-manager.lib.homeManagerConfiguration {
      inherit pkgs;
      modules = [
        ../modules/home/cua-driver.nix
        ({ lib, ... }: {
          options.pi.mcpServers = lib.mkOption {
            type = lib.types.attrs;
            default = { };
          };
          config = {
            # Override only the module's package argument, not the nixpkgs
            # fixpoint (which would rebuild GTK, FFmpeg and Xvnc).
            _module.args.pkgs = lib.mkForce (
              pkgs
              // {
                dbus = delayedDbus;
                at-spi2-core = sandboxAtSpi;
              }
            );
            home.username = "cua-test";
            home.homeDirectory = "/build/cua-home";
            home.stateVersion = "26.11";
            services.cua-driver.agentDesktop.enable = true;
          };
        })
      ];
    }).config;
  desktop = builtins.head home.systemd.user.services.cua-agent-desktop.Service.ExecStart;
  run = pkgs.lib.findFirst (
    p: p.name == "cua-agent-run"
  ) (throw "missing launcher") home.home.packages;
in
pkgs.runCommand "cua-readiness" { nativeBuildInputs = [ pkgs.python3 ]; } ''
  python3 ${./cua-readiness.py} ${desktop} ${run}/bin/cua-agent-run ${pkgs.coreutils}/bin/true
  touch "$out"
''
