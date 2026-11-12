# T3 Code on hgrai

The proposed host configuration in `hosts/hgrai/agents.nix` installs the pinned
ARM64 T3 CLI and Codex under a dedicated `coding-agent` account. This account
has no sudo or Docker group membership. `matif` remains the administrator.
No repository, provider credentials, or support project tokens are enrolled by
this module. Applying it does not start support-ticket processing.

## Service and access

The lingering account runs the `t3-server` user service at boot. T3 listens on
`127.0.0.1:3773`, keeps its state in `/home/coding-agent/.t3`, and resolves tools
from the account's declarative package profile. No public firewall port is
opened. Do not start a second server against this state.

After a reviewed rebuild, inspect the service as the service user:

```sh
sudo -u coding-agent XDG_RUNTIME_DIR=/run/user/$(id -u coding-agent) systemctl --user status t3-server
sudo -u coding-agent XDG_RUNTIME_DIR=/run/user/$(id -u coding-agent) journalctl --user -u t3-server -n 50
```

For initial access, forward the server over SSH from the client:

```sh
ssh -N -L 3775:127.0.0.1:3773 hgrai
```

Use the local forwarded endpoint with T3's pairing flow. Run `t3 pair` as
`coding-agent`, with that account's HOME and runtime directory. Pairing material
is a credential: do not publish it or commit it. A persistent Tailscale Serve
mapping can replace the SSH tunnel later; retain the loopback listener and
pairing requirement. Keep client/server versions compatible with the pinned
`packages/t3-cli.nix` release.

For tailnet pairing, run `t3 pair --tailscale` as `coding-agent`. NixOS makes
that account the Tailscale operator so T3 can configure Serve HTTPS on port 443
and proxy to its loopback listener. This grants Tailscale management access to
the service account, not sudo. `matif` can still administer Tailscale using
`sudo tailscale ...`. Serve is tailnet-only; this setup does not enable Funnel.
The tailnet must permit HTTPS certificates and Serve. Pairing still requires
the short-lived token generated in your terminal; do not paste it into chat.

Authenticate Codex and GitHub as `coding-agent` using their supported login
flows. Never copy the administrator's complete home or credentials. Headless
credential storage and provider login must be validated on this host before
enrolling real work; installing libsecret alone does not provision an unlocked
Secret Service keyring.

## Support-center integration

The support-center runner currently invokes `codex exec` directly. This module
does not change it into a T3 client. A separate adapter is required:

1. Poll support-center using a project-scoped token and atomically claim a job.
2. Resolve the registered repository against a host-controlled allowlist. Treat
   ticket text and repository URLs as data, never as provisioning authority.
3. Submit the ticket to T3 using its supported automation interface, with an
   isolated task worktree. Persist the support job ID, T3 run/thread identity,
   and attempt so a process restart can reconcile existing work.
4. Renew the support lease every minute while the T3 run is active. A submitted
   task is not a completed job. On cancellation or lease loss, stop its T3 run
   and retain the worktree for inspection; never post a stale completion.
5. Return the final report, changed-file and test evidence, and any PR link to
   support-center. Default to human review. Do not automatically merge or deploy.

Start with one active ticket across the VPS. Increase concurrency only after
measuring memory, disk, and repository build costs. Keep a separate credential
and repository allowlist entry for each enrolled project. The adapter's token
should not be included in agent prompts or child process environments.

The adapter is not implemented yet. Before implementing it, inspect the pinned
T3 executable's CLI/API schema and verify submit, status, cancellation, and
restart recovery against that exact release. Do not rely on guessed HTTP paths
or substitute a direct Codex process while reporting the job as T3-managed.

## Desktop work with CUA

`hosts/hgrai/home.nix` reuses the existing Cua Driver desktop pool for
`coding-agent`, without importing a physical desktop environment. The broker
starts with the lingering user manager. Two desktop slots start only when
leased; the shared legacy desktop does not start automatically. Each slot has
its own X11 display, Openbox session, accessibility bus, driver socket,
clipboard and disposable Chromium profile. The pool limits all desktop work
to 4 GiB RAM, 512 MiB swap and two CPUs of quota, with 2 GiB per slot.

Codex discovers the pinned CUA skills under `~/.agents/skills`. Home Manager
registers `cua-pool mcp` as its `cua-driver` MCP server using `codex mcp add`,
preserving other settings in the writable Codex config. New Codex sessions
launched by T3 inherit that configuration. Restart an existing Codex session
to discover the newly registered server; do not restart unrelated active work.
See [the official Codex MCP documentation](https://developers.openai.com/codex/mcp).

An MCP connection leases a desktop on its first GUI tool call and releases it
on disconnect or idle expiry. Coding-only sessions consume no desktop slot.
The installed desktop skill explains how to use manual leases across shell
calls; do not mix an unleased CLI with an MCP-owned desktop. Run commands as
the same service account:

```sh
sudo -iu coding-agent
export XDG_RUNTIME_DIR=/run/user/$(id -u)
codex mcp list
cua-pool status
cua-agent-smoke
cua-agent-browser-smoke --require-context-menu
cua-pool-smoke
```

These smoke checks use disposable local fixtures and release their own
desktops. No X11 or VNC TCP listener is opened: human viewing requires a
separate connection to the private VNC Unix socket, as described in
[the shared CUA guide](cua-driver.md). A T3 browser preview is separate from
this desktop. Pool slots isolate GUI state, not filesystem permissions between
tasks sharing `coding-agent`. ARM64 Cua remains an upstream preview; validate
native input, screenshots, browser interactions and release/recovery on hgrai
before assigning real desktop tasks.

The host enables NixOS's AT-SPI service. Without it, NixOS injects
`NO_AT_BRIDGE=1`, which disables GTK3 accessibility even inside a private
desktop bus. The CUA runtime also explicitly enables the accessibility bridge
and Chromium accessibility so existing lingering sessions do not retain a
disabled bridge. The browser smoke check accepts a still-open GTK file chooser
through its observed Open control or keyboard mnemonic, then requires the page
to confirm the uploaded filename.

## Validation before activation

Evaluate the host and build its ARM64 system without switching. Then apply the
reviewed configuration through the repository's usual deployment process.
Confirm service startup, loopback-only listening, SSH access, pairing, provider
authentication, persistence across a service restart, and one synthetic task
before enabling ticket intake. This setup has not been deployed by adding these
files.
