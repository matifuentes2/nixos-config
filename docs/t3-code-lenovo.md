# T3 Code secure storage on Lenovo

T3 Code requires Electron's encrypted `safeStorage` for its connection catalog.
The Lenovo configuration enables GNOME Keyring's Secret Service and SDDM PAM
integration. The pinned SDDM PAM configuration delegates to `login`; enabling
GNOME Keyring also enables the keyring rules in that included stack.

The packaged `t3-code` command always adds
`--password-store=gnome-libsecret`. The desktop launcher uses that same command.
The pinned AppImage FHS environment already includes `libsecret`. No plaintext
fallback, blank keyring password, or `--password-store=basic` is configured.

References:
- [T3 Code issue #5427](https://github.com/pingdotgg/t3code/issues/5427)
- [Electron safeStorage](https://www.electronjs.org/docs/latest/api/safe-storage)

## Apply and initialize

On Lenovo, rebuild from the branch:

```sh
sudo nixos-rebuild switch --refresh --flake github:matifuentes2/nixos-config/feat/lenovo-t3-code#amd64-lenovo-legion-y720
```

Fully quit T3 Code (including any tray/background instance), log out of Hyprland,
and log back in through **SDDM using your account password**. A screen unlock or
an SSH login is not a substitute for a new desktop password login. Autologin or
passwordless/fingerprint-only authentication cannot supply the password needed
to unlock the keyring automatically.

On a fresh installation, the password-protected **Login** keyring may need to be
created on first use. Open **Passwords and Keys** (`seahorse`, installed on Lenovo)
if no initialization prompt appears. Create a password keyring named `Login`,
set it as the default, and use the same non-empty password as your account login.
If an existing keyring has a different password, unlock it with its old password
and change its password to match the login password. Do not delete an existing
keyring: it may hold other applications' credentials. Log out/in again after
initializing or changing it to verify automatic unlock.

## Verify in the desktop session

Run as your normal user in a terminal **inside Hyprland**, not with `sudo`:

```sh
busctl --user get-property org.freedesktop.secrets \
  /org/freedesktop/secrets/aliases/default \
  org.freedesktop.Secret.Collection Locked
```

Expected result: `b false` (the default collection exists and is unlocked).
A missing collection means initialization/default selection is still needed;
`b true` means the keyring needs unlocking. This D-Bus request also activates the
Secret Service if it is not already running. No secret values are printed.

Launch T3 Code normally, from either `t3-code` or its desktop entry, and retry
adding the MacBook environment. To check the running Electron main process:

```sh
pgrep -af -- '--password-store=gnome-libsecret'
```

This verifies the launch flag, not the encryption backend by itself. Successful
connection registration after confirming an unlocked collection is the runtime
test. Do not override the wrapper with a plaintext password-store flag.

## Validation from macOS

`python3 tests/test-t3-secure-storage.py` evaluates the real Lenovo keyring/PAM
configuration and exercises the package's install commands against a mock FHS
launcher on the current platform. It verifies terminal/desktop argument
forwarding and that the symlink target is not modified. It does not execute the
Linux AppImage or test SDDM, D-Bus, PAM, or encryption at runtime.

On x86-64 Linux, also perform the real non-switching build:

```sh
nix build --no-link .#nixosConfigurations.amd64-lenovo-legion-y720.config.system.build.toplevel
```
