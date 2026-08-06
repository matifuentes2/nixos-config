# Fresh installation on macOS

This procedure bootstraps the repository's `macbook` output on a new Apple
Silicon Mac. It expects the macOS short account name `matif` and that account
must be an administrator.

No separate installation of Nix, Git, the Xcode Command Line Tools, Homebrew,
or nix-darwin is required.

## Install

Open Terminal while logged in as `matif` and run:

```sh
curl --proto '=https' --tlsv1.2 -fsSL \
  https://raw.githubusercontent.com/matifuentes2/nixos-config/main/scripts/bootstrap-macos.sh \
  | bash
```

Enter the account password when macOS asks for `sudo` access. The initial build
and application downloads can take some time. When the script finishes, open a
new Terminal window.

The bootstrap script:

1. verifies that it is running as user `matif` on Apple Silicon macOS;
2. installs Lix when Nix is not already available;
3. clones this repository to `~/nixos-config`, using a Nix-provided Git when the
   Xcode Command Line Tools are absent;
4. checks and builds the locked `macbook` flake output;
5. activates nix-darwin and Home Manager; and
6. installs the pinned Homebrew distribution and all declared Homebrew casks.

Lix is the Nix implementation recommended by nix-darwin. Homebrew itself is
installed declaratively by `nix-homebrew`; it is not a manual prerequisite. If
Homebrew already exists at its standard prefix, `nix-homebrew` adopts it during
the first activation.

## Inspect before running

The command above downloads code and eventually requests administrator access.
To inspect it first:

```sh
curl --proto '=https' --tlsv1.2 -fLo bootstrap-macos.sh \
  https://raw.githubusercontent.com/matifuentes2/nixos-config/main/scripts/bootstrap-macos.sh
less bootstrap-macos.sh
bash bootstrap-macos.sh
```

## Rerun or update

The bootstrap command is safe to rerun after an interrupted installation. It
reuses an existing Git checkout at `~/nixos-config` and rebuilds the declared
configuration; it does not overwrite or automatically update that checkout.

For normal updates after installation:

```sh
cd ~/nixos-config
git pull --ff-only
rebuild
```

Build without activating changes:

```sh
darwin-rebuild build --flake ~/nixos-config#macbook
```

If the account name or architecture differs, change `darwinUsername` and
`darwinSystem` in `flake.nix` and adapt the bootstrap guard before the first
activation. The one-command path intentionally stops rather than applying this
host configuration to an unexpected user or architecture.
