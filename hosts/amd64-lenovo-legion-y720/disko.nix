{ ... }:

{
  # This layout owns the complete internal disk. The confirmed target uses the
  # non-identifying kernel path /dev/sda so this public repository does not
  # disclose a serial-number-bearing /dev/disk/by-id path.
  disko.devices.disk.main = {
    type = "disk";
    device = "/dev/sda";
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
}
