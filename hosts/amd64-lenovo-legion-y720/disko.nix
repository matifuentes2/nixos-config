{ ... }:

{
  # This layout owns both internal disks. The confirmed targets use
  # non-identifying kernel paths so this public repository does not disclose
  # serial-number-bearing /dev/disk/by-id paths.
  disko.devices.disk.system = {
    type = "disk";
    device = "/dev/nvme0n1";
    content = {
      type = "gpt";
      partitions = {
        ESP = {
          priority = 1;
          start = "1M";
          size = "1G";
          type = "EF00";
          content = {
            type = "filesystem";
            format = "vfat";
            mountpoint = "/boot";
            mountOptions = [ "umask=0077" ];
          };
        };

        encrypted-root = {
          size = "100%";
          content = {
            type = "luks";
            name = "crypted-root";
            # Permit the periodic fstrim service to reach the NVMe SSD. This
            # leaks which physical blocks are unused but not their contents.
            settings.allowDiscards = true;
            # With no key file configured, Disko asks for the passphrase
            # interactively and the initrd asks for it on every boot.
            content = {
              type = "btrfs";
              extraArgs = [ "-f" ];
              subvolumes = {
                "/root" = {
                  mountpoint = "/";
                  mountOptions = [
                    "compress=zstd"
                    "noatime"
                  ];
                };
                "/home" = {
                  mountpoint = "/home";
                  mountOptions = [
                    "compress=zstd"
                    "noatime"
                  ];
                };
                "/nix" = {
                  mountpoint = "/nix";
                  mountOptions = [
                    "compress=zstd"
                    "noatime"
                  ];
                };
              };
            };
          };
        };
      };
    };
  };

  disko.devices.disk.data = {
    type = "disk";
    device = "/dev/sda";
    content = {
      type = "gpt";
      partitions = {
        encrypted-data = {
          size = "100%";
          content = {
            type = "luks";
            name = "crypted-data";
            content = {
              type = "btrfs";
              extraArgs = [ "-f" ];
              subvolumes = {
                "/data" = {
                  mountpoint = "/data";
                  mountOptions = [
                    "compress=zstd"
                    "noatime"
                  ];
                };
              };
            };
          };
        };
      };
    };
  };
}
