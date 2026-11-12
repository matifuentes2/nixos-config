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

`hosts/hgrai/support-bridge.nix` runs the support-center T3 bridge under a
separate `support-bridge` account. It pulls queued work over HTTPS, validates
the enrolled repository, and launches a T3-managed worktree per claim. The
support Worker needs no inbound path to this host. One active claim is allowed
per project token. Completed investigations return to human review; the bridge
never requests automatic resolution, merges, or deployments.

The private bridge source is pinned to a reviewed support-center commit. A
root enrollment unit fetches only its bridge files using `coding-agent`'s
existing GitHub login and installs an immutable versioned directory. No private
source or credentials enter the public Nix cache. Updating the bridge means
reviewing a new support-center commit and updating the pin here.

Provision a project-scoped support token with `tickets:read`, `tickets:write`,
and `jobs:claim` in `/var/lib/grai-support-bridge-secrets/support-token` (root,
0600; parent directory 0700). Keep its backup in the team's secret manager.
The units stay gated until that file exists. Do not put it in a Nix expression
or the Nix store. Enrollment obtains a scoped 30-day T3 OAuth session at
`auto-accept-edits` and discovers exact project mappings at runtime. It uses the
coding account's existing T3 login; no pairing code is printed or stored in Git.
The bridge drains before refreshing credentials with seven days remaining.

Codex and CUA run as `coding-agent`, which cannot read bridge credentials or
its SQLite state. Evidence is writable only by the bridge and readable by the
coding account. Both use the existing repository and CUA configuration;
filesystem isolation between coding tasks remains at the worktree level.

The support API and bundled CLI require the fresh `claim_id` for every lease
renewal, handoff, and completion. Persistent SQLite launch intent plus T3's
idempotency key recovers lost launch replies. The bridge renews leases each
ten-second cycle and limits a claim to thirty minutes. Cancellation, lease
loss, or a support outage stops the remote thread before proceeding. An
unconfirmed stop or ambiguous launch blocks new claims for operator review.
Human-input pauses remain leased and appear in the internal support timeline.
Worktrees, evidence, and reports remain available for review and archival.

Deploy the matching support Worker migration before activating this host:

```sh
sudo systemctl restart grai-support-bridge
sudo systemctl status grai-support-{repository,enrollment,bridge}
sudo journalctl -u grai-support-bridge -n 50 --no-pager
```

A graceful restart stops outstanding work and returns it to review. Crash
recovery resumes the persisted claim. Never delete the SQLite state or rotate
the T3 credential to bypass an ambiguous submission; reconcile the existing
thread first. Revoke the support token in Workspace settings to disable new
claims, stop the service to quiesce existing work, and retain artifacts for
review. The repository checkout and model/GitHub credentials stay in the
coding account's home; no credentials are passed in ticket prompts.

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
before enabling ticket intake. Adding these files alone does not activate enrollment; a scoped support token
and authenticated coding account are required.
