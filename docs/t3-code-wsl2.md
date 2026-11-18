# T3 Code on WSL2

Use the native Windows T3 Code app and enable its built-in WSL backend.
The app manages the backend; NixOS does not install the Linux T3 desktop app,
the standalone `t3` CLI, or a `t3-server` service on this host.

## Setup

1. Install the Windows app using the tracked WinGet configuration described in
   [`wsl2-glazewm.md`](./wsl2-glazewm.md).
2. Enable the WSL backend in the Windows app and select the NixOS distribution.
   Keep repositories and agent tools in WSL; the shared Home Manager
   configuration still provides the development tools.

No manual server pairing or port 3773 firewall opening is needed.

## Migrating from the standalone server

Rebuild WSL2 with the updated configuration:

```sh
sudo nixos-rebuild switch --flake ~/nixos-config#wsl2
```

Activation stops the old `t3-server` user service and removes its unit,
package, port setting, firewall opening, and user lingering configuration.
`windows-config-sync` stops and unregisters the old per-user,
per-distribution `NixOS-WSL-T3-*` keepalive task. If Windows interop is
unavailable during activation, run `windows-config-sync` later from a WSL shell.
Existing `~/.t3` data is preserved; this does not import it into the Windows app.

If you previously enabled Tailscale forwarding for the standalone server,
remove that listener from Windows PowerShell:

```powershell
tailscale serve --tcp=3773 off
```

The tracked [`wslconfig`](../hosts/wsl2/windows/wslconfig) still disables WSLg
and enables localhost forwarding. Windows-native applications provide the UI.
Changes to that file apply to all WSL2 distributions and take effect after
`wsl --shutdown`; finish active agent work before restarting.
