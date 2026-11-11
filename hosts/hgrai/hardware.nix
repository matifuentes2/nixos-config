{ modulesPath, ... }:

{
  imports = [ (modulesPath + "/profiles/qemu-guest.nix") ];
  boot.initrd.availableKernelModules = [
    "virtio_pci"
    "virtio_scsi"
    "virtio_blk"
    "xhci_pci"
    "sr_mod"
  ];
  boot.kernelParams = [
    "console=ttyAMA0,115200n8"
    "console=tty0"
    "net.ifnames=0"
  ];
  nixpkgs.hostPlatform = "aarch64-linux";
}
