# Public repository and bootstrap security

This repository is public. Treat every tracked file and every reachable Git
commit as permanently available to anyone, including content later deleted
from `main`.

## Bootstrap trust model

This repository has a single maintainer, so fresh installs simply run the
current `main` branch over HTTPS from GitHub:

- the Raspberry Pi runs the flake app with
  `nix run github:matifuentes2/nixos-config`, which clones the same commit it
  was built from; and
- the Mac runs `scripts/bootstrap-macos.sh` from `main`, which clones `main`.

Trust therefore rests on GitHub, the maintainer's GitHub account, and the
protected `main` branch (pull requests plus the required validation check).
There are no release tags or archive checksums to maintain. Everything the
bootstrap builds is still pinned by `flake.lock`.

The validation workflow follows GitHub's
[secure-use guidance](https://docs.github.com/en/actions/reference/security/secure-use)
by granting read-only repository permissions and pinning actions to full commit
SHAs.

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

Before merging, run:

```sh
nix flake check
nix eval --raw .#nixosConfigurations.amd64-lenovo-legion-y720.config.system.build.toplevel.drvPath
nix eval --raw .#nixosConfigurations.wsl2.config.system.build.toplevel.drvPath
nix build --no-link .#darwinConfigurations.macbook.system
nix shell .#ci-tools -c actionlint
nix shell .#ci-tools -c sh -c 'git ls-files -z "*.nix" | xargs -0 nixfmt --check'
nix shell .#ci-tools -c shellcheck scripts/*.sh
nix shell .#ci-tools -c bash scripts/check-public-repo.sh
```

After changing GitHub repository controls, additionally run:

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
