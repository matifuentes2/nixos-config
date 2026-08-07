# Fresh installation on macOS

This procedure bootstraps the repository's `macbook` output on a new Apple
Silicon Mac. It expects the macOS short account name `matif` and that account
must be an administrator.

No separate installation of Nix, Git, the Xcode Command Line Tools, Homebrew,
or nix-darwin is required.

## Install

Open Terminal while logged in as `matif`. The following commands resolve
`main` once to a full Git commit, download an archive for that immutable
revision, and run the bootstrap script from the same archive:

```sh
(
set -eu
repository="matifuentes2/nixos-config"
revision=$(curl --proto '=https' --tlsv1.2 -fsSL \
  "https://api.github.com/repos/$repository/commits/main" \
  | awk -F '"' '/^[[:space:]]*"sha":/ { print $4; exit }')
[ "${#revision}" -eq 40 ]
case "$revision" in *[!0-9a-f]*) exit 1 ;; esac

bootstrap_directory=$(mktemp -d)
trap 'rm -rf "$bootstrap_directory"' EXIT
curl --proto '=https' --tlsv1.2 -fsSL \
  "https://github.com/$repository/archive/$revision.tar.gz" \
  -o "$bootstrap_directory/source.tar.gz"
tar -xzf "$bootstrap_directory/source.tar.gz" -C "$bootstrap_directory"
source_directory=$(find "$bootstrap_directory" -mindepth 1 -maxdepth 1 -type d -print -quit)
[ -n "$source_directory" ]

NIXOS_CONFIG_REVISION="$revision" \
NIXOS_CONFIG_SOURCE_DIRECTORY="$source_directory" \
bash "$source_directory/scripts/bootstrap-macos.sh"
)
```

To install a previously reviewed release rather than the current `main`
snapshot, replace the `revision=$(...)` command with its full 40-character
commit. A commit URL is immutable; a branch or ordinary tag is not an
appropriate trust anchor unless repository rules prevent it from moving.

Enter the account password when macOS asks for `sudo` access. The initial build
and application downloads can take some time. When the script finishes, open a
new Terminal window.

The bootstrap script:

1. verifies that it is running as user `matif` on Apple Silicon macOS;
2. verifies that the selected revision is a full commit ID;
3. installs a checksum-verified, versioned Nix installer in multi-user daemon
   mode when Nix is not already available;
4. obtains Git from the archive's locked nixpkgs input when the Xcode Command
   Line Tools are absent;
5. fetches exactly the selected Git commit into a temporary worktree and moves
   it atomically to `~/nixos-config`;
6. checks and builds the locked `macbook` flake output; and
7. activates nix-darwin, Home Manager, the pinned Homebrew distribution and
   taps, and all declared Homebrew casks.

Homebrew itself and the `homebrew-core` and `homebrew-cask` tap revisions are
pinned by `flake.lock`. Cask downloads can still depend on artifacts retained
by their upstream vendors, and some GUI applications update themselves after
installation.

## Inspect before running

The procedure downloads a complete archive before executing anything. Inspect
it after extraction and before the final `bash` command if desired:

```sh
less "$source_directory/scripts/bootstrap-macos.sh"
```

The archive and script use the same commit. This avoids the previous situation
where a script inspected from one `main` revision could clone and activate a
different revision later.

## Rerun after an interruption

Rerun the complete installation block above with the **same revision**. The
script reuses `~/nixos-config` only when all of these are true:

- it is a real Git worktree rather than a symbolic link;
- its `origin` is this repository's HTTPS URL;
- its `HEAD` is the selected bootstrap revision; and
- it has no modified or untracked files.

New clones are assembled in a temporary directory and moved into place only
after Git verifies the requested commit, so an interrupted clone does not leave
a partial `~/nixos-config`.

If the checkout has subsequently been updated or edited, the bootstrap script
stops rather than activating it with administrator privileges. Use the normal
update procedure instead.

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
