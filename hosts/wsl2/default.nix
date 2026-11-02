{
  config,
  pkgs,
  username,
  ...
}:

{
  imports = [
    ../../modules/system/common.nix
    ../../modules/system/claude-code.nix
  ];

  networking.hostName = "wsl2";

  # The headless T3 Code server (a Home Manager user service) is reachable
  # through the Windows-to-WSL port forward.
  networking.firewall.allowedTCPPorts = [ 3773 ];

  # Start the user's systemd services, including the T3 Code server, when WSL
  # boots rather than on the first interactive login.
  users.users.${username}.linger = true;

  # NixOS-WSL supplies the Windows kernel, boot integration, the default user,
  # and Windows executable interoperability.
  wsl = {
    enable = true;
    defaultUser = username;
    # Expose the Windows host's D3D12 user-mode drivers to Mesa so WSLg apps
    # render on the GPU instead of llvmpipe.
    useWindowsDriver = true;
  };

  # Mesa's D3D12 driver must be selected explicitly. It otherwise picks the
  # first adapter, the Kaby Lake iGPU, whose WSL driver fails to initialize,
  # and falls back to software rendering. Pin the working NVIDIA adapter.
  # Mesa's RUNPATH does not include /run/opengl-driver/lib, so its d3d12
  # driver cannot dlopen libd3d12.so unless the Windows driver symlinks are on
  # the library path. Only wsl-lib is added, so applications keep their own
  # Mesa build.
  environment.sessionVariables = {
    GALLIUM_DRIVER = "d3d12";
    MESA_D3D12_DEFAULT_ADAPTER_NAME = "NVIDIA";
    LD_LIBRARY_PATH = [ "${config.wsl.wslLib}/lib" ];
  };

  # Support dynamically linked tools such as the VS Code Remote server.
  programs.nix-ld.enable = true;

  # The T3 Code wrapper uses libsecret for encrypted credential storage.
  services.gnome.gnome-keyring.enable = true;

  # System administration tools belong to the host; user-facing tools are
  # shared through Home Manager.
  environment.systemPackages = with pkgs; [
    vim
    wget
    git
    gh
  ];

  # This is the first NixOS version used for this WSL2 host. Do not change it
  # during normal upgrades; it controls compatibility defaults.
  system.stateVersion = "26.11";
}
