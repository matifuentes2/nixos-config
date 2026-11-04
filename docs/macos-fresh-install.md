# Fresh installation on macOS

This procedure bootstraps the repository's `macbook` output on a new Apple
Silicon Mac. It expects the macOS short account name `matif` and that account
must be an administrator.

No separate installation of Nix, Git, the Xcode Command Line Tools, Homebrew,
or nix-darwin is required.

## Install

Open Terminal while logged in as `matif` and run:

```sh
bash <(curl -fsSL https://raw.githubusercontent.com/matifuentes2/nixos-config/main/scripts/bootstrap-macos.sh)
```

Enter the account password when macOS asks for `sudo` access. The initial build
and application downloads can take some time. When the script finishes, open a
new Terminal window.

The bootstrap script:

1. verifies that it is running as user `matif` on Apple Silicon macOS;
2. installs a checksum-verified, versioned Nix installer in multi-user daemon
   mode when Nix is not already available;
3. obtains Git from this repository's locked nixpkgs input when the Xcode
   Command Line Tools are absent;
4. clones the repository's `main` branch to `~/nixos-config`;
5. builds the locked `macbook` flake output; and
6. activates nix-darwin, Home Manager, the pinned Homebrew distribution and
   taps, and all declared Homebrew casks.

Homebrew itself and the `homebrew-core` and `homebrew-cask` tap revisions are
pinned by `flake.lock`. Cask downloads can still depend on artifacts retained
by their upstream vendors, and some GUI applications update themselves after
installation.

If `brew` reports a formula DSL error such as `unknown keyword: :overwrite`,
the pinned Homebrew distribution may be older than the formula metadata.
Update Homebrew through Nix rather than `brew update`:

```sh
cd ~/nixos-config
nix flake update nix-homebrew
darwin-rebuild build --flake .#macbook
sudo darwin-rebuild switch --flake .#macbook
brew upgrade llmfit
```

Review and retain the `flake.lock` changes so the updated Homebrew version is
reproducible. Updating `nix-homebrew` also updates its pinned `brew-src` input;
there is no need to update unrelated flake inputs.

## Rerun after an interruption

Run the same command again. An existing `~/nixos-config` is reused as long as
it is a real Git worktree whose `origin` is this repository's HTTPS URL; a new
clone is assembled in a temporary directory and only moved into place once
complete, so an interrupted clone does not leave a partial checkout.

## Normal updates

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
activation. The bootstrap intentionally stops rather than applying this host
configuration to an unexpected user or architecture.
