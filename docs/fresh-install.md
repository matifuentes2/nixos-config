# Fresh installation on the Raspberry Pi 4

This guide installs the repository's `nixos` flake output on a 64-bit
Raspberry Pi 4. The repository also contains a separate nix-darwin `macbook`
output; none of the macOS modules are applied by this procedure. The Pi expects
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

## 4. Run the bootstrap script

The encrypted system secrets require the age identity stored in Bitwarden.
Before starting, make sure the private identity is the complete contents of a
secure note named `NixOS SOPS age identity` and that you have the account's
master password and Authenticator app available.

The following commands resolve `main` once to a full Git commit, download an
archive for that immutable revision, and run the script from the same archive:

```sh
(
set -eu
repository="matifuentes2/nixos-config"
revision=$(curl --proto '=https' --tlsv1.2 -fsSL \
  "https://api.github.com/repos/$repository/commits/main" \
  | awk -F '"' '/^[[:space:]]*"sha":/ { print $4; exit }')
[ "${#revision}" -eq 40 ]
case "$revision" in *[!0-9a-f]*) exit 1 ;; esac

bootstrap_directory=$(mktemp -d)
trap 'rm -rf "$bootstrap_directory"' EXIT
curl --proto '=https' --tlsv1.2 -fsSL \
  "https://github.com/$repository/archive/$revision.tar.gz" \
  -o "$bootstrap_directory/source.tar.gz"
tar -xzf "$bootstrap_directory/source.tar.gz" -C "$bootstrap_directory"
source_directory=$(find "$bootstrap_directory" -mindepth 1 -maxdepth 1 -type d -print -quit)
[ -n "$source_directory" ]

sudo env \
  NIXOS_CONFIG_REVISION="$revision" \
  NIXOS_CONFIG_SOURCE_DIRECTORY="$source_directory" \
  bash "$source_directory/scripts/bootstrap.sh"
)
```

To install a previously reviewed release instead of the current `main`
snapshot, replace the `revision=$(...)` command with its full 40-character
commit. The archive and the commit fetched by Git are then tied to the same
immutable identifier.

The script uses the flake-pinned Bitwarden CLI to log in interactively with
Authenticator method `0`, retrieve the secure note, verify that its public
recipient matches `.sops.yaml`, and install it as root-only
`/var/lib/sops-nix/key.txt`. This explicitly selects an Authenticator app code;
the CLI does not use the account's passkey. Its temporary Bitwarden state and
downloaded note are removed before the script exits. A rerun uses an
already-installed matching identity without logging in again.

To use a differently named secure note, replace the final `sudo env` command
inside the installation block with:

```sh
sudo env \
  NIXOS_CONFIG_REVISION="$revision" \
  NIXOS_CONFIG_SOURCE_DIRECTORY="$source_directory" \
  BITWARDEN_ITEM_NAME="My NixOS age identity" \
  bash "$source_directory/scripts/bootstrap.sh"
```

The script deliberately stops unless it detects all of the following:

- an ARM64 system;
- a Raspberry Pi 4;
- the root filesystem UUID used by the official NixOS SD image; and
- a full, immutable configuration commit.

It then:

1. obtains Git from the archive's locked nixpkgs input if Git is unavailable;
2. fetches and cryptographically verifies the selected commit in a temporary
   worktree;
3. retrieves and validates the SOPS age identity when it is not already
   installed;
4. runs `nix flake check`;
5. places the checkout at `/etc/nixos` and applies `/etc/nixos#nixos` with
   `nixos-rebuild switch`; and
6. asks for a local login and `sudo` password for user `pi`.

Any configuration originally at `/etc/nixos` is retained in a timestamped
`/etc/nixos.backup-*` directory.

The procedure downloads the complete source before executing it. To inspect it
before the final `sudo` command, use:

```sh
less "$source_directory/scripts/bootstrap.sh"
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

Do not rerun an older bootstrap revision as an update: it deliberately installs
that exact revision and may replace a newer checkout after retaining it as a
backup.
