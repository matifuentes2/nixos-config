# Public repository and bootstrap security

This repository is public. Treat every tracked file and every reachable Git
commit as permanently available to anyone, including content later deleted
from `main`.

## Bootstrap trust model

The installation guides resolve `main` once, validate that GitHub returned a
full commit ID, download that immutable commit's archive, and require the
bootstrap script to fetch and verify the same Git commit before activation.
This prevents a branch update between inspecting the script and cloning the
configuration.

For a reviewed installation release, use a full commit ID directly instead of
resolving `main`. Maintainers should:

1. run the validation workflow and host build for the candidate commit;
2. create an immutable GitHub release whose tag points to that commit;
3. enable repository rules that prevent release-tag updates or deletion;
4. publish the full commit ID and source archive checksum in the release notes;
5. keep `main` protected from force-pushes and require passing checks; and
6. update pinned bootstrap dependencies only through a reviewed pull request.

The validation workflow follows GitHub's
[secure-use guidance](https://docs.github.com/en/actions/reference/security/secure-use)
by granting read-only repository permissions and pinning actions to full commit
SHAs. GitHub's
[immutable-release guidance](https://docs.github.com/en/enterprise-cloud@latest/code-security/concepts/supply-chain-security/immutable-releases)
describes the repository setting used for reviewed release tags and assets.

A commit ID prevents accidental movement and time-of-check/time-of-use races.
It does not protect a new visitor if GitHub and the maintainer account are
already compromised. A higher-assurance release should additionally sign a
manifest containing the commit and archive checksum with a key stored outside
GitHub, and distribute the verification key through an independent trusted
channel.

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
nix build --no-link .#darwinConfigurations.macbook.system
nix shell .#ci-tools -c actionlint
nix shell .#ci-tools -c sh -c 'git ls-files -z "*.nix" | xargs -0 nixfmt --check'
nix shell .#ci-tools -c shellcheck \
  scripts/bootstrap.sh scripts/bootstrap-macos.sh scripts/check-public-repo.sh
nix shell .#ci-tools -c bash scripts/check-public-repo.sh
```

On the Raspberry Pi, also perform a non-switching host build:

```sh
sudo nixos-rebuild build --flake /etc/nixos#nixos
```

The public-repository check scans the working tree and reachable Git history
with Gitleaks, verifies author and committer addresses, and rejects identifying
metadata in tracked media. Automated checks reduce risk but do not replace
review of configuration values that may reveal personal preferences or account
identifiers.
