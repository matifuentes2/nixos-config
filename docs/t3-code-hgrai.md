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

## Validation before activation

Evaluate the host and build its ARM64 system without switching. Then apply the
reviewed configuration through the repository's usual deployment process.
Confirm service startup, loopback-only listening, SSH access, pairing, provider
authentication, persistence across a service restart, and one synthetic task
before enabling ticket intake. This setup has not been deployed by adding these
files.
