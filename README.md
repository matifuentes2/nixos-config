# Shared NixOS, WSL2, and macOS configuration

This repository is the declarative source of truth for:

- the `nixos` flake output: a 64-bit Raspberry Pi 4 running NixOS, with Home
  Manager for user `pi`;
- the `amd64-lenovo-legion-y720` flake output: an x86-64 physical NixOS laptop
  with encrypted Btrfs storage, Hyprland, and Home Manager for user `matif`;
- the `wsl2` flake output: an x86-64 NixOS-WSL environment running under WSL2,
  with Home Manager for user `matif`; and
- the `macbook` flake output: an Apple Silicon Mac managed by nix-darwin, with
  Home Manager for user `matif`.

Shared command-line packages, Pi/Herdr configuration, shell tools, Starship,
and Neovim live in [`modules/home/common.nix`](./modules/home/common.nix).
Linux desktop and macOS-only Home Manager settings are kept in
[`modules/home/linux.nix`](./modules/home/linux.nix) and
[`modules/home/darwin.nix`](./modules/home/darwin.nix). Shared NixOS desktop
services live in [`modules/system/linux-desktop.nix`](./modules/system/linux-desktop.nix).
WSL2 intentionally skips
the Hyprland-oriented Linux desktop module. Device configuration lives under
[`hosts/`](./hosts/).

## Repository layout

```text
flake.nix
hosts/
  raspberry-pi/
    default.nix
    hardware-configuration.nix
    home.nix
  amd64-lenovo-legion-y720/
    default.nix
    disko.nix
    hardware.nix
    home.nix
  macbook/
    default.nix
    home.nix
  wsl2/
    default.nix
    home.nix
modules/
  home/
    common.nix
    linux.nix
    darwin.nix
  system/common.nix
hyprland/
neovim/
```

Add packages needed on every host to `modules/home/common.nix`. Add host-only
user packages to the corresponding `hosts/<host>/home.nix`. Machine
services, hardware settings, and operating-system packages belong in the
host's `default.nix` or an imported platform-specific module.

## Raspberry Pi

For a new Raspberry Pi 4, follow the
[fresh-installation guide](./docs/fresh-install.md). Rebuild an existing host
with:

```sh
sudo nixos-rebuild switch --flake /etc/nixos#nixos
```

Hyprland is configured under [`hyprland/`](./hyprland/) and starts from SDDM.
See the [Hyprland desktop guide](./docs/hyprland.md) for its keybindings.

## Lenovo Legion Y720

The `amd64-lenovo-legion-y720` output installs the physical x86-64 laptop with
the encrypted NVMe system drive at `/`, `/home`, and `/nix`, plus the encrypted
SATA bulk-storage drive at `/data`. The declarative Disko layout is documented
in the
[fresh-installation guide](./docs/amd64-lenovo-legion-y720-fresh-install.md).
The Disko procedure owns and erases both internal drives.

Build the installed host without switching:

```sh
sudo nixos-rebuild build --flake /etc/nixos#amd64-lenovo-legion-y720
```

## WSL2

The `wsl2` output uses the upstream NixOS-WSL module and shares the portable
Home Manager configuration without installing the Raspberry Pi's boot or
Hyprland desktop settings. Follow the
[fresh WSL2 installation guide](./docs/wsl2-fresh-install.md) for a new Windows
host.

Rebuild an existing WSL2 host with:

```sh
sudo nixos-rebuild switch --flake ~/nixos-config#wsl2
```

## macOS

A new Apple Silicon Mac with the short account name `matif` can be bootstrapped
from the stock Terminal without separately installing Nix, Git, the Xcode
Command Line Tools, Homebrew, or nix-darwin. Follow the
[fresh macOS installation guide](./docs/macos-fresh-install.md).

The documented procedure downloads a checksum-verified immutable release and
requires the bootstrap script to fetch and activate that release's full Git
commit. Nix, Git, Homebrew, its taps, Home Manager, and nix-darwin are obtained
from versioned or flake-locked sources.

After installation, rebuild with:

```sh
sudo darwin-rebuild switch --flake ~/nixos-config#macbook
```

## Validation and pinned dependencies

```sh
nix flake check
```

Build the Raspberry Pi configuration without switching:

```sh
sudo nixos-rebuild build --flake /etc/nixos#nixos
```

Build the physical amd64 configuration on an x86-64 Linux host without
switching:

```sh
nix build --no-link .#nixosConfigurations.amd64-lenovo-legion-y720.config.system.build.toplevel
```

Build the WSL2 configuration on an x86-64 Linux host without switching:

```sh
nix build --no-link .#nixosConfigurations.wsl2.config.system.build.toplevel
```

Build the Darwin configuration on the Mac:

```sh
darwin-rebuild build --flake ~/nixos-config#macbook
```

A Linux host cannot build a Darwin activation package without a Darwin remote
builder, and a Mac needs a Linux builder for the WSL2 activation package.
`flake.lock` pins nixpkgs, NixOS-WSL, nix-darwin, Home Manager, and the other
flake inputs.

Run the public-repository safety checks with:

```sh
nix shell .#ci-tools -c bash scripts/check-public-repo.sh
```

See the [public repository and bootstrap security policy](./docs/public-repository-security.md)
for the release procedure, trust boundaries, automated checks, and secret
rotation requirements. The current immutable release metadata lives in
[`bootstrap-release.env`](./bootstrap-release.env); tracked scripts validate
that metadata, audit GitHub controls, and create the next release reproducibly.

Neovim is configured under [`neovim/`](./neovim/); its plugins, parsers,
language servers, formatters, and debug adapters are supplied by Nix rather
than downloaded at runtime.
