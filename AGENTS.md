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

## Privacy and public-repository safety

Treat the working tree and the complete Git history as publicly accessible.
Privacy-sensitive data must never enter a commit, because deleting it in a
later commit does not remove it from history or existing forks.

- Use `55928941+matifuentes2@users.noreply.github.com` for every author and
  for every committer under local control. Before creating a commit, verify the
  repository's `git config user.email`; never commit with a personal email
  address. Protected-branch squash merges created server-side by GitHub may use
  the verified platform committer `GitHub <noreply@github.com>`; this is the
  only accepted exception because it is public infrastructure metadata rather
  than a personal address.
- Never add images or other media containing EXIF, XMP, IPTC, GPS, author,
  device make/model, device serial number, or similar identifying metadata.
  Strip metadata losslessly when possible and verify the cleaned file before
  staging it. Check every added or modified binary file explicitly.
- Do not commit unnecessary personal or network identifiers such as private
  email addresses, physical locations, Wi-Fi SSIDs, MAC addresses, device
  serial numbers, private host addresses, or private account identifiers.
- Public cryptographic material such as SSH public keys and age recipients may
  be tracked only when intentionally required by the configuration. Private
  keys, recovery codes, session material, and plaintext secrets must never be
  tracked.
- Before finishing, scan both the working tree and reachable history with
  Gitleaks (`gitleaks dir .` and `gitleaks git .`) and verify that every author
  and committer email in `git log --all` uses the configured GitHub noreply
  address, apart from the documented GitHub platform committer above. Do not
  suppress or allowlist any other finding without explaining why it is a false
  positive.
- Never rewrite or force-push shared history merely to hide exposed sensitive
  data without explicit approval. Assume anything already pushed may have been
  copied, and rotate exposed credentials even if history is subsequently
  cleaned.

Rebuild the Raspberry Pi with:

```sh
sudo nixos-rebuild switch --flake /etc/nixos#nixos
```

Rebuild the Mac from its checkout with:

```sh
sudo darwin-rebuild switch --flake ~/nixos-config#macbook
```

Before finishing a change, ensure new files are tracked, complete the privacy
checks above, and run `nix flake check`. Validate the affected host with a
non-switching build when possible:

```sh
sudo nixos-rebuild build --flake /etc/nixos#nixos
# Run on macOS:
darwin-rebuild build --flake ~/nixos-config#macbook
```

A Linux machine cannot build Darwin activation packages without a Darwin
builder; perform the macOS build on the Mac.
