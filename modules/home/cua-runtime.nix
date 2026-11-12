# Shared X11 runtime used by the legacy desktop and independently leased slots.
{
  lib,
  pkgs,
  display,
  runtimeDir ? ".",
  xauthority ? null,
  geometry ? "1920x1080",
  driver ? null,
}:
let
  agent = {
    inherit
      display
      runtimeDir
      xauthority
      geometry
      ;
  };
  authorityExpression =
    if xauthority == null then ''"$XDG_RUNTIME_DIR/authority"'' else lib.escapeShellArg xauthority;
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
        if DISPLAY=${agent.display} XAUTHORITY=${authorityExpression} xdpyinfo >/dev/null 2>&1; then
          if [[ "''${1:-}" == --server-only ]] || \
            DISPLAY=${agent.display} XAUTHORITY=${authorityExpression} \
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
      printf '%s\n' "$DBUS_SESSION_BUS_ADDRESS" > "$dir/bus-address.tmp"
      mv "$dir/bus-address.tmp" "$dir/bus-address"
      wait -n
      exit 1
    '';
  };

  waitForAgentSession = pkgs.writeShellApplication {
    name = "cua-agent-session-wait";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.glib
    ];
    text = ''
      file="$XDG_RUNTIME_DIR/${agent.runtimeDir}/bus-address"
      for _ in $(seq 50); do
        if [[ -s "$file" ]]; then
          address="$(< "$file")"
          if timeout 0.2 gdbus call --address "$address" \
            --dest org.freedesktop.DBus --object-path /org/freedesktop/DBus \
            --method org.freedesktop.DBus.Peer.Ping >/dev/null 2>&1; then
            printf '%s\n' "$address"
            exit 0
          fi
        fi
        sleep 0.1
      done
      echo "agent session bus is not ready; check cua-agent-desktop.service" >&2
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
      pkgs.systemd
    ];
    text = ''
      # dbus-daemon also sends READY=1. Keep the notification endpoint out of
      # every child environment; only this supervisor declares full readiness.
      service_notify_endpoint="$NOTIFY_SOCKET"
      unset NOTIFY_SOCKET
      dir="$XDG_RUNTIME_DIR/${agent.runtimeDir}"
      rm -f -- "$dir/bus-address"
      export XAUTHORITY=${authorityExpression}
      mkdir -p "$(dirname "$XAUTHORITY")"
      # A fresh cookie per start; created 0600 so it is never readable by others.
      rm -f "$XAUTHORITY"
      (umask 077 && : > "$XAUTHORITY")
      xauth -q add "${agent.display}" MIT-MAGIC-COOKIE-1 "$(mcookie)"

      # Xvnc can notify systemd itself; only our full-session readiness probe
      # may release the dependent driver.
      Xvnc "${agent.display}" -auth "$XAUTHORITY" \
        -geometry ${agent.geometry} -depth 24 -nolisten tcp \
        -rfbport -1 -rfbunixpath "$dir/vnc.sock" -rfbunixmode 0600 \
        -SecurityTypes None -AlwaysShared &
      xserver_pid=$!

      ${lib.getExe waitForAgentDisplay} --server-only

      export DISPLAY="${agent.display}"
      # Supply the AT-SPI D-Bus activation file even before any desktop login.
      export XDG_DATA_DIRS="${pkgs.at-spi2-core}/share:''${XDG_DATA_DIRS:-/run/current-system/sw/share}"
      dbus-run-session -- ${lib.getExe agentSession} &
      session_pid=$!

      # agentSession publishes this only after the WM and AT-SPI registry
      # answer. Fail startup if either supervised child exits or times out.
      for _ in $(seq 200); do
        kill -0 "$xserver_pid"
        kill -0 "$session_pid"
        if [[ -s "$dir/bus-address" ]]; then
          ${lib.optionalString (driver != null) ''
            driver_socket="$dir/driver-$CUA_POOL_LEASE.sock"
            ${lib.getExe agentRun} ${lib.getExe driver} serve --socket "$driver_socket" &
            driver_pid=$!
            driver_ready=false
            for _ in $(seq 100); do
              kill -0 "$driver_pid"
              if [[ -S "$driver_socket" ]] && \
                timeout 1 ${lib.getExe driver} call --socket "$driver_socket" health_report | \
                  ${lib.getExe pkgs.jq} -e '.overall == "ok"' >/dev/null; then
                driver_ready=true
                break
              fi
              sleep 0.1
            done
            if [[ "$driver_ready" != true ]]; then
              echo "agent driver did not become ready" >&2
              exit 1
            fi
          ''}
          NOTIFY_SOCKET="$service_notify_endpoint" systemd-notify --ready
          wait -n
          exit 1
        fi
        sleep 0.1
      done
      echo "agent desktop session did not become ready" >&2
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
      export XAUTHORITY=${authorityExpression}
      ${lib.optionalString (driver != null) ''
        if [[ -z "''${CUA_POOL_LEASE:-}" || ! -r "$XDG_RUNTIME_DIR/lease.id" ]] || \
          [[ "$(< "$XDG_RUNTIME_DIR/lease.id")" != "$CUA_POOL_LEASE" ]]; then
          echo "desktop lease is no longer active" >&2
          exit 2
        fi
      ''}
      DBUS_SESSION_BUS_ADDRESS="$(${lib.getExe waitForAgentSession})"
      export DBUS_SESSION_BUS_ADDRESS
      unset AT_SPI_BUS_ADDRESS
      exec "$@"
    '';
  };
in
{
  environment = agentEnvironment;
  unsetEnvironment = waylandVariables;
  desktop = agentDesktop;
  run = agentRun;
  view = agentView;
  waitForDisplay = waitForAgentDisplay;
}
