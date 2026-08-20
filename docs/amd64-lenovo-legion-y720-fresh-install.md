# Fresh installation on the Lenovo Legion Y720

This procedure installs the `amd64-lenovo-legion-y720` NixOS flake output on
the physical Lenovo laptop. It uses Disko to replace the complete internal
Western Digital disk with an encrypted Btrfs installation.

> **Destructive operation:** the confirmed target is `/dev/sda`, a 931.5 GiB
> internal SATA disk. The Disko step permanently removes its existing NTFS
> partition, Windows installation, recovery data, and every other file. The
> installer USB observed during preparation is `/dev/sdb`; never substitute it
> as the target.

The initial installation uses UEFI without Secure Boot and compressed zram
without disk-backed hibernation.

## 1. Boot and connect

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

Clone the public repository into the live system:

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
lsblk -e7 -o NAME,PATH,SIZE,TYPE,FSTYPE,MOUNTPOINTS,MODEL,TRAN
```

Proceed only when `/dev/sda` is the 931.5 GiB internal Western Digital SATA
disk and `/dev/sdb` is the USB installer.

## 3. Validate the flake

The Disko executable and all configuration inputs come from `flake.lock`:

The live installer does not enable flakes by default, so pass the required
experimental features explicitly:

```sh
nix --extra-experimental-features "nix-command flakes" \
  flake check --no-write-lock-file
nix --extra-experimental-features "nix-command flakes" \
  eval --raw \
  .#nixosConfigurations.amd64-lenovo-legion-y720.config.system.build.toplevel.drvPath
```

Do not continue if either command fails.

## 4. Erase, encrypt, format, and mount the disk

The following command is the destructive boundary. It erases `/dev/sda`,
creates a GPT partition table and 1 GiB EFI System Partition, and places Btrfs
inside a LUKS-encrypted partition. Disko asks for the new disk-encryption
passphrase interactively. Store that passphrase securely; the machine asks for
it during every boot and it cannot be recovered from this repository.

Run the complete command in an explicit root shell; running only the generated
Disko script as the live user leaves it unable to open the target device:

```sh
sudo sh -c '
  cd /tmp/nixos-config &&
  nix --extra-experimental-features "nix-command flakes" \
    run .#disko -- \
    --mode destroy,format,mount \
    hosts/amd64-lenovo-legion-y720/disko.nix
'
```

Verify the resulting mounts:

```sh
findmnt /mnt
findmnt /mnt/boot
findmnt /mnt/home
findmnt /mnt/nix
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

This login password is separate from the LUKS disk-encryption passphrase.

## 6. Reboot

Cleanly flush and unmount the installation before restarting:

```sh
sync
sudo umount -R /mnt
sudo cryptsetup close crypted-root
sudo reboot
```

Remove the USB stick when the firmware begins restarting. If the firmware uses
an obsolete Windows entry on the first boot, press **F12** and select **Linux
Boot Manager**. Enter the LUKS passphrase when prompted, then log in to SDDM as
`matif` using the account password selected above. Use `efibootmgr` after login
to place Linux Boot Manager first in the persistent firmware boot order; run
`sudo efibootmgr` to inspect the firmware-specific boot identifiers.

The Hyprland session uses Intel HD Graphics 630 by default. Run individual
programs on the NVIDIA GTX 1060 Mobile with:

```sh
nvidia-offload PROGRAM
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
