# Repository instructions

## Reproducibility is mandatory

This GitHub repository (`matifuentes2/nixos-config`) is the single source of
truth for the Raspberry Pi NixOS host and the Mac nix-darwin host. A fresh
installation must be reproducible by cloning the repository and rebuilding the
appropriate flake output.

- Put host-specific operating-system configuration under `hosts/<host>/`.
  The Raspberry Pi uses `hosts/raspberry-pi/`; the Mac uses `hosts/macbook/`.
- Put cross-platform user packages, dotfiles, shell settings, and application
  configuration in `modules/home/common.nix` or another tracked shared module.
- Put Linux-only Home Manager settings in `modules/home/linux.nix`, macOS-only
  settings in `modules/home/darwin.nix`, and per-device settings in that host's
  `home.nix`.
- Install macOS GUI applications through Homebrew casks, but declare every cask
  declaratively in the tracked Nix configuration (for example, via nix-darwin's
  `homebrew.casks`). Do not install GUI applications imperatively with `brew`.
- Put cross-platform system settings in `modules/system/common.nix`. Do not
  import NixOS-only options into nix-darwin or Darwin-only options into NixOS.
- Manage inputs, host architecture, macOS username, and module wiring through
  `flake.nix`. Commit `flake.lock` whenever an input changes.
- Keep every referenced configuration file and custom module tracked in this
  repository. Do not rely on an untracked file already present on a machine.
- Do not use imperative package installation or configuration as the final
  solution. This includes `nix-env`, `nix profile install`, manually editing
  generated files, or installing software through language-specific/global
  package managers. Encode the lasting result declaratively.
- Never commit plaintext credentials. Use an appropriate encrypted-secret
  mechanism and track only encrypted material and reproducible wiring.
- Preserve existing `system.stateVersion` and `home.stateVersion` values unless
  a migration explicitly requires changing them.

Rebuild the Raspberry Pi with:

```sh
sudo nixos-rebuild switch --flake /etc/nixos#nixos
```

Rebuild the Mac from its checkout with:

```sh
sudo darwin-rebuild switch --flake ~/nixos-config#macbook
```

Before finishing a change, ensure new files are tracked and run `nix flake
check`. Validate the affected host with a non-switching build when possible:

```sh
sudo nixos-rebuild build --flake /etc/nixos#nixos
# Run on macOS:
darwin-rebuild build --flake ~/nixos-config#macbook
```

A Linux machine cannot build Darwin activation packages without a Darwin
builder; perform the macOS build on the Mac.
