# Fresh installation on the Raspberry Pi 4

This guide installs the repository's `nixos` flake output on a 64-bit
Raspberry Pi 4. The repository also contains separate NixOS-WSL `wsl2` and
nix-darwin `macbook` outputs; none of their host modules are applied by this
procedure. The Pi expects
the partition layout from the official generic AArch64 NixOS SD-card image:

- a small `FIRMWARE` partition containing the Raspberry Pi boot files;
- an ext4 `NIXOS_SD` root partition; and
- root filesystem UUID `44444444-4444-4444-8888-888888888888`.

Do not use a PC-oriented NixOS ISO, manually repartition the card, or run
`nixos-install`. The official SD image is already an installed, mutable NixOS
system. After booting it, the bootstrap script replaces its configuration and
runs `nixos-rebuild`.

> These instructions are specific to the Raspberry Pi 4. Do not apply the
> `nixos` output to another computer; each device needs its own host and
> hardware configuration under `hosts/`.

## 1. Download the NixOS SD image

On another computer, open the NixOS Wiki's
[ARM installation page](https://wiki.nixos.org/wiki/NixOS_on_ARM/Installation#SD_card_images_(SBCs_and_similar_platforms))
and download the latest successful **AArch64 SD image** build. The downloaded
file normally ends in `.img.zst`.

The Raspberry Pi 4 uses the generic image; it does not use the AArch64 ISO.

## 2. Flash the microSD card

Writing an image destroys everything currently on the selected card. Identify
the card carefully:

```sh
lsblk
```

Decompress the image and write it to the **whole card**, not to a partition.
Replace the image name and `/dev/sdX` with the correct paths:

```sh
unzstd nixos-sd-image-aarch64-linux.img.zst
sudo dd \
  if=nixos-sd-image-aarch64-linux.img \
  of=/dev/sdX \
  bs=4M \
  status=progress \
  conv=fsync
sync
```

For example, use `/dev/sdX`, not `/dev/sdX1`. Device names vary between
computers; do not copy a device name without checking it first. A graphical
image-writing tool that supports `.img.zst` files is also suitable.

Insert the card into the Raspberry Pi after the write completes.

## 3. Boot and connect to the network

Connect a monitor and keyboard and, for the simplest initial setup, connect
Ethernet. Boot the Pi and use the console provided by the stock NixOS image.
The image normally logs in to its installation account automatically and
allows that account to use `sudo` without a password.

Confirm that the network can reach GitHub:

```sh
ping -c 3 github.com
```

If Ethernet is unavailable, use NetworkManager's text interface to configure
Wi-Fi:

```sh
sudo nmtui
```

## 4. Run the bootstrap

The encrypted system secrets require the age identity stored in Bitwarden.
Before starting, make sure the private identity is the complete contents of a
secure note named `NixOS SOPS age identity` and that you have the account's
master password and Authenticator app available.

On the Pi's console, type this single command:

```sh
sudo nix --extra-experimental-features 'nix-command flakes' run github:matifuentes2/nixos-config
```

Nix downloads the current `main` branch and runs its bootstrap app. The app
brings its own Git, Bitwarden CLI, and age, so nothing else needs installing
first. It:

1. refuses to run unless this is a Raspberry Pi 4 booted from the official
   NixOS SD image;
2. clones the repository at the same commit that was just run;
3. logs in to Bitwarden in the terminal (Authenticator method `0`), retrieves
   the secure note, checks it against the recipient in `.sops.yaml`, and
   installs it as root-only `/var/lib/sops-nix/key.txt` (skipped on a rerun if
   a matching identity is already installed);
4. moves any existing `/etc/nixos` to `/etc/nixos.backup-*`, places the
   checkout at `/etc/nixos`, and runs `nixos-rebuild switch`; and
5. asks for a local login and `sudo` password for user `pi`.

The first rebuild downloads and builds a lot; expect it to take a while.

To use a differently named secure note, prefix the command with the variable:

```sh
sudo BITWARDEN_ITEM_NAME="My NixOS age identity" \
  nix --extra-experimental-features 'nix-command flakes' run github:matifuentes2/nixos-config
```

## 5. Reboot and connect

After bootstrap completes, reboot:

```sh
sudo reboot
```

The configuration starts SDDM and Hyprland. Log in locally as `pi` with the
password selected during bootstrap.

OpenSSH accepts the public key declared in
`hosts/raspberry-pi/default.nix`; SSH password login remains disabled. From a
computer holding the corresponding private key, connect with:

```sh
ssh pi@RASPBERRY_PI_ADDRESS
```

The authorized ED25519 key has this fingerprint:

```text
SHA256:PthH+8gCQ9QJMelH0BmgL6gYECOkPNaZYVscMvtESRw
```

A public key and its fingerprint are safe to commit, but publishing a reused
key can correlate identities across services. This key should be dedicated to
this host. Never copy the corresponding private key into this repository or
onto an untrusted system.

## Subsequent updates

The permanent checkout is `/etc/nixos`. Pull reviewed changes and rebuild with:

```sh
cd /etc/nixos
git pull --ff-only
sudo nixos-rebuild switch --flake /etc/nixos#nixos
```

Before switching larger changes, perform a non-switching build:

```sh
sudo nixos-rebuild build --flake /etc/nixos#nixos
```

Do not rerun the bootstrap as an update: it replaces `/etc/nixos` with a fresh
clone (keeping the old one as a backup). Use the commands above instead.
