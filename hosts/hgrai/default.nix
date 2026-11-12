{ pkgs, ... }:

let
  adminKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAt+/czluQsmX++mLb+H96Zy5SKcU7uzRikipfvG1FSn";
in
{
  imports = [
    ../../modules/system/common.nix
    ./hardware.nix
    ./disko.nix
    ./agents.nix
  ];

  networking = {
    hostName = "hgrai";
    useDHCP = false;
    useNetworkd = true;
    firewall.enable = true;
  };

  # Hetzner supplies the IPv4 /32 address and off-subnet gateway through DHCP.
  # Its IPv6 address and link-local gateway require explicit configuration.
  systemd.network.networks."10-wan" = {
    matchConfig.Name = "eth0";
    networkConfig = {
      DHCP = "ipv4";
      IPv6AcceptRA = false;
    };
    address = [ "2a01:4f9:c013:68a4::1/64" ];
    routes = [ { Gateway = "fe80::1"; } ];
    dhcpV4Config.ClientIdentifier = "mac";
    linkConfig.RequiredForOnline = "routable";
  };

  boot.loader = {
    grub.enable = false;
    systemd-boot = {
      enable = true;
      configurationLimit = 10;
    };
    efi.canTouchEfiVariables = true;
  };

  users.users.matif = {
    isNormalUser = true;
    uid = 1000;
    extraGroups = [ "wheel" ];
    openssh.authorizedKeys.keys = [ adminKey ];
  };
  # Keep key-only recovery access independent of the normal user account.
  users.users.root.openssh.authorizedKeys.keys = [ adminKey ];
  security.sudo.wheelNeedsPassword = false;

  services.openssh = {
    enable = true;
    openFirewall = true;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "prohibit-password";
    };
  };
  services.tailscale = {
    enable = true;
    openFirewall = true;
    extraSetFlags = [ "--operator=matif" ];
  };
  services.qemuGuest.enable = true;
  services.fstrim.enable = true;
  zramSwap.enable = true;

  nix.settings = {
    max-jobs = 2;
    cores = 2;
  };
  environment.systemPackages = with pkgs; [
    git
    vim
    curl
    jq
    htop
  ];

  # First NixOS installation; retain this value on future upgrades.
  system.stateVersion = "26.11";
}
