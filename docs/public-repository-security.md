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

Every pull request runs the CI routing/gate regression tests, workflow syntax,
Nix formatting, ShellCheck, and the complete public-repository safety scan.
These checks start immediately, independently of the host validation jobs.
Run the same quick checks locally with:

```sh
nix shell --inputs-from . nixpkgs#python3 -c python3 tests/test-ci-validation.py
nix shell .#ci-tools -c actionlint
nix shell .#ci-tools -c sh -c 'git ls-files -z "*.nix" | xargs -0 nixfmt --check'
nix shell .#ci-tools -c shellcheck scripts/*.sh
nix shell .#ci-tools -c bash scripts/check-public-repo.sh
```

Before merging, all checks selected by `scripts/ci-validation.py` must pass:

- Changes confined to a known `hosts/<host>/` directory validate that host:
  Linux hosts evaluate their activation derivation, and the Mac builds its
  activation package on native Apple silicon.
- Changes confined to `README.md`, `AGENTS.md`, or Markdown under `docs/` need
  only the quick checks. Markdown outside those locations may be a runtime
  dependency and is not exempt.
- Shared modules, packages, flake inputs, scripts, tests, CI configuration,
  and all unrecognized paths select full flake checks and every host.
- A PR diff uses the merge base and includes both sides of renames, deleted
  files, and added files. Multiple host changes select the union of those hosts.

Host evaluations, flake checks, and the Mac build run independently after
selection. Full validation also runs on every push to `main`, weekly, and via
**Run workflow** (`workflow_dispatch`). Before publishing a release, run the
full suite regardless of changed paths:

```sh
nix flake check
nix eval --raw .#nixosConfigurations.amd64-lenovo-legion-y720.config.system.build.toplevel.drvPath
nix eval --raw .#nixosConfigurations.wsl2.config.system.build.toplevel.drvPath
nix eval --raw .#nixosConfigurations.nixos.config.system.build.toplevel.drvPath
nix eval --raw .#nixosConfigurations.hgrai.config.system.build.toplevel.drvPath
nix build --no-link .#darwinConfigurations.macbook.system
nix shell --inputs-from . nixpkgs#python3 -c python3 tests/test-ci-validation.py
nix shell .#ci-tools -c actionlint
nix shell .#ci-tools -c sh -c 'git ls-files -z "*.nix" | xargs -0 nixfmt --check'
nix shell .#ci-tools -c shellcheck scripts/*.sh
nix shell .#ci-tools -c bash scripts/check-public-repo.sh
```

After changing GitHub repository controls, additionally run:

```sh
scripts/audit-github-settings.sh
```

The Ubuntu CI job evaluates selected Linux activation
derivations rather than realizing their multi-gigabyte closures. The native
Apple silicon macOS job builds the Mac activation package. On the Lenovo
Legion Y720, perform a non-switching host build:

```sh
sudo nixos-rebuild build --flake /etc/nixos#amd64-lenovo-legion-y720
```

The required check keeps its existing name, **Flake, shell, and public-repository
checks**, so branch protection does not need changing. It always runs and
requires successful selection and quick checks. Every selected job must succeed;
failure, cancellation, unexpected skips, and missing or invalid selection outputs
fail the gate. Only jobs explicitly excluded by the plan may be skipped. Do not
add workflow-level path filters: they can leave the required check pending.

Each Nix job restores and saves a Nix store cache, separated by OS, architecture,
and job. Keys include the lockfile hash and run/attempt; restoration first tries
the same lockfile, then an older cache for that platform and job. Nix still
validates store dependencies. Caches contain no credentials, use the action's
default GitHub cache scope restrictions, and need no extra token or repository
permissions. Each job garbage-collects toward 2 GiB before saving to limit cache
transfer and storage costs; rooted paths may exceed that target. GitHub may evict
older caches, and a miss must remain correct. Compare cache restore/save time
with the work avoided when tuning this limit.

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
