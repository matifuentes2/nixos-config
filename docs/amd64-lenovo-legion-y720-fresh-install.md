# Fresh installation on the Lenovo Legion Y720

This procedure installs the `amd64-lenovo-legion-y720` NixOS flake output on
the physical Lenovo laptop. It uses Disko to configure both internal drives:

- the 953.9 GiB Intel NVMe drive (`/dev/nvme0n1`) contains the EFI System
  Partition and the LUKS-encrypted Btrfs system volumes for `/`, `/home`, and
  `/nix`;
- the 931.5 GiB Western Digital SATA drive (`/dev/sda`) contains a
  LUKS-encrypted Btrfs data volume mounted at `/data`.

> **Destructive operation:** Disko permanently erases both internal drives,
> including every existing operating system, partition, recovery environment,
> and user file. Identify the installer USB by its model and transport and
> never substitute it for either target.

The installation uses UEFI without Secure Boot and compressed zram without
disk-backed hibernation.

## 1. Configure firmware and boot the installer

Keep the firmware storage-controller mode set to **AHCI**, not Intel RST or
RAID. In RST/RAID mode Linux cannot access the remapped NVMe drive.

Boot the graphical NixOS USB through its UEFI boot entry, start the live
desktop, and connect to Wi-Fi or Ethernet. Do not start the graphical installer.
Open a terminal and verify connectivity:

```sh
ping -c 3 github.com
```

Confirm that the session was booted through UEFI:

```sh
test -d /sys/firmware/efi && echo UEFI || echo legacy
```

Stop unless this prints `UEFI`.

## 2. Fetch and inspect the configuration

Clone the reviewed repository revision into the live system:

```sh
git clone https://github.com/matifuentes2/nixos-config /tmp/nixos-config
cd /tmp/nixos-config
```

Review the disk layout before executing it:

```sh
less hosts/amd64-lenovo-legion-y720/disko.nix
```

Confirm the disk identities again:

```sh
lsblk -d -e7 -o NAME,PATH,SIZE,TYPE,MODEL,TRAN
lsblk -e7 -o NAME,PATH,SIZE,TYPE,FSTYPE,MOUNTPOINTS
```

Proceed only when all of the following are true:

- `/dev/nvme0n1` is the 953.9 GiB Intel NVMe drive;
- `/dev/sda` is the 931.5 GiB Western Digital SATA drive;
- neither internal drive has a mounted partition; and
- the installer USB has been identified as a different device by its model and
  `usb` transport.

## 3. Validate the flake

The Disko executable and all configuration inputs come from `flake.lock`. The
live installer does not enable flakes by default, so pass the required
experimental features explicitly:

```sh
nix --extra-experimental-features "nix-command flakes" \
  flake check --no-write-lock-file
nix --extra-experimental-features "nix-command flakes" \
  eval --raw \
  .#nixosConfigurations.amd64-lenovo-legion-y720.config.system.build.toplevel.drvPath
```

Do not continue if either command fails.

## 4. Erase, encrypt, format, and mount both drives

The following command is the destructive boundary. Disko asks interactively
for the encryption passphrase for each LUKS container. Store the passphrases
securely; they cannot be recovered from this repository. Using the same strong
passphrase for both containers may allow the boot-time prompt to reuse it, but
the drives remain independently encrypted.

Run the complete command in an explicit root shell; running only the generated
Disko script as the live user leaves it unable to open the target devices:

```sh
sudo sh -c '
  cd /tmp/nixos-config &&
  nix --extra-experimental-features "nix-command flakes" \
    run .#disko -- \
    --mode destroy,format,mount \
    hosts/amd64-lenovo-legion-y720/disko.nix
'
```

Verify every resulting mount:

```sh
findmnt /mnt
findmnt /mnt/boot
findmnt /mnt/home
findmnt /mnt/nix
findmnt /mnt/data
```

## 5. Preserve the checkout and install NixOS

Copy the exact checkout used for installation onto the new root filesystem:

```sh
sudo mkdir -p /mnt/etc
sudo cp -a /tmp/nixos-config /mnt/etc/nixos
sudo chown -R 1000:100 /mnt/etc/nixos
```

Install the tracked host without creating a root password:

```sh
sudo env NIX_CONFIG="experimental-features = nix-command flakes" \
  nixos-install \
  --no-root-passwd \
  --flake /mnt/etc/nixos#amd64-lenovo-legion-y720
```

Set the local login and `sudo` password for `matif`:

```sh
sudo nixos-enter --root /mnt -c 'passwd matif'
```

This login password is separate from the LUKS disk-encryption passphrases.

## 6. Reboot

Cleanly flush and unmount the installation before restarting:

```sh
sync
sudo umount -R /mnt
sudo cryptsetup close crypted-data
sudo cryptsetup close crypted-root
sudo reboot
```

Remove the USB stick when the firmware begins restarting. If the firmware uses
an obsolete Windows entry on the first boot, press **F12** and select **Linux
Boot Manager**. Enter the LUKS passphrase when prompted, then log in to SDDM as
`matif` using the account password selected above. Use `efibootmgr` after login
to place Linux Boot Manager first in the persistent firmware boot order; run
`sudo efibootmgr` to inspect the firmware-specific boot identifiers.

After login, verify that the system is using both drives as declared:

```sh
findmnt /
findmnt /data
lsblk -e7 -o NAME,PATH,SIZE,TYPE,FSTYPE,MOUNTPOINTS,MODEL,TRAN
```

The Hyprland session uses Intel HD Graphics 630 by default. Run individual
programs on the NVIDIA GTX 1060 Mobile with:

```sh
nvidia-offload PROGRAM
```

OpenSSH accepts the ED25519 public key tracked in the host configuration, which
is a reproducible snapshot of the key published at
<https://github.com/matifuentes2.keys>. Password-based SSH login remains
disabled. Connect from the machine holding the corresponding private key:

```sh
ssh matif@AMD64_HOST_ADDRESS
```

## Subsequent updates

The persistent checkout is `/etc/nixos`. Pull reviewed changes, build without
switching, and then activate them:

```sh
cd /etc/nixos
git pull --ff-only
sudo nixos-rebuild build --flake /etc/nixos#amd64-lenovo-legion-y720
sudo nixos-rebuild switch --flake /etc/nixos#amd64-lenovo-legion-y720
```

Do not rerun Disko for ordinary updates. Its destructive modes are only for a
fresh disk installation or an intentional complete reinstall.
