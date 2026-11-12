{ nixpkgs }:
let
  system = "x86_64-linux";
  cfg =
    (nixpkgs.lib.nixosSystem {
      inherit system;
      modules = [
        ../hosts/hgrai/support-bridge.nix
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
    (builtins.length bridge.serviceConfig.LoadCredential == 3)
    (bridge.unitConfig.ConditionPathExists == "/var/lib/grai-support-bridge-secrets/support-token")
    (builtins.elem "grai-support-enrollment.service" bridge.requires)
    (!(builtins.elem "wheel" cfg.users.users.support-bridge.extraGroups))
  ];
in
assert builtins.all (value: value) checks;
nixpkgs.legacyPackages.${system}.runCommand "hgrai-support-bridge-check" { } ''
  touch "$out"
''
