{
  config,
  lib,
  pkgs,
  username,
  ...
}:

let
  nvidiaOffloadEnv = {
    __GLX_VENDOR_LIBRARY_NAME = "nvidia";
    __NV_PRIME_RENDER_OFFLOAD = "1";
    __NV_PRIME_RENDER_OFFLOAD_PROVIDER = "NVIDIA-G0";
    __VK_LAYER_NV_optimus = "NVIDIA_only";
  };

  lutrisNvidia = pkgs.symlinkJoin {
    name = "lutris-nvidia";
    paths = [ pkgs.lutris ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      wrapProgram "$out/bin/lutris" \
        ${lib.concatStringsSep " \\\n        " (
          lib.mapAttrsToList (name: value: "--set ${name} ${lib.escapeShellArg value}") nvidiaOffloadEnv
        )}
    '';
  };
in
{
  imports = [
    ../../modules/system/common.nix
    ../../modules/system/linux-desktop.nix
    ./disko.nix
    ./hardware.nix
  ];

  networking = {
    hostName = "amd64-lenovo-legion-y720";
    networkmanager.enable = true;
  };

  boot.loader = {
    systemd-boot.enable = true;
    efi.canTouchEfiVariables = true;
  };

  # Let tools such as uv run upstream dynamically linked binaries.
  programs.nix-ld.enable = true;

  # Keep Steam and Lutris out of the default desktop. Opt in from a running system with:
  # sudo /run/current-system/specialisation/steam/bin/switch-to-configuration switch
  # The Steam specialisation is also available from the systemd-boot menu. Steam,
  # Lutris, and the games they launch inherit PRIME offload variables for the NVIDIA GPU.
  specialisation.steam.configuration = {
    programs.steam = {
      enable = true;
      package = pkgs.steam.override {
        extraEnv = nvidiaOffloadEnv;
      };
    };

    environment.systemPackages = [ lutrisNvidia ];
  };

  # The GTX 1060 Mobile is a Pascal GPU and therefore uses NVIDIA's closed
  # kernel module. PRIME offload keeps the Intel GPU as the desktop default.
  nixpkgs.config.allowUnfree = true;
  services.xserver.videoDrivers = [ "nvidia" ];
  hardware = {
    bluetooth = {
      enable = true;
      powerOnBoot = true;
    };
    graphics.enable = true;
    nvidia = {
      # The current stable branch no longer supports Pascal GPUs. Keep this
      # GTX 1060 Mobile on NVIDIA's final Maxwell/Pascal/Volta branch.
      package = config.boot.kernelPackages.nvidiaPackages.legacy_580;
      modesetting.enable = true;
      open = false;
      nvidiaSettings = true;
      powerManagement.enable = true;
      prime = {
        intelBusId = "PCI:0:2:0";
        nvidiaBusId = "PCI:1:0:0";
        offload = {
          enable = true;
          enableOffloadCmd = true;
        };
      };
    };
  };

  users.users.${username} = {
    isNormalUser = true;
    uid = 1000;
    description = "NixOS user";
    extraGroups = [
      "wheel"
      "networkmanager"
      "video"
      "audio"
    ];
    # Pin the public key currently published by the user's GitHub account.
    # Keeping the key here avoids a network dependency during SSH login.
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAt+/czluQsmX++mLb+H96Zy5SKcU7uzRikipfvG1FSn"
    ];
  };

  environment.systemPackages = with pkgs; [
    efibootmgr
    firefox
    gh
    git
    vim
    wget
  ];

  # Use PipeWire for desktop audio with ALSA and PulseAudio compatibility.
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa = {
      enable = true;
      support32Bit = true;
    };
    pulse.enable = true;
  };

  # Use compressed RAM-backed swap. Disk-backed swap and hibernation are
  # intentionally omitted from the initial installation.
  zramSwap.enable = true;

  # Scrub each distinct Btrfs filesystem monthly for checksum and device
  # errors. Do not list /home and /nix because they share the root filesystem.
  services.btrfs.autoScrub = {
    enable = true;
    fileSystems = [
      "/"
      "/data"
    ];
  };

  services.blueman.enable = true;

  services.tailscale = {
    enable = true;
    openFirewall = true;
    extraSetFlags = [ "--operator=${username}" ];
  };

  services.openssh = {
    enable = true;
    openFirewall = true;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
    };
  };

  programs.mosh = {
    enable = true;
    openFirewall = true;
  };

  # Keep this at the first NixOS version installed on this machine.
  system.stateVersion = "26.11";
}
