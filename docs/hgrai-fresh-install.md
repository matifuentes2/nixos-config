# hgrai cloud server

This host is an ARM64 Hetzner Cloud VM. Its flake output is
`nixosConfigurations.hgrai`, with a headless operating system and a `matif`
administrator account. The pinned SSH public key permits login as `matif` or
root; password authentication is disabled. The wheel group has passwordless
sudo so remote administration does not depend on a local password.

## Installation

Installation destroys the entire `/dev/sda` disk, including previous operating
systems and Docker data. Confirm the target with `lsblk` before proceeding.
The Disko layout creates a 1 GiB EFI partition and an ext4 root filesystem.

Before installation, verify Hetzner console/rescue access and that the matching
SSH private key works. The installation needs root SSH or passwordless sudo.
The target must support aarch64 kexec, or already run an ARM64 NixOS installer.
Use the public IP for installation; Tailscale alone does not survive kexec.

Build the system on an ARM64 Linux builder before formatting the disk:

```sh
nix build --no-link .#nixosConfigurations.hgrai.config.system.build.toplevel
```

Run a reviewed, pinned nixos-anywhere revision from an administrator workstation:

```sh
nix run github:nix-community/nixos-anywhere/58132e1d1f813b845382a2aeca4203b18d2ac807 -- \
  --flake .#hgrai --target-host root@<server-public-ip> \
  --build-on remote --copy-host-keys -i ~/.ssh/id_ed25519
```

`--copy-host-keys` preserves the server's SSH identity. To preserve Tailscale
membership, securely copy `/var/lib/tailscale` using `--extra-files` and remove
the temporary local copy after verification. Never commit it or place it in the
Nix store. Otherwise enroll this host with `sudo tailscale up` after boot.

IPv4 uses DHCP, including Hetzner's /32 routing. IPv6 is explicitly configured
for this VM. `net.ifnames=0` keeps the public interface named `eth0`.
A cloned VM must have its IPv6 configuration changed before booting.

## Administration and acceptance

Configure the workstation's SSH alias to use the server's public address,
`User matif`, and the matching identity file. Keep the old alias configuration
until a direct `ssh matif@<server-public-ip>` connection succeeds.

Keep a tracked repository checkout at `/etc/nixos` and rebuild with:

```sh
sudo git -C /etc/nixos pull --ff-only
sudo nixos-rebuild switch --flake /etc/nixos#hgrai
```

Verify `ssh hgrai`, `sudo -n true`, IPv4/IPv6 routes, DNS, Tailscale, systemd
service health, and bootloader entries. Reboot once more and repeat SSH/sudo
checks before accepting the installation. Docker and previous application
services are intentionally absent.

If SSH is unavailable, use Hetzner's console or enable its ARM64 rescue system
with the administrator's SSH public key. Repair the network or bootloader from
rescue; reinstall from the same flake if needed. NixOS generation rollback
applies to later NixOS updates, not recovery of the previous Ubuntu installation.
