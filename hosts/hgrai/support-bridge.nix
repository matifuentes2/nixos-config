{
  lib,
  pkgs,
  ...
}:
let
  # Pin the reviewed private support-center source. Download at enrollment
  # time using the coding account's GitHub login, never a public Nix cache.
  revision = "46def8aabb00143f9f84826f231745351f46d8a4";
  packageDir = "/var/lib/grai-support-package/${revision}";
  secretsDir = "/var/lib/grai-support-bridge-secrets";
  evidenceDir = "/var/lib/grai-support-evidence";
  workspace = "/home/coding-agent/repos/support-center";
  repo = "https://github.com/GraiAnalytics/support-center";
  t3 = pkgs.callPackage ../../packages/t3-cli.nix { };
  template = pkgs.writeText "support-bridge-enrollment.json" (
    builtins.toJSON {
      supportUrl = "https://support.graianalytics.com";
      t3Url = "http://127.0.0.1:3773";
      inherit repo evidenceDir;
      workspaceRoot = workspace;
      baseRef = "origin/master";
      runtimeMode = "auto-accept-edits";
      pollMs = 10000;
      maxRunMs = 1800000;
    }
  );
  configured = {
    ConditionPathExists = "${secretsDir}/support-token";
  };
in
{
  users.users.support-bridge = {
    isSystemUser = true;
    group = "support-bridge";
    extraGroups = [ "coding-agent" ];
  };
  users.groups.support-bridge = { };
  # Keep the existing agent UID stable for its lingering user manager.
  users.users.coding-agent.uid = 1001;
  systemd.tmpfiles.rules = [
    "d ${secretsDir} 0700 root root -"
    "d /var/lib/grai-support-package 0755 root root -"
    "d ${evidenceDir} 2750 support-bridge coding-agent -"
  ];

  systemd.services.grai-support-package = {
    description = "Install the pinned private support bridge package";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    unitConfig = configured;
    path = [
      pkgs.util-linux
      pkgs.coreutils
      pkgs.gnutar
      pkgs.gzip
    ];
    serviceConfig = {
      Type = "oneshot";
      UMask = "0077";
    };
    script = ''
      if test -f ${packageDir}/bridge/bridge.mjs; then exit 0; fi
      stage=$(mktemp -d /var/lib/grai-support-package/.install.XXXXXX)
      trap 'rm -rf "$stage"' EXIT
      runuser --login coding-agent --command \
        '${lib.getExe pkgs.gh} api repos/GraiAnalytics/support-center/tarball/${revision}' > "$stage/source.tar.gz"
      mkdir "$stage/source"
      tar -xzf "$stage/source.tar.gz" -C "$stage/source" --strip-components=1 --wildcards '*/bridge/*.mjs'
      test -f "$stage/source/bridge/bridge.mjs"
      chmod -R a+rX "$stage/source"
      mv "$stage/source" ${packageDir}
    '';
  };
  systemd.services.grai-support-repository = {
    description = "Enroll the approved support-center repository in T3";
    after = [
      "network-online.target"
      "user@1001.service"
    ];
    wants = [ "network-online.target" ];
    unitConfig = configured;
    path = [
      pkgs.git
      pkgs.coreutils
      pkgs.systemd
      pkgs.gnused
      pkgs.curl
    ];
    environment = {
      HOME = "/home/coding-agent";
      XDG_RUNTIME_DIR = "/run/user/1001";
    };
    serviceConfig = {
      Type = "oneshot";
      User = "coding-agent";
      WorkingDirectory = "/home/coding-agent";
      UMask = "0077";
    };
    script = ''
      systemctl --user start t3-server
      for _ in $(seq 60); do
        if curl --max-time 1 -fsS http://127.0.0.1:3773/ >/dev/null 2>&1; then break; fi
        sleep 1
      done
      curl --max-time 1 -fsS http://127.0.0.1:3773/ >/dev/null
      mkdir -p /home/coding-agent/repos
      if ! test -d ${workspace}/.git; then
        git -c 'credential.helper=!${lib.getExe pkgs.gh} auth git-credential' clone ${repo} ${workspace}
      fi
      actual=$(git -C ${workspace} remote get-url origin | sed 's#^git@github.com:#https://github.com/#; s#\.git$##; s#/$##')
      test "$actual" = '${repo}'
      git -C ${workspace} config credential.helper '!${lib.getExe pkgs.gh} auth git-credential'
      git -C ${workspace} fetch --prune origin
    '';
  };
  systemd.services.grai-support-enrollment = {
    description = "Enroll scoped T3 and support credentials";
    requires = [
      "grai-support-package.service"
      "grai-support-repository.service"
    ];
    after = [
      "grai-support-package.service"
      "grai-support-repository.service"
    ];
    unitConfig = configured;
    path = [
      pkgs.util-linux
      pkgs.coreutils
    ];
    serviceConfig = {
      Type = "oneshot";
      UMask = "0077";
    };
    script = ''
      ${lib.getExe pkgs.nodejs} ${packageDir}/bridge/bootstrap-t3.mjs ${secretsDir}/t3-session.json ${lib.getExe t3} coding-agent
      ${lib.getExe pkgs.nodejs} ${packageDir}/bridge/enroll.mjs ${template} ${secretsDir}
    '';
  };
  systemd.services.grai-support-bridge = {
    description = "Dispatch Grai Support jobs to T3 Code";
    wantedBy = [ "multi-user.target" ];
    wants = [ "network-online.target" ];
    requires = [ "grai-support-enrollment.service" ];
    after = [
      "network-online.target"
      "grai-support-enrollment.service"
    ];
    unitConfig = configured;
    serviceConfig = {
      User = "support-bridge";
      Group = "support-bridge";
      SupplementaryGroups = [ "coding-agent" ];
      ExecStart = "${lib.getExe pkgs.nodejs} ${packageDir}/bridge/bridge.mjs";
      LoadCredential = [
        "support-token:${secretsDir}/support-token"
        "t3-session:${secretsDir}/t3-session.json"
        "config:${secretsDir}/config.json"
      ];
      StateDirectory = "grai-support-bridge";
      StateDirectoryMode = "0700";
      ReadWritePaths = [ evidenceDir ];
      Restart = "always";
      RestartSec = 10;
      TimeoutStopSec = 120;
      UMask = "0077";
      NoNewPrivileges = true;
      PrivateTmp = true;
      ProtectHome = true;
      ProtectSystem = "strict";
      ProtectKernelTunables = true;
      ProtectControlGroups = true;
      RestrictSUIDSGID = true;
      CapabilityBoundingSet = "";
    };
  };
}
