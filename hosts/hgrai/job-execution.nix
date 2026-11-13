{ lib, pkgs, ... }:
let
  codex = import ../../packages/codex.nix { inherit lib pkgs; };
  driver = pkgs.callPackage ../../packages/cua-driver.nix { };
  desktop = import ../../modules/home/cua-runtime.nix {
    inherit lib pkgs driver;
    display = ":47";
  };
  cuaBase = {
    driver = lib.getExe driver;
    desktop = lib.getExe desktop.desktop;
    run = lib.getExe desktop.run;
    displayFiles = [
      "/tmp/.X47-lock"
      "/tmp/.X11-unix/X47"
    ];
  };
  cuaBaseConfig = pkgs.writeText "support-cua-schema-config.json" (builtins.toJSON cuaBase);
  schemas = pkgs.runCommand "support-cua-tools.json" { } ''
    ${lib.getExe pkgs.python3} ${./job-cua.py} ${cuaBaseConfig} --schema > "$out"
  '';
  cuaConfig = pkgs.writeText "support-job-cua.json" (
    builtins.toJSON (cuaBase // { schemasFile = schemas; })
  );
  cua = pkgs.writeShellScript "support-job-cua" ''
    exec ${lib.getExe pkgs.python3} ${./job-cua.py} ${cuaConfig}
  '';
  config = pkgs.writeText "support-job-codex.toml" ''
    model_provider = "support_proxy"
    model = "gpt-6.1-sol"
    approval_policy = "never"
    sandbox_mode = "danger-full-access"
    allow_login_shell = false
    mcp_optional_startup_grace_ms = 10000
    [features]
    multi_agent = false
    multi_agent_v2 = false
    [model_providers.support_proxy]
    name = "Support credential proxy"
    base_url = "http://127.0.0.1:8000/model"
    wire_api = "responses"
    requires_openai_auth = false
    supports_websockets = false
    [mcp_servers.cua-driver]
    command = "${cua}"
    [mcp_servers.cua-driver.env]
    HOME = "/home/job"
    XDG_RUNTIME_DIR = "/tmp/job-runtime"
    XDG_CONFIG_HOME = "/home/job/.config"
    XDG_CACHE_HOME = "/home/job/.cache"
    XDG_DATA_HOME = "/home/job/.local/share"
    XDG_DATA_DIRS = "${pkgs.openbox}/share:${pkgs.at-spi2-core}/share:${pkgs.gsettings-desktop-schemas}/share:${pkgs.shared-mime-info}/share:${pkgs.adwaita-icon-theme}/share"
    FONTCONFIG_FILE = "/etc/fonts/fonts.conf"
    FONTCONFIG_PATH = "/etc/fonts"
    LANG = "en_US.UTF-8"
    LOCALE_ARCHIVE = "${pkgs.glibcLocales}/lib/locale/locale-archive"
    HTTP_PROXY = "http://127.0.0.1:8000"
    HTTPS_PROXY = "http://127.0.0.1:8000"
    NO_PROXY = "127.0.0.1,localhost"
  '';
  chromium = pkgs.writeShellScriptBin "chromium" ''
    exec ${lib.getExe pkgs.chromium} --proxy-server=http://127.0.0.1:8000 "$@"
  '';
  runtime = pkgs.writeShellScript "support-job-runtime" ''
    set -eu
    export PATH=${
      lib.makeBinPath [
        chromium
        pkgs.git
        pkgs.nodejs
        pkgs.python3
        pkgs.ripgrep
        pkgs.curl
        pkgs.jq
        pkgs.coreutils
        pkgs.bash
        pkgs.gnused
        pkgs.gnugrep
        pkgs.gnutar
        pkgs.gzip
      ]
    }
    export HOME=/home/job CODEX_HOME=/home/job/.codex XDG_RUNTIME_DIR=/tmp/job-runtime
    export XDG_CONFIG_HOME=/home/job/.config XDG_CACHE_HOME=/home/job/.cache XDG_DATA_HOME=/home/job/.local/share
    export FONTCONFIG_FILE=/etc/fonts/fonts.conf FONTCONFIG_PATH=/etc/fonts
    export LANG=en_US.UTF-8 LOCALE_ARCHIVE=${pkgs.glibcLocales}/lib/locale/locale-archive
    mkdir -p "$CODEX_HOME" "$XDG_RUNTIME_DIR"
    chmod 700 "$HOME" "$XDG_RUNTIME_DIR"
    cp ${config} "$CODEX_HOME/config.toml"
    mkdir -p "$HOME/.agents/skills"
    ln -sfn ${driver}/share/cua-driver/skill "$HOME/.agents/skills/cua-driver"
    export HTTP_PROXY=http://127.0.0.1:8000 HTTPS_PROXY=http://127.0.0.1:8000
    export http_proxy="$HTTP_PROXY" https_proxy="$HTTPS_PROXY" NO_PROXY=127.0.0.1,localhost
    ${lib.getExe pkgs.nodejs} ${./job-network.mjs} &
    cd "$1"
    # Even baseline Git processing belongs inside the unprivileged job: tracked
    # attributes and repository contents must never execute in the supervisor.
    if [ ! -d .git ]; then
      git init -q
      git -c core.hooksPath=/dev/null add --all
      git -c core.hooksPath=/dev/null -c user.name='Support job' \
        -c user.email=55928941+matifuentes2@users.noreply.github.com \
        commit -qm 'Investigation baseline' --allow-empty
    fi
    exec ${lib.getExe codex} app-server
  '';
  launcher = pkgs.writeShellScript "support-job-codex" ''
    # T3's health/model probes contain no ticket instructions. Serve these
    # with the installed CLI; actual thread sessions require a host lease.
    if [ "''${1:-}" = --version ]; then exec ${lib.getExe codex} --version; fi
    exec ${lib.getExe pkgs.python3} ${./job-client.py}
  '';
  supervisorConfig = pkgs.writeText "support-job-supervisor.json" (
    builtins.toJSON {
      socket = "/run/grai-job-supervisor/control.sock";
      proxySocket = "/run/grai-job-proxy/model.sock";
      state = "/var/lib/grai-job-archives";
      repository = "/home/coding-agent/repos/support-center";
      worktrees = "/home/coding-agent/.t3/worktrees";
      evidence = "/var/lib/grai-support-evidence";
      supportUrl = "https://support.graianalytics.com";
      supportToken = "/var/lib/grai-support-bridge-secrets/support-token";
      git = lib.getExe pkgs.git;
      shell = lib.getExe pkgs.bash;
      env = "${pkgs.coreutils}/bin/env";
      dbusDaemon = "${pkgs.dbus}/bin/dbus-daemon";
      inherit runtime;
    }
  );
in
{
  users.users.support-job = {
    isSystemUser = true;
    group = "support-job";
  };
  users.groups.support-job = { };
  environment.etc."grai-support-job-launcher".source = launcher;
  systemd.slices.grai-jobs.sliceConfig = {
    MemoryMax = "3G";
    MemorySwapMax = "256M";
    TasksMax = 768;
    CPUQuota = "200%";
    CPUWeight = 10;
  };
  # Budget interactive T3/CUA together as well: their separate agent/desktop
  # caps must not combine with support jobs to consume the entire 8 GiB host.
  systemd.slices."user-1001".sliceConfig = {
    MemoryMax = "3G";
    MemorySwapMax = "256M";
    TasksMax = 2048;
    CPUQuota = "200%";
  };
  systemd.tmpfiles.rules = [
    "d /var/lib/grai-job-archives 0711 root root -"
    "d /run/grai-job-proxy 0755 root root -"
  ];
  systemd.sockets.grai-job-proxy = {
    description = "Stable socket for the support model proxy";
    wantedBy = [ "sockets.target" ];
    socketConfig = {
      ListenStream = "/run/grai-job-proxy/model.sock";
      SocketMode = "0660";
      SocketGroup = "support-job";
      DirectoryMode = "0755";
    };
  };
  systemd.services.grai-job-proxy = {
    description = "Credential-isolated model and public egress proxy";
    requires = [ "grai-job-proxy.socket" ];
    after = [ "grai-job-proxy.socket" ];
    serviceConfig = {
      ExecStart = "${lib.getExe pkgs.nodejs} ${./job-proxy.mjs} /home/coding-agent/.codex/auth.json /run/grai-job-proxy/model.sock";
      Restart = "always";
      RestartSec = 5;
      UMask = "0077";
      LimitCORE = 0;
      NoNewPrivileges = true;
      ProtectSystem = "strict";
      ReadWritePaths = [
        "/run/grai-job-proxy"
        "/home/coding-agent/.codex"
      ];
      MemoryMax = "256M";
      TasksMax = 64;
      OOMScoreAdjust = -500;
    };
  };
  systemd.services.grai-job-supervisor = {
    description = "Independent support execution lease and sandbox supervisor";
    wantedBy = [ "multi-user.target" ];
    requires = [ "grai-job-proxy.socket" ];
    after = [ "grai-job-proxy.socket" ];
    path = [
      pkgs.systemd
      pkgs.util-linux
      pkgs.coreutils
      pkgs.e2fsprogs
      pkgs.rsync
    ];
    serviceConfig = {
      ExecStart = "${lib.getExe pkgs.python3} ${./job-supervisor.py} ${supervisorConfig}";
      ExecStopPost = "${pkgs.systemd}/bin/systemctl stop grai-job-*.service";
      Restart = "always";
      RestartSec = 2;
      RuntimeDirectory = "grai-job-supervisor";
      RuntimeDirectoryMode = "0755";
      UMask = "0077";
      LimitCORE = 0;
      MemoryMax = "256M";
      TasksMax = 64;
      OOMScoreAdjust = -500;
    };
  };
}
