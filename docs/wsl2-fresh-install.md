# Fresh installation on WSL2

This guide installs the repository's `wsl2` flake output on an x86-64 Windows
Subsystem for Linux 2 instance. It uses the upstream NixOS-WSL image and Home
Manager for user `matif`. The Raspberry Pi boot and Hyprland modules are not
part of this host.

The configuration expects the repository at `~/nixos-config` after the first
activation. If the Linux username should not be `matif`, change `wslUsername`
in [`../flake.nix`](../flake.nix) before activating and substitute that name in
the commands below.

## 1. Install or update WSL2

Open an elevated PowerShell. If WSL is not installed yet, enable it without
installing a distribution, then restart Windows if prompted:

```powershell
wsl --install --no-distribution
```

Install the current Store-delivered WSL and confirm its version:

```powershell
wsl --update
wsl --version
```

NixOS-WSL supports Windows 10 and Windows 11, and recommends the Store version
of WSL2.

## 2. Install the upstream NixOS-WSL image

Download `nixos.wsl` from the
[latest NixOS-WSL release](https://github.com/nix-community/NixOS-WSL/releases/latest).
The commands below assume the browser saved it in the default Downloads
folder; adjust `$nixosImage` if it was saved elsewhere. With WSL 2.4.4 or newer,
install the downloaded file from PowerShell:

```powershell
$nixosImage = "$env:USERPROFILE\Downloads\nixos.wsl"
wsl --install --from-file $nixosImage --name NixOS
wsl -d NixOS
```

For WSL older than 2.4.4, import the same file explicitly instead:

```powershell
$nixosImage = "$env:USERPROFILE\Downloads\nixos.wsl"
wsl --import NixOS "$env:USERPROFILE\NixOS" $nixosImage --version 2
wsl -d NixOS
```

The initial NixOS-WSL account is named `nixos`. The repository changes the
default account during the first activation, so do not create unrelated state
under that temporary home directory.

## 3. Clone and validate the configuration

In the NixOS shell, initialize the stock channel once and use a temporary Git
shell to clone the repository:

```sh
sudo nix-channel --update
nix-shell -p git

git clone https://github.com/matifuentes2/nixos-config.git ~/nixos-config
exit
cd ~/nixos-config
```

The temporary `nix-shell` is only bootstrap tooling. Git and the lasting system
configuration are declared by the locked flake.

Evaluate the complete flake and build the WSL2 system before selecting it as the
next boot generation:

```sh
nix --extra-experimental-features "nix-command flakes" flake check
sudo nixos-rebuild build \
  --flake "$HOME/nixos-config#wsl2" \
  --option experimental-features "nix-command flakes"
sudo nixos-rebuild boot \
  --flake "$HOME/nixos-config#wsl2" \
  --option experimental-features "nix-command flakes"
```

Use `boot`, not `switch`, for this first activation because it changes the WSL
default username. This is the migration sequence required by NixOS-WSL.

Exit NixOS, then return to PowerShell:

```sh
exit
```

## 4. Apply the new user and move the checkout

Terminate the distribution and start it once as root. Starting this shell
activates the selected generation and creates `/home/matif`:

```powershell
wsl --terminate NixOS
wsl -d NixOS --user root
```

In the root shell, move the checkout out of the temporary `nixos` home and give
it to the configured user:

```sh
mkdir -p /home/matif
mv /home/nixos/nixos-config /home/matif/nixos-config
chown -R matif:users /home/matif/nixos-config
exit
```

Back in PowerShell, terminate the distribution once more and open it normally:

```powershell
wsl --terminate NixOS
wsl -d NixOS
```

Confirm that the configured account and declarative tools are active:

```sh
whoami
nix --version
home-manager --version
```

`whoami` should print `matif`. Set an account password with `passwd` if desired;
NixOS-WSL permits the default wheel user to use `sudo` without a password unless
the configuration is changed to require one.

## Subsequent updates

Pull reviewed changes, perform a non-switching build, and then activate them:

```sh
cd ~/nixos-config
git pull --ff-only
sudo nixos-rebuild build --flake ~/nixos-config#wsl2
sudo nixos-rebuild switch --flake ~/nixos-config#wsl2
```

When a later change modifies `wsl.defaultUser`, follow the same `boot`,
terminate, root-start, and terminate sequence rather than switching directly.
Windows owns the WSL2 kernel; the flake reproducibly manages the NixOS userland,
services, packages, Home Manager configuration, and Windows interoperability.
