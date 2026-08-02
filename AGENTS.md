# Repository instructions

## Reproducibility is mandatory

This GitHub repository (`matifuentes2/nixos-config`) is the single source of
truth for this machine. A fresh NixOS installation must be able to reproduce
all installed packages and persistent system/user configuration by cloning the
repository and rebuilding its flake.

- Declare machine-wide packages, services, users, hardware settings, and other
  operating-system configuration in `configuration.nix` or an imported,
  tracked NixOS module.
- Declare user packages, dotfiles, shell settings, and application
  configuration in `home.nix` or an imported, tracked Home Manager module.
- Manage inputs and module wiring through `flake.nix`, and commit `flake.lock`
  whenever an input changes so builds remain pinned.
- Keep every referenced configuration file and custom module in this
  repository. Do not rely on an untracked file already present on the machine.
- Do not use imperative package installation or configuration as the final
  solution. This includes `nix-env`, `nix profile install`, manually editing
  generated files, or installing software through language-specific/global
  package managers. Encode the desired result declaratively instead.
- If a temporary manual command is needed for diagnosis, translate its lasting
  effect into the flake, NixOS configuration, or Home Manager configuration
  before considering the work complete.
- Never commit plaintext credentials or other secrets. Represent secret
  requirements declaratively using an appropriate encrypted-secret mechanism,
  with only encrypted material and reproducible wiring tracked by Git.

Rebuild the host with:

```sh
sudo nixos-rebuild switch --flake /etc/nixos#nixos
```

Before finishing a change, ensure relevant new files are tracked and validate
with `nix flake check` and/or a non-switching build such as:

```sh
sudo nixos-rebuild build --flake /etc/nixos#nixos
```
