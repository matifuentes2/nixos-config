# T3 Code on WSL2

On WSL2, T3 Code is split in two:

- **Server (WSL2):** the headless `t3` CLI ([`packages/t3-cli.nix`](../packages/t3-cli.nix))
  runs as the `t3-server` systemd user service defined in
  [`hosts/wsl2/home.nix`](../hosts/wsl2/home.nix). It listens on `0.0.0.0:3773`,
  keeps its data in `~/.t3`, and runs the agents with the user's profile on
  `PATH`. Lingering is enabled, so it starts when WSL boots.
- **UI (Windows):** the native T3 Code app (`T3Tools.T3Code`, declared in
  [`hosts/wsl2/windows/configuration.winget`](../hosts/wsl2/windows/configuration.winget))
  connects to that server. A native window tiles cleanly under GlazeWM, unlike
  the WSLg window of the Linux desktop app.

The Linux T3 Code desktop app is not installed on WSL2: it starts its own server
on the same port with the same `~/.t3` data, and the two must not run at once.

## Setup

1. Rebuild WSL2. The service starts automatically:

   ```sh
   sudo nixos-rebuild switch --flake ~/nixos-config#wsl2
   systemctl --user status t3-server
   ss -ltnp 'sport = :3773'
   ```

2. Install the Windows app with the WinGet configuration (see
   [`wsl2-glazewm.md`](./wsl2-glazewm.md)). The configuration pins the app
   version to match `packages/t3-cli.nix`; to upgrade, bump both and reapply
   the configuration after rebuilding WSL2.

3. Mint a pairing link in WSL and add it to the Windows app under
   **Add environment**. Windows reaches the server through WSL's localhost
   forwarding:

   ```sh
   t3 pair
   ```

   If the printed URL uses a WSL-internal address, replace the host with
   `localhost:3773`.

Logs are available with `journalctl --user -u t3-server`.

## Notes

- WSL shuts the distribution down when nothing on Windows is using it. If the
  Windows app cannot connect, open a WSL terminal (or run `wsl -d NixOS`) to
  start it; the service then comes up with it.
- When Tailscale runs on Windows and WSL2 uses NAT networking, Windows must
  also forward its Tailscale interface's TCP port 3773 to the WSL2 address and
  allow the connection through Windows Firewall. These Windows settings are
  separate from this NixOS configuration. The forwarding destination may need
  updating after WSL2 restarts because its NAT address can change.
- The service and the CLI must not be started a second time on port 3773.
