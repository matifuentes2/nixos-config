# T3 Code on the Raspberry Pi

The Pi's Home Manager configuration installs the native ARM64 T3 Code desktop
release, pinned to version 0.1.7 with a fixed content hash in
[`packages/t3-code.nix`](../packages/t3-code.nix). The Lenovo continues to use
the same version's x86-64 release. The Pi also installs the pinned ARM64
standalone CLI (`t3`), used by the persistent server described below.

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

## Headless use (no desktop login required)

The declarative `t3-server` systemd user service starts at boot using the Pi's
existing user lingering. It listens only on `127.0.0.1:3774`, opens no firewall
ports, and runs agents from the user's declarative profile. It does not need
Hyprland, a browser, or Electron running on the Pi.

The service and normal CLI commands use the same default `~/.t3` state.
Use plain `t3 pair`; no wrapper or `T3CODE_HOME` override is needed. Use the
browser or the desktop client's **Add environment** flow to connect to this
server, rather than launching a second local server against the same state.

### Migration from the old isolated server

Close the local T3 desktop app before rebuilding. On the first activation,
Home Manager stops `t3-server`, preserves any existing `~/.t3` directory in
`~/.t3-before-unification.XXXXXXXX/state`, and moves the entire old
`~/.local/share/t3-headless` directory to `~/.t3`. This keeps the running
headless server's sessions, settings, credentials, and SQLite WAL files
together. The service is then started with the new configuration. Later
activations do nothing once the old directory is gone.

The two databases are **not merged**. Any old desktop sessions remain in the
backup. Keep it until you have verified the migrated server; it contains
private state and must not be committed. Migration refuses symlinks or a
detected process using the default database; resolve that condition before
retrying activation.

After rebuilding, check on the Pi:

```sh
systemctl --user status t3-server
journalctl --user -u t3-server -n 50
ss -ltnp 'sport = :3774'
t3 pair
```

On your client computer, keep this SSH tunnel running (replace `pi` with your
SSH alias or `pi@HOST` if necessary):

```sh
ssh -N -L 3774:127.0.0.1:3774 pi
```

Use the pairing link/token from `t3 pair` with the client endpoint
`http://127.0.0.1:3774`, in a browser or the desktop client's **Add environment**
flow. If the pairing link advertises a different host, change only its
host/port to `127.0.0.1:3774`; retain its token/path. Pairing links are private
credentials: do not paste them into issues or commit them. Keep client/server
versions compatible (the server is pinned to 0.1.7).

To stop/restart the server, use `systemctl --user stop t3-server` or
`systemctl --user restart t3-server`. Do not also run `t3 serve`
while the service is active. Do not use `t3 service install`, npm global
installation, or self-update: the package and service are managed by Nix.

Agent authentication remains private user state. Authenticate Codex/Claude on
the Pi as needed. A password-protected Secret Service keyring may need manual
unlocking when used without a password-based graphical login; the headless
service does not bypass or weaken that protection.

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

On a capable machine, `python3 tests/test-t3-headless.py` checks ARM64/x86-64
CLI pins, shared default state, migration wiring, listen arguments, agent PATH, lingering, nix-ld
libraries, and unchanged WSL service settings. `python3 tests/test-t3-secure-storage.py` checks the Pi's
declarative package selection, both release URLs and hashes, keyring integration,
and the real wrapper's argument forwarding using a mocked FHS launcher. Actual
ARM64 application startup and graphics must be verified on the Pi after rebuilding.
