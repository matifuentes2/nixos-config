# T3 Code on the Raspberry Pi

The Pi's Home Manager configuration installs the native ARM64 T3 Code desktop
release, pinned to version 0.1.7 with a fixed content hash in
[`packages/t3-code.nix`](../packages/t3-code.nix). The Lenovo continues to use
the same version's x86-64 release. This does not install the WSL2 headless
server or expose any new listening ports.

## Apply and launch

From the Pi's existing checkout, after the change is merged:

```sh
cd /etc/nixos
git pull --ff-only origin main
sudo nixos-rebuild switch --flake /etc/nixos#nixos --max-jobs 1 --cores 1
```

Do not run another Nix build/evaluation concurrently on the Pi. Check available
memory, swap, load, and temperature first; stop if the host is under pressure.
A full build can instead be prepared on a capable aarch64-linux builder.

Log out of the desktop and back in after the first activation so the login
keyring's PAM integration takes effect. Launch **T3 Code** from the application
launcher or run `t3-code` in a terminal. Codex and Claude Code are already
provided by the shared Home Manager configuration.

## Encrypted credential storage

The package adds `--password-store=gnome-libsecret` for both terminal and desktop
launches. The Pi enables GNOME Keyring and installs Seahorse (**Passwords and
Keys**) to initialize/manage a password-protected login keyring. Keep its
password matched to the login password if automatic unlocking is desired.
Passwordless/autologin sessions may require manually unlocking the keyring.
Do not use `--password-store=basic` as a workaround.

The configuration is reproducible, but provider login sessions and credentials
remain private, mutable user state and are not committed to this repository.

## Validation

On a capable machine, `python3 tests/test-t3-secure-storage.py` checks the Pi's
declarative package selection, both release URLs and hashes, keyring integration,
and the real wrapper's argument forwarding using a mocked FHS launcher. Actual
ARM64 application startup and graphics must be verified on the Pi after rebuilding.
