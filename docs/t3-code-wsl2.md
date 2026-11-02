# T3 Code network access in WSL2

The WSL2 Home Manager configuration merges
`serverExposureMode: "network-accessible"` into
`~/.t3/userdata/desktop-settings.json` on each rebuild. T3 Code Desktop then
listens on `0.0.0.0` instead of loopback. Other desktop preferences remain
writable and are preserved. The WSL2 session sets `T3CODE_PORT=3773`, and the
NixOS firewall allows that TCP port. Other hosts keep their existing settings.

Quit T3 Code before rebuilding so the running app cannot overwrite the
updated preferences:

```sh
sudo nixos-rebuild switch --flake /path/to/nixos-config#wsl2
```

Start a new login shell to load the session variables, then launch `t3-code`.
Check the listener with:

```sh
ss -ltnp 'sport = :3773'
```

It should report `0.0.0.0:3773`. Desktop network exposure is controlled by
the saved setting, rather than the server CLI's `--host` option.

When Tailscale runs on Windows and WSL2 uses NAT networking, Windows must
also forward its Tailscale interface's TCP port 3773 to the WSL2 address and
allow the connection through Windows Firewall. These Windows settings are
separate from this NixOS configuration. The forwarding destination may need
updating after WSL2 restarts because its NAT address can change.
