{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.ciCdCluster.localWorker;
  inherit (lib)
    mkDefault
    mkEnableOption
    mkIf
    mkOption
    types
    ;

  tokenPath = config.sops.secrets.k3s-agent-token.path;
  packageK3sVersion = lib.getVersion config.services.k3s.package;
  k3sVersion =
    if lib.hasPrefix "v" packageK3sVersion then packageK3sVersion else "v${packageK3sVersion}";
  tailscaleVersion = lib.getVersion config.services.tailscale.package;

  # This exact non-secret schema is attested by ci-cd-cluster before it may
  # acquire mutation authority. Keep it synchronized with that repository's
  # docs/nixos-local-worker-onboarding.md contract.
  contract = {
    schemaVersion = 1;
    platform = "nixos";
    system = pkgs.stdenv.hostPlatform.system;
    inherit (cfg)
      nodeName
      profile
      overlayIP
      lanCIDR
      clusterName
      projectName
      environment
      clusterCIDR
      privateSubnetCIDR
      ;
    serverAddr = "https://${cfg.controlPlaneIP}:6443";
    inherit k3sVersion tailscaleVersion;
    tokenFile = tokenPath;
    k3sUnit = "k3s.service";
    startGate = cfg.startGate;
    network = {
      interface = "k3s-local0";
      flannelInterface = "k3s-local0";
      managedBy = "nix-preparatory";
    };
    kubelet = {
      failSwapOn = false;
      memorySwap.swapBehavior = "NoSwap";
    };
    swap = {
      kind = "zram";
      podSwap = false;
    };
  };
in
{
  options.services.ciCdCluster.localWorker = {
    enable = mkEnableOption "declarative preparation for ci-cd-cluster local-worker onboarding";

    nodeName = mkOption {
      type = types.str;
      description = "Kubernetes Node name and reviewed local-worker inventory name.";
    };

    profile = mkOption {
      type = types.enum [
        "general"
        "dind"
      ];
      description = "Local-worker runner profile.";
    };

    overlayIP = mkOption {
      type = types.str;
      description = "Reviewed worker /32 address inside the cluster local-worker overlay.";
    };

    lanCIDR = mkOption {
      type = types.str;
      description = "Worker LAN CIDR protected by the local-worker egress guard.";
    };

    controlPlaneIP = mkOption {
      type = types.str;
      description = "Private IPv4 address of the k3s API server.";
    };

    privateSubnetCIDR = mkOption {
      type = types.str;
      description = "HCloud private subnet routed through Tailscale.";
    };

    clusterCIDR = mkOption {
      type = types.str;
      default = "10.42.0.0/16";
      description = "k3s Pod network CIDR.";
    };

    clusterName = mkOption {
      type = types.str;
      description = "Exact cluster name from the applied cluster platform configuration.";
    };

    projectName = mkOption {
      type = types.str;
      description = "Project label value from the applied cluster platform configuration.";
    };

    environment = mkOption {
      type = types.str;
      description = "Environment label value from the applied cluster platform configuration.";
    };

    sopsFile = mkOption {
      type = types.path;
      description = "SOPS file containing the encrypted k3s agent token.";
    };

    ageKeyFile = mkOption {
      type = types.str;
      default = "/var/lib/sops-nix/key.txt";
      description = "Host-local age identity used by sops-nix. This file is never committed.";
    };

    startGate = mkOption {
      type = types.str;
      default = "/etc/ci-cd-cluster/local-worker-network-ready";
      readOnly = true;
      description = "Root-owned marker created only after the onboarding route and token gates pass.";
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = pkgs.stdenv.hostPlatform.system == "x86_64-linux";
        message = "ci-cd-cluster local workers currently support only x86_64-linux NixOS.";
      }
      {
        assertion = builtins.match "^[a-z0-9]([-a-z0-9]*[a-z0-9])?$" cfg.nodeName != null;
        message = "services.ciCdCluster.localWorker.nodeName must be a lowercase DNS label.";
      }
      {
        assertion = builtins.match "^[0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+$" cfg.overlayIP != null;
        message = "services.ciCdCluster.localWorker.overlayIP must be an IPv4 address.";
      }
      {
        assertion = tokenPath == "/run/secrets/k3s-agent-token";
        message = "The decrypted k3s token path must be exactly /run/secrets/k3s-agent-token.";
      }
      {
        assertion = config.zramSwap.enable;
        message = "The reviewed NixOS local-worker contract requires zramSwap.enable = true.";
      }
      {
        assertion = config.swapDevices == [ ];
        message = "NixOS local workers permit zram only; declarative disk or file swapDevices are unsupported.";
      }
    ];

    sops = {
      age = {
        keyFile = cfg.ageKeyFile;
        sshKeyPaths = [ ];
      };
      secrets.k3s-agent-token = {
        inherit (cfg) sopsFile;
        key = "k3s-agent-token";
        name = "k3s-agent-token";
        owner = "root";
        group = "root";
        mode = "0400";
      };
    };

    # Host-only compressed swap remains available, while kubelet's NoSwap
    # policy below prevents Kubernetes workloads from consuming it.
    zramSwap.enable = mkDefault true;

    environment.systemPackages = [
      config.services.k3s.package
      config.services.tailscale.package
      pkgs.python3
    ];

    services.tailscale = {
      enable = true;
      openFirewall = true;
      useRoutingFeatures = "both";
    };

    services.k3s = {
      enable = true;
      role = "agent";
      serverAddr = "https://${cfg.controlPlaneIP}:6443";
      tokenFile = tokenPath;
      nodeName = cfg.nodeName;
      nodeIP = cfg.overlayIP;
      nodeLabel = [
        "capacity-source=local"
        "project=${cfg.projectName}"
        "environment=${cfg.environment}"
        "cluster=${cfg.clusterName}"
        "ephemeral=false"
        "workload=github-runner"
        "runner-pool=${cfg.profile}"
        "role=github-runner"
      ];
      nodeTaint = [
        "local-worker-bootstrap=true:NoSchedule"
        "github-runner=${cfg.profile}:NoSchedule"
      ];
      extraFlags = [ "--flannel-iface=k3s-local0" ];
      extraKubeletConfig = {
        failSwapOn = false;
        memorySwap.swapBehavior = "NoSwap";
      };
    };

    # A rebuild prepares the service but cannot join the cluster. The reviewed
    # administrator transaction creates this marker only after exact Tailscale
    # identity, /32 route approval, network guards, and token digest checks.
    systemd.services.k3s = {
      after = [
        "network-online.target"
        "tailscaled.service"
      ];
      wants = [ "network-online.target" ];
      unitConfig.ConditionPathExists = cfg.startGate;
    };

    environment.etc."ci-cd-cluster/local-worker-contract.json" = {
      mode = "0444";
      text = builtins.toJSON contract + "\n";
    };
  };
}
