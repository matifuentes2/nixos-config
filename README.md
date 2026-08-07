# Shared NixOS and macOS configuration

This repository is the declarative source of truth for:

- the `nixos` flake output: a 64-bit Raspberry Pi 4 running NixOS, with Home
  Manager for user `pi`; and
- the `macbook` flake output: an Apple Silicon Mac managed by nix-darwin, with
  Home Manager for user `matif`.

Shared command-line packages, Pi/Herdr configuration, shell tools, Starship,
and Neovim live in [`modules/home/common.nix`](./modules/home/common.nix).
Linux-only and macOS-only Home Manager settings are kept in
[`modules/home/linux.nix`](./modules/home/linux.nix) and
[`modules/home/darwin.nix`](./modules/home/darwin.nix). Device configuration
lives under [`hosts/`](./hosts/).

## Repository layout

```text
flake.nix
hosts/
  raspberry-pi/
    default.nix
    hardware-configuration.nix
    home.nix
  macbook/
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

Add packages needed on both machines to `modules/home/common.nix`. Add
host-only user packages to the corresponding `hosts/<host>/home.nix`. Machine
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

## macOS

A new Apple Silicon Mac with the short account name `matif` can be bootstrapped
from the stock Terminal without separately installing Nix, Git, the Xcode
Command Line Tools, Homebrew, or nix-darwin. Follow the
[fresh macOS installation guide](./docs/macos-fresh-install.md).

The documented procedure resolves the repository to one full Git commit,
downloads and optionally inspects that immutable source archive, and requires
the bootstrap script to fetch and activate the same revision. Nix, Git,
Homebrew, its taps, Home Manager, and nix-darwin are obtained from versioned or
flake-locked sources.

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

Build the Darwin configuration on the Mac:

```sh
darwin-rebuild build --flake ~/nixos-config#macbook
```

A Linux host cannot build a Darwin activation package without a Darwin remote
builder. `flake.lock` pins nixpkgs, nix-darwin, Home Manager, and the other
flake inputs.

Run the public-repository safety checks with:

```sh
nix shell .#ci-tools -c bash scripts/check-public-repo.sh
```

See the [public repository and bootstrap security policy](./docs/public-repository-security.md)
for the release procedure, trust boundaries, automated checks, and secret
rotation requirements.

Neovim is configured under [`neovim/`](./neovim/); its plugins, parsers,
language servers, formatters, and debug adapters are supplied by Nix rather
than downloaded at runtime.
