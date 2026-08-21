{
  nixpkgs,
  sops-nix,
}:

let
  system = "x86_64-linux";
  pkgs = nixpkgs.legacyPackages.${system};
  module = {
    imports = [
      sops-nix.nixosModules.sops
      ../modules/system/ci-cd-local-worker.nix
    ];
    system.stateVersion = "26.11";
  };
  disabled = nixpkgs.lib.nixosSystem {
    inherit system;
    modules = [ module ];
  };
  workerConfig = {
    zramSwap.enable = true;
    services.ciCdCluster.localWorker = {
      enable = true;
      nodeName = "test-local-worker";
      profile = "dind";
      overlayIP = "10.20.255.10";
      lanCIDR = "192.168.1.0/24";
      controlPlaneIP = "10.20.0.10";
      privateSubnetCIDR = "10.20.0.0/24";
      clusterName = "github-arc-production";
      projectName = "github-arc";
      environment = "production";
      # Evaluation needs only a path. No real recipient, ciphertext, or
      # secret is created until a future host explicitly opts in.
      sopsFile = builtins.toFile "local-worker-evaluation-only.yaml" "{}\n";
    };
  };
  enabled = nixpkgs.lib.nixosSystem {
    inherit system;
    modules = [
      module
      workerConfig
    ];
  };
  diskSwap = nixpkgs.lib.nixosSystem {
    inherit system;
    modules = [
      module
      workerConfig
      { swapDevices = [ { device = "/swapfile"; } ]; }
    ];
  };
  alternateSecretPath = nixpkgs.lib.nixosSystem {
    inherit system;
    modules = [
      module
      workerConfig
      { sops.secrets.k3s-agent-token.name = nixpkgs.lib.mkForce "custom-token"; }
    ];
  };
  cfg = enabled.config;
  contract = builtins.fromJSON cfg.environment.etc."ci-cd-cluster/local-worker-contract.json".text;
  checks = [
    (!disabled.config.services.k3s.enable)
    (!disabled.config.services.tailscale.enable)
    (!(disabled.config.environment.etc ? "ci-cd-cluster/local-worker-contract.json"))
    (!(disabled.config.sops.secrets ? "k3s-agent-token"))
    (!(disabled.config.systemd.services ? k3s))
    (cfg.services.k3s.enable)
    (cfg.services.k3s.role == "agent")
    (cfg.services.k3s.serverAddr == "https://10.20.0.10:6443")
    (cfg.services.k3s.tokenFile == "/run/secrets/k3s-agent-token")
    (cfg.services.k3s.extraKubeletConfig.failSwapOn == false)
    (cfg.services.k3s.extraKubeletConfig.memorySwap.swapBehavior == "NoSwap")
    (cfg.zramSwap.enable)
    (cfg.swapDevices == [ ])
    (!builtins.all (entry: entry.assertion) diskSwap.config.assertions)
    (!builtins.all (entry: entry.assertion) alternateSecretPath.config.assertions)
    (
      cfg.systemd.services.k3s.unitConfig.ConditionPathExists
      == "/etc/ci-cd-cluster/local-worker-network-ready"
    )
    (
      builtins.attrNames contract == [
        "clusterCIDR"
        "clusterName"
        "environment"
        "k3sUnit"
        "k3sVersion"
        "kubelet"
        "lanCIDR"
        "network"
        "nodeName"
        "overlayIP"
        "platform"
        "privateSubnetCIDR"
        "profile"
        "projectName"
        "schemaVersion"
        "serverAddr"
        "startGate"
        "swap"
        "system"
        "tailscaleVersion"
        "tokenFile"
      ]
    )
    (contract.platform == "nixos")
    (contract.system == system)
    (nixpkgs.lib.hasPrefix "v" contract.k3sVersion)
    (contract.profile == "dind")
    (contract.clusterName == "github-arc-production")
    (contract.projectName == "github-arc")
    (contract.environment == "production")
    (contract.network.managedBy == "nix-preparatory")
    (contract.tokenFile == "/run/secrets/k3s-agent-token")
    (contract.kubelet.failSwapOn == false)
    (contract.kubelet.memorySwap.swapBehavior == "NoSwap")
    (contract.swap.kind == "zram")
    (!contract.swap.podSwap)
  ];
in
assert builtins.all (value: value) checks;
pkgs.runCommand "ci-cd-local-worker-module-check" { } ''
  touch "$out"
''
