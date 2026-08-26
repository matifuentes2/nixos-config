# Raspberry Pi-specific NixOS configuration. Help is available in the
# configuration.nix(5) man page and on
# https://search.nixos.org/options and in the NixOS manual (`nixos-help`).

{ pkgs, ... }:

{
  imports = [
    ../../modules/system/common.nix
    ../../modules/system/linux-desktop.nix
    ./hardware-configuration.nix
    ./orca-server.nix
  ];

  # Let tools such as uv run upstream, dynamically linked Python builds.
  programs.nix-ld.enable = true;

  # Collie's VAPID private key is encrypted in the repository. sops-nix
  # decrypts its dotenv file for the Collie user service at activation time.
  sops = {
    defaultSopsFile = ../../secrets/collie.yaml;
    age = {
      keyFile = "/var/lib/sops-nix/key.txt";
      sshKeyPaths = [ ];
    };
    secrets."collie-env" = {
      owner = "pi";
      group = "users";
      mode = "0400";
    };
  };

  systemd.tmpfiles.rules = [
    "d /home/pi/.config/herdr/plugins/config/herdr.collie 0700 pi users -"
    "L+ /home/pi/.config/herdr/plugins/config/herdr.collie/.env - - - - /run/secrets/collie-env"
  ];

  # Use the extlinux boot loader. (NixOS wants to enable GRUB by default)
  boot.loader.grub.enable = false;
  # Enables the generation of /boot/extlinux/extlinux.conf
  boot.loader.generic-extlinux-compatible.enable = true;

  # Linux 6.18 repeatedly wedged the Pi 4's MMC worker in mmc_rescan.
  boot.kernelPackages = pkgs.linuxPackages_6_12;

  # Absorb transient agent memory spikes instead of invoking the OOM killer.
  zramSwap = {
    enable = true;
    memoryPercent = 50;
  };

  # networking.hostName = "nixos"; # Define your hostname.

  # Configure network connections interactively with nmcli or nmtui.
  networking.networkmanager.enable = true;

  # Set your time zone.
  # time.timeZone = "Europe/Amsterdam";

  # Configure network proxy if necessary
  # networking.proxy.default = "http://user:password@proxy:port/";
  # networking.proxy.noProxy = "127.0.0.1,localhost,internal.domain";

  # Select internationalisation properties.
  # i18n.defaultLocale = "en_US.UTF-8";
  # console = {
  #   font = "Lat2-Terminus16";
  #   keyMap = "us";
  #   useXkbConfig = true; # use xkb.options in tty.
  # };

  # Configure keymap in X11
  # services.xserver.xkb.layout = "us";
  # services.xserver.xkb.options = "eurosign:e,caps:escape";

  # Enable CUPS to print documents.
  # services.printing.enable = true;

  # Enable sound.
  # services.pulseaudio.enable = true;
  # OR
  # services.pipewire = {
  #   enable = true;
  #   pulse.enable = true;
  # };

  # Enable touchpad support (enabled default in most desktopManager).
  # services.libinput.enable = true;

  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users.pi = {
    isNormalUser = true;
    description = "Pi user";
    # Allow sudo and access to networking, graphics, and audio devices.
    extraGroups = [
      "wheel"
      "networkmanager"
      "video"
      "audio"
    ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAt+/czluQsmX++mLb+H96Zy5SKcU7uzRikipfvG1FSn"
    ];
  };

  programs.firefox.enable = true;

  # Packages installed in the system profile. Cross-platform user packages
  # belong in modules/home/common.nix instead.
  environment.systemPackages = with pkgs; [
    vim
    wget
    git
    gh
  ];

  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  # programs.mtr.enable = true;
  # programs.gnupg.agent = {
  #   enable = true;
  #   enableSSHSupport = true;
  # };

  # List services that you want to enable:

  # Enable Tailscale and allow direct peer-to-peer tunnel connections.
  services.tailscale = {
    enable = true;
    openFirewall = true;
    # Let the primary user manage tailnet-only Serve mappings without sudo.
    extraSetFlags = [ "--operator=pi" ];
  };

  # Enable key-only remote access through OpenSSH.
  services.openssh = {
    enable = true;
    openFirewall = true;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
    };
  };

  # Provide resilient remote shells over SSH and allow Mosh's UDP traffic.
  programs.mosh = {
    enable = true;
    openFirewall = true;
  };

  # Open ports in the firewall.
  # networking.firewall.allowedTCPPorts = [ ... ];
  # networking.firewall.allowedUDPPorts = [ ... ];
  # Or disable the firewall altogether.
  # networking.firewall.enable = false;

  # Copy the NixOS configuration file and link it from the resulting system
  # (/run/current-system/configuration.nix). This is useful in case you
  # accidentally delete configuration.nix.
  # system.copySystemConfiguration = true;

  # This option defines the first version of NixOS you have installed on this particular machine,
  # and is used to maintain compatibility with application data (e.g. databases) created on older NixOS versions.
  #
  # Most users should NEVER change this value after the initial install, for any reason,
  # even if you've upgraded your system to a new NixOS release.
  #
  # This value does NOT affect the Nixpkgs version your packages and OS are pulled from,
  # so changing it will NOT upgrade your system - see https://nixos.org/manual/nixos/stable/#sec-upgrading for how
  # to actually do that.
  #
  # This value being lower than the current NixOS release does NOT mean your system is
  # out of date, out of support, or vulnerable.
  #
  # Do NOT change this value unless you have manually inspected all the changes it would make to your configuration,
  # and migrated your data accordingly.
  #
  # For more information, see `man configuration.nix` or https://nixos.org/manual/nixos/stable/options#opt-system.stateVersion .
  system.stateVersion = "25.11"; # Did you read the comment?

}
