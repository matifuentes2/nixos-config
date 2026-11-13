{ nixpkgs }:
let
  system = "x86_64-linux";
  cfg =
    (nixpkgs.lib.nixosSystem {
      inherit system;
      modules = [
        ../hosts/hgrai/support-bridge.nix
        ../hosts/hgrai/job-execution.nix
        { system.stateVersion = "26.11"; }
      ];
    }).config;
  bridge = cfg.systemd.services.grai-support-bridge;
  checks = [
    (cfg.users.users.support-bridge.isSystemUser)
    (cfg.users.users.support-bridge.group == "support-bridge")
    (cfg.users.users.coding-agent.uid == 1001)
    (bridge.serviceConfig.User == "support-bridge")
    (bridge.serviceConfig.ProtectHome == true)
    (bridge.serviceConfig.ProtectSystem == "strict")
    (bridge.serviceConfig.NoNewPrivileges == true)
    (bridge.serviceConfig.CapabilityBoundingSet == "")
    (bridge.serviceConfig.StateDirectoryMode == "0700")
    (bridge.serviceConfig.Restart == "always")
    (cfg.users.users.support-job.isSystemUser)
    (cfg.systemd.slices.grai-jobs.sliceConfig.MemoryMax == "3G")
    (builtins.elem "grai-job-supervisor.service" bridge.requires)
    (builtins.length bridge.serviceConfig.LoadCredential == 3)
    (bridge.unitConfig.ConditionPathExists == "/var/lib/grai-support-bridge-secrets/support-token")
    (builtins.elem "grai-support-enrollment.service" bridge.requires)
    (!(builtins.elem "wheel" cfg.users.users.support-bridge.extraGroups))
  ];
in
assert builtins.all (value: value) checks;
nixpkgs.legacyPackages.${system}.runCommand "hgrai-support-bridge-check" { } ''
  export PYTHONDONTWRITEBYTECODE=1
  ${nixpkgs.legacyPackages.${system}.python3}/bin/python3 ${../hosts/hgrai}/job-supervisor.test.py
  ${nixpkgs.legacyPackages.${system}.nodejs}/bin/node --test ${../hosts/hgrai}/job-proxy.test.mjs
  touch "$out"
''
