# Public repository and bootstrap security

This repository is public. Treat every tracked file and every reachable Git
commit as permanently available to anyone, including content later deleted
from `main`.

## Bootstrap trust model

The two bootstrap-backed installation guides pin an immutable release, its
full Git commit ID, and the SHA-256 checksum of its attached source archive.
The bootstrap script then fetches and verifies the same Git commit before
activation. This prevents a branch update or asset replacement between
reviewing the release and activating the configuration.

`bootstrap-release.env` is the single tracked record of the current release,
full commit, deterministic archive name, and SHA-256 checksum. CI runs
`scripts/check-bootstrap-release.sh` to ensure both bootstrap-backed
installation guides contain the same values. The WSL2 guide installs the
upstream NixOS-WSL image and is not part of this bootstrap-release mechanism.

To publish a new bootstrap release:

1. merge the candidate through a pull request and wait for both required checks
   on `main` to pass;
2. from a clean, synchronized `main`, run
   `scripts/audit-github-settings.sh`;
3. run `scripts/create-bootstrap-release.sh bootstrap-vMAJOR.MINOR.PATCH`;
4. let the script verify the successful workflow, create the deterministic
   archive, publish the draft as an immutable release, and update
   `bootstrap-release.env` plus both installation guides; and
5. move those generated documentation changes to a branch, validate them, and
   merge them through another pull request.

The release script deliberately refuses an existing version, non-`main`
revision, dirty checkout, failed workflow, or GitHub control audit. If anything
fails after publication, the release remains immutable; use the printed commit
and checksum to finish the manifest update rather than editing the release.

The validation workflow follows GitHub's
[secure-use guidance](https://docs.github.com/en/actions/reference/security/secure-use)
by granting read-only repository permissions and pinning actions to full commit
SHAs. GitHub's
[immutable-release guidance](https://docs.github.com/en/enterprise-cloud@latest/code-security/concepts/supply-chain-security/immutable-releases)
describes the repository setting used for reviewed release tags and assets.

The repository currently enables immutable releases and protects
`bootstrap-v*` tags against updates and deletion. A commit ID and checksum
prevent accidental movement and time-of-check/time-of-use races. They do not
protect a new visitor if GitHub and the maintainer account are already
compromised. A higher-assurance release should additionally sign a manifest
containing the commit and archive checksum with a key stored outside GitHub,
and distribute the verification key through an independent trusted channel.

## Public cryptographic material

The following are intentionally public and are not private credentials:

- SOPS age recipients;
- SSH public keys and fingerprints; and
- SOPS-encrypted files.

Use keys dedicated to this repository and host where practical. Reusing a
public key can correlate identities across repositories and services.

Private age identities, SSH private keys, Bitwarden sessions, recovery codes,
and plaintext application secrets must never be committed.

If an age identity is exposed, rotating only the recipient is insufficient.
Anyone holding the old identity can decrypt old ciphertext retained in Git
history. Rotate all affected application credentials, generate a new age
identity, update `.sops.yaml`, and re-encrypt the current secret files. Assume
old ciphertext and any secret it protected remain compromised.

## Required checks

Before merging or publishing a release, run:

```sh
nix flake check
nix eval --raw .#nixosConfigurations.amd64-lenovo-legion-y720.config.system.build.toplevel.drvPath
nix eval --raw .#nixosConfigurations.wsl2.config.system.build.toplevel.drvPath
nix build --no-link .#darwinConfigurations.macbook.system
nix shell .#ci-tools -c actionlint
nix shell .#ci-tools -c sh -c 'git ls-files -z "*.nix" | xargs -0 nixfmt --check'
nix shell .#ci-tools -c shellcheck scripts/*.sh
bash scripts/check-bootstrap-release.sh
nix shell .#ci-tools -c bash scripts/check-public-repo.sh
```

Before publishing a bootstrap release, additionally run:

```sh
scripts/audit-github-settings.sh
```

The standard CI runner evaluates the physical amd64 and WSL2 activation
derivations rather than realizing their multi-gigabyte closures. On the Lenovo
Legion Y720, perform a non-switching host build:

```sh
sudo nixos-rebuild build --flake /etc/nixos#amd64-lenovo-legion-y720
```

On the WSL2 host, also perform a non-switching host build:

```sh
sudo nixos-rebuild build --flake ~/nixos-config#wsl2
```

On the Raspberry Pi, likewise perform a non-switching host build:

```sh
sudo nixos-rebuild build --flake /etc/nixos#nixos
```

The public-repository check scans the working tree and reachable Git history
with Gitleaks, verifies author and committer addresses, and rejects identifying
metadata in tracked media. Authors and locally created commits must use the
configured GitHub noreply address. Protected-branch squash merges may use
`GitHub <noreply@github.com>` as their verified server-side committer; this is
an explicitly documented false positive because it contains no personal
address. Automated checks reduce risk but do not replace review of
configuration values that may reveal personal preferences or account
identifiers.
