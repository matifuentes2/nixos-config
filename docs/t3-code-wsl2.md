# T3 Code on WSL2

On WSL2, T3 Code is split in two:

- **Server (WSL2):** the headless `t3` CLI ([`packages/t3-cli.nix`](../packages/t3-cli.nix))
  runs as the `t3-server` systemd user service defined in
  [`hosts/wsl2/home.nix`](../hosts/wsl2/home.nix). It listens on `0.0.0.0:3773`,
  keeps its data in `~/.t3`, and runs the agents with the user's profile on
  `PATH`. Lingering is enabled, so it starts when WSL boots. A Windows logon
  task starts WSL and keeps it alive without an open terminal.
- **UI (Windows):** the native T3 Code app (`T3Tools.T3Code`, declared in
  [`hosts/wsl2/windows/configuration.winget`](../hosts/wsl2/windows/configuration.winget))
  connects to that server. A native window tiles cleanly under GlazeWM, unlike
  the WSLg window of the Linux desktop app.

The Linux T3 Code desktop app is not installed on WSL2: it starts its own server
on the same port with the same `~/.t3` data, and the two must not run at once.

## Setup

1. Rebuild WSL2. The service starts automatically, and Home Manager installs
   the Windows logon task through `windows-config-sync`:

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

- `windows-config-sync` registers a per-user `NixOS-WSL-T3-*` logon task
  that invokes `wsl.exe` directly to run `sleep infinity` in the distribution.
  This keeps WSL alive without an open terminal. It needs no saved password or
  administrator privileges, has no execution time limit, continues on battery
  power, and uses three one-minute retries if it fails to launch. A second
  trigger repeats every five minutes, so if WSL stops the VM and the command
  exits, the task starts WSL again; repeats are skipped while it is running.
- To intentionally shut down WSL, first end and disable the `NixOS-WSL-T3-*`
  task in Task Scheduler; otherwise it restarts WSL within five minutes. Running
  `windows-config-sync` enables and starts the task again.
- `windows-config-sync` also deploys the tracked
  [`wslconfig`](../hosts/wsl2/windows/wslconfig) to `%USERPROFILE%\.wslconfig`.
  WSL runs headless (`guiApplications=false`) with localhost forwarding enabled.
  Windows-native applications provide the UI; the WSLg compositor is unnecessary.
  This file applies to all WSL2 distributions for the Windows user. Changes take
  effect after a full `wsl --shutdown`; finish active agent work before restarting.
- For remote access, configure persistent Tailscale forwarding once from
  Windows PowerShell:

  ```powershell
  tailscale serve --bg --yes --tcp=3773 tcp://127.0.0.1:3773
  ```

  Tailscale owns the listener and resumes it after reboots. Tailnet access policy
  controls which devices can connect, and T3 still requires pairing. Windows
  localhost forwarding follows WSL's current NAT address.
- The service and the CLI must not be started a second time on port 3773.
