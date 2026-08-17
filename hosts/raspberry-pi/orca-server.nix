{ lib, pkgs, ... }:

let
  version = "1.4.184";

  src = pkgs.fetchurl {
    url = "https://github.com/stablyai/orca/releases/download/v${version}/orca-linux-arm64.AppImage";
    hash = "sha256-dnrfGkmSIyNWpDZu1LaxaHKpmOwaeH37Yz77Nm5GdG8=";
  };

  appImageContents = pkgs.appimageTools.extractType2 {
    pname = "orca-ide";
    inherit version src;
  };

  orcaApp = pkgs.appimageTools.wrapType2 {
    pname = "orca-ide";
    inherit version src;

    # Although `orca serve` is headless, Electron still needs a virtual X
    # server. Orca discovers and starts Xvfb itself when it is on PATH.
    extraPkgs = pkgs: [ pkgs.xorg-server ];

    # The FHS wrapper normally replaces /etc. Keep the Raspberry Pi's tracked
    # source-of-truth checkout visible so Orca agents can work in this repo.
    extraBwrapArgs = [ "--bind /etc/nixos /etc/nixos" ];
  };

  # Orca's Linux AppImage bundles its CLI entry point but does not expose it
  # as a top-level executable. Run that entry point with the bundled Electron
  # runtime in Node mode, matching Orca's own CLI installer.
  orcaCli = pkgs.writeShellScriptBin "orca" ''
    export ORCA_NODE_OPTIONS="''${NODE_OPTIONS-}"
    export ORCA_NODE_REPL_EXTERNAL_MODULE="''${NODE_REPL_EXTERNAL_MODULE-}"
    unset NODE_OPTIONS
    unset NODE_REPL_EXTERNAL_MODULE

    exec ${pkgs.coreutils}/bin/env ELECTRON_RUN_AS_NODE=1 \
      ${lib.getExe orcaApp} \
      ${appImageContents}/resources/app.asar.unpacked/out/cli/index.js \
      "$@"
  '';

  # Resolve the current Tailscale IPv4 address at service start rather than
  # committing a private tailnet address that may later change. Start Xvfb
  # outside the AppImage sandbox: the sandbox's private X11 socket directory
  # prevents Orca's built-in Xvfb fallback from becoming ready under systemd.
  serverLauncher = pkgs.writeShellScript "orca-server" ''
    mapfile -t addresses < <(${lib.getExe pkgs.tailscale} ip -4)
    if (( ''${#addresses[@]} == 0 )); then
      echo "Tailscale has no IPv4 address yet" >&2
      exit 1
    fi

    display_file="$RUNTIME_DIRECTORY/display"
    ${lib.getExe' pkgs.xorg-server "Xvfb"} \
      -displayfd 3 \
      -screen 0 1280x1024x24 \
      -nolisten tcp \
      3>"$display_file" &
    xvfb_pid=$!

    cleanup() {
      kill "$xvfb_pid" 2>/dev/null || true
      wait "$xvfb_pid" 2>/dev/null || true
    }
    trap cleanup EXIT INT TERM

    for _ in {1..50}; do
      if [[ -s "$display_file" ]]; then
        break
      fi
      if ! kill -0 "$xvfb_pid" 2>/dev/null; then
        echo "Xvfb exited before selecting a display" >&2
        exit 1
      fi
      ${lib.getExe' pkgs.coreutils "sleep"} 0.1
    done

    if [[ ! -s "$display_file" ]]; then
      echo "Xvfb did not select a display in time" >&2
      exit 1
    fi

    export DISPLAY=":$(<"$display_file")"
    exec ${lib.getExe orcaCli} serve \
      --port 6768 \
      --pairing-address "''${addresses[0]}" \
      --mobile-pairing
  '';
in
{
  environment.systemPackages = [ orcaCli ];

  # Orca is reachable only through Tailscale, never through a public or LAN
  # interface. Per-client Orca grants provide the application-level access.
  networking.firewall.interfaces.tailscale0.allowedTCPPorts = [ 6768 ];

  systemd.services.orca-server = {
    description = "Orca remote server";
    wantedBy = [ "multi-user.target" ];
    wants = [
      "network-online.target"
      "tailscaled.service"
    ];
    after = [
      "network-online.target"
      "tailscaled.service"
    ];

    environment = {
      HOME = "/home/pi";
      XDG_CACHE_HOME = "/home/pi/.cache";
      XDG_CONFIG_HOME = "/home/pi/.config";
      XDG_DATA_HOME = "/home/pi/.local/share";
      # Agent CLIs installed through Home Manager must remain visible to Orca.
      PATH = lib.mkForce "/etc/profiles/per-user/pi/bin:/home/pi/.nix-profile/bin:/run/current-system/sw/bin";
    };

    serviceConfig = {
      Type = "simple";
      User = "pi";
      Group = "users";
      WorkingDirectory = "/home/pi";
      RuntimeDirectory = "orca-server";
      RuntimeDirectoryMode = "0700";
      ExecStart = serverLauncher;
      KillMode = "control-group";
      Restart = "on-failure";
      RestartSec = 5;
    };
  };
}
