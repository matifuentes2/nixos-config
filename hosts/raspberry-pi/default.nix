# Raspberry Pi-specific NixOS configuration. Help is available in the
# configuration.nix(5) man page and on
# https://search.nixos.org/options and in the NixOS manual (`nixos-help`).

{ pkgs, ... }:

{
  imports = [
    ../../modules/system/common.nix
    ../../modules/system/linux-desktop.nix
    ./hardware-configuration.nix
  ];

  # Keep local builds from consuming every core while the desktop and remote
  # services are in use. These are defaults; callers can override them explicitly.
  nix.settings = {
    max-jobs = 1;
    cores = 1;
  };

  # Run the Docker daemon with automatic weekly pruning of unused data.
  # Membership in the docker group below is root-equivalent.
  virtualisation.docker = {
    enable = true;
    autoPrune.enable = true;
  };

  # Let uv and T3's standalone Node executable/add-ons run unmodified.
  # Patching T3's ELF would corrupt its appended JavaScript payload.
  programs.nix-ld.enable = true;
  programs.nix-ld.libraries = [
    pkgs.libsecret
    pkgs.libffi
  ];

  # Use the extlinux boot loader. (NixOS wants to enable GRUB by default)
  boot.loader.grub.enable = false;
  # Enables the generation of /boot/extlinux/extlinux.conf
  boot.loader.generic-extlinux-compatible.enable = true;

  # Linux 6.18 repeatedly wedged the Pi 4's MMC worker in mmc_rescan.
  boot.kernelPackages = pkgs.linuxPackages_6_12;

  # The generic device tree reserves only 64 MiB for contiguous DMA buffers.
  # Give the VC4 display pipeline room for the greeter, compositor and clients,
  # keeping the pool in the low memory range accessible to the display engine.
  boot.kernelParams = [ "cma=256M@0-1G" ];

  # Avoid the greeter's failing GPU buffer-import path. Hyprland still uses V3D
  # acceleration once logged in; only the login screen uses software rendering.
  services.displayManager.sddm = {
    wayland.compositorCommand = "${pkgs.weston}/bin/weston --shell=kiosk --renderer=pixman --no-config";
    settings.General.GreeterEnvironment = "QT_QUICK_BACKEND=software";
  };

  # Absorb transient agent memory spikes instead of invoking the OOM killer.
  zramSwap = {
    enable = true;
    memoryPercent = 50;
  };

  # Keep background store maintenance below interactive and server workloads.
  systemd.services.nix-gc.serviceConfig = {
    Nice = 19;
    IOSchedulingClass = "idle";
  };

  # networking.hostName = "nixos"; # Define your hostname.

  # Configure network connections interactively with nmcli or nmtui.
  networking.networkmanager.enable = true;

  # The time zone is pinned for all NixOS hosts in modules/system/common.nix.

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
    # Keep remote user services available independently of logins.
    linger = true;
    description = "Pi user";
    # Allow sudo, Docker, and access to networking, graphics, and audio devices.
    extraGroups = [
      "wheel"
      "networkmanager"
      "video"
      "audio"
      "docker"
    ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAt+/czluQsmX++mLb+H96Zy5SKcU7uzRikipfvG1FSn"
    ];
  };

  programs.firefox.enable = true;

  # T3 Code uses libsecret; unlock the encrypted login keyring through PAM.
  services.gnome.gnome-keyring.enable = true;
  security.pam.services.sddm.enableGnomeKeyring = true;

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
