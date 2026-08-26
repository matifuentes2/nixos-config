# Repository instructions

## Reproducibility is mandatory

This GitHub repository (`matifuentes2/nixos-config`) is the single source of
truth for the Raspberry Pi NixOS host, the NixOS-WSL host, and the Mac
nix-darwin host. A fresh installation must be reproducible by cloning the
repository and rebuilding the appropriate flake output.

- Put host-specific operating-system configuration under `hosts/<host>/`.
  The Raspberry Pi uses `hosts/raspberry-pi/`, the Lenovo Legion Y720 uses
  `hosts/amd64-lenovo-legion-y720/`, WSL2 uses `hosts/wsl2/`, and the Mac uses
  `hosts/macbook/`.
- Put cross-platform user packages, dotfiles, shell settings, and application
  configuration in `modules/home/common.nix` or another tracked shared module.
- Put Linux desktop Home Manager settings in `modules/home/linux.nix`, macOS-only
  settings in `modules/home/darwin.nix`, and per-device settings in that host's
  `home.nix`. Do not import the Hyprland-oriented Linux module into WSL2.
- Install macOS GUI applications through Homebrew casks, but declare every cask
  declaratively in the tracked Nix configuration (for example, via nix-darwin's
  `homebrew.casks`). Do not install GUI applications imperatively with `brew`.
- Put cross-platform system settings in `modules/system/common.nix`. Do not
  import NixOS-only options into nix-darwin or Darwin-only options into NixOS.
- Manage inputs, host architectures, macOS and WSL usernames, and module wiring
  through `flake.nix`. Commit `flake.lock` whenever an input changes.
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

## Raspberry Pi resource safety

The Raspberry Pi is resource-constrained. Treat Nix evaluation and builds on
that host as potentially disruptive, especially while the Orca server or other
services are running.

- Do not run `nix flake check`, a full NixOS build, or another broad evaluation
  on the Raspberry Pi unless the user explicitly authorizes it. Prefer targeted
  syntax checks and evaluation of only the changed option or derivation.
- Defer complete flake checks and host builds to CI or a more capable machine
  whenever possible. Report the deferred validation clearly instead of trying
  to satisfy it locally at the cost of exhausting the host.
- When an authorized build must run on the Raspberry Pi, serialize it with
  `--max-jobs 1 --cores 1`, avoid concurrent checks/builds, and stop if memory,
  swap, load, or temperature indicates resource pressure.
- Never run multiple Nix evaluations or builds in parallel on the Raspberry Pi.
  Start with the least expensive targeted validation and increase scope only
  when necessary and approved.

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

## Bootstrap and release maintenance

Agents changing `scripts/bootstrap*.sh`, installation guides, flake inputs,
Homebrew taps, CI validation, GitHub repository controls, or bootstrap releases
must first read [`docs/public-repository-security.md`](./docs/public-repository-security.md).

- `bootstrap-release.env` is the single tracked record of the current reviewed
  release, commit, archive name, and SHA-256 checksum. Never update only one of
  the two bootstrap-backed installation guides; run
  `scripts/check-bootstrap-release.sh` to ensure both guides and the manifest
  agree.
- Published `bootstrap-v*` releases and tags are immutable. Never attempt to
  replace, edit, retag, or delete one. Publish the next semantic version with
  `scripts/create-bootstrap-release.sh` only after the candidate commit is on
  `main` and its validation workflow has passed.
- Run `scripts/audit-github-settings.sh` after changing GitHub controls or
  publishing a release. It verifies protected `main`, required checks,
  immutable releases, protected release tags, and the release asset digest.
- `main` is protected. Submit changes through a pull request and wait for the
  required check; do not weaken or temporarily bypass protection to merge.
- Run every command under **Required checks** in the public-repository security
  document before merging or publishing a release.

Rebuild the Raspberry Pi with:

```sh
sudo nixos-rebuild switch --flake /etc/nixos#nixos
```

Rebuild the Lenovo Legion Y720 from its checkout with:

```sh
sudo nixos-rebuild switch --flake /etc/nixos#amd64-lenovo-legion-y720
```

Rebuild WSL2 from its checkout with:

```sh
sudo nixos-rebuild switch --flake ~/nixos-config#wsl2
```

Rebuild the Mac from its checkout with:

```sh
sudo darwin-rebuild switch --flake ~/nixos-config#macbook
```

Before finishing a change, ensure new files are tracked and complete the
privacy checks above. Run `nix flake check` and validate the affected host with
a non-switching build when possible, except that on the Raspberry Pi these
resource-intensive checks must follow the resource-safety rules above and be
deferred unless explicitly authorized:

```sh
sudo nixos-rebuild build --flake /etc/nixos#nixos
# Run on x86-64 Linux:
nix build --no-link .#nixosConfigurations.amd64-lenovo-legion-y720.config.system.build.toplevel
# Run on x86-64 Linux or WSL2:
nix build --no-link .#nixosConfigurations.wsl2.config.system.build.toplevel
# Run on macOS:
darwin-rebuild build --flake ~/nixos-config#macbook
```

A Linux machine cannot build Darwin activation packages without a Darwin
builder; perform the macOS build on the Mac. A Mac also needs a Linux builder
to build the WSL2 activation package.
