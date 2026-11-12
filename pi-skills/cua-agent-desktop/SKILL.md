---
name: cua-agent-desktop
description: >-
  Host context for native GUI automation on isolated X11 desktops, including
  concurrent leased desktops when cua-pool is installed. Read alongside
  cua-driver when operating GUI applications on this Linux host.
---

# Cua agent desktop (Linux)

Cua operates private X11 desktops, **not** the user's Hyprland session.

## Concurrent tasks (when `cua-pool` is installed)

- Lease one desktop for the whole GUI task. Different Cua session IDs do not
  separate focus or clipboards on the same desktop.
- If `CUA_POOL_LEASE` is already set, `cua-driver` and `cua-agent-*` helpers
  route to that lease automatically. Do not override its driver socket.
- Otherwise, acquire on demand with `cua-pool acquire --name <task> --wait 60`.
  Keep the returned `lease` value across tool calls. Use
  `cua-pool call <lease> <tool> '<json>'`, `cua-pool run <lease> -- <command>`,
  and `cua-pool browser <lease> <url>`. Release it with
  `cua-pool release <lease>` when finished, including after failure.
- Alternatively, `cua-pool exec --name <task> -- <command>` leases a desktop
  for an entire command/agent process, renews it automatically and releases it
  on exit. Wrap only work that needs GUI access so idle coding tasks need no slot.
- The configured Pi MCP server leases lazily on its first tool call. Discovery
  does not consume a desktop. Call `pool_release_desktop` when GUI work is done.
  An automatically owned desktop also expires after ten idle minutes with no
  pending requests; ping and discovery do not keep it alive. After expiry the
  next GUI call reports lost state without acting. Retry with fresh window
  discovery, never stale window/session handles. Explicit release allows fresh
  acquisition on the next call. Native `end_session` does not release the lease.
  Use `launch_app` for apps on that MCP desktop; do not mix its tools with
  unleased CLI calls. Starting MCP inside `cua-pool exec` reuses the existing lease;
  MCP idle expiry and release never release that parent-owned lease.
- Manual leases expire after the configured idle interval (one hour by default).
  Each call renews it; use `cua-pool renew <lease>` during long pauses. Expired
  tokens and restarted desktops refuse further actions: acquire a fresh lease
  and observe from scratch. Never silently resume old window handles.
- Each desktop has separate focus, clipboard, D-Bus, Xauthority, driver socket,
  browser profile, caches and task directories. Profiles are discarded on release;
  task files and downloads are preserved. Never reuse another lease's profile.
- Pool exhaustion is explicit; wait boundedly or finish an owned task. Do not
  release another task or fall back to the shared desktop to evade capacity.
- `cua-pool status` lists occupied slots. The human can watch a manual lease
  using `cua-pool view <lease>` or any active slot using
  `cua-pool view --slot <number>` from their ordinary graphical terminal.
- This separates GUI state, not Unix file permissions: all slots use the same
  user. Coordinate edits to shared files separately.

## Legacy desktop and common GUI guidance

Without a lease, existing CLI helpers still target the shared legacy desktop
(`DISPLAY=:47`, Xvnc + Openbox). Reserve that path for intentional single-task use.
Unleased driver `call` commands require `CUA_LEGACY_DESKTOP=1` to select this
shared desktop explicitly. The two smoke commands automatically lease a pool
desktop unless that legacy flag is set. Do not use the flag to evade pool capacity.

- The user's own windows are not visible or controllable. `list_windows`,
  screenshots, and input only cover the agent desktop. Do not try to reach
  the user's screen.
- Start apps there with cua-driver `launch_app`, or from a shell with
  `cua-agent-run <command> &`. Apps started any other way open on Hyprland.
- Browsers must use an isolated profile, or they hand off to the user's
  running instance on Hyprland:
  - Prefer `cua-agent-browser <url>` for Chromium. It forces X11, enables
    renderer accessibility, and uses a profile reserved for this desktop.
  - `cua-agent-run firefox --new-instance --profile <dir> <url> &`
  - `cua-agent-run chromium --user-data-dir=<dir> --force-renderer-accessibility <url> &`
  Use a scratch directory for `<dir>` unless the user names one. Electron and
  other single-instance apps need a separate profile or user-data directory too.
- Use `delivery_mode:"foreground"` for keyboard and pointer actions. This is
  authorized here: the agent desktop has its own pointer, focus, and
  clipboard, so it never interferes with the user.
- The desktop also has a private D-Bus/AT-SPI session. `cua-agent-run` reads
  its current address; do not replace it with the user's session bus.
- `cua-agent-editor <file>` opens Mousepad here without reusing another
  instance. `cua-agent-smoke` checks discovery, accessible editing, keyboard
  delivery, capture and submission in a disposable dialog.
- `set_window_frame` works for moving and sizing windows (screen 1920x1080).
- `cua-agent-browser-smoke` checks the local browser fixture with a disposable
  profile, verified file transfers and repeated input. Context-menu accessibility
  is reported separately; use `--require-context-menu` to make it mandatory.
- After opening a popup, inspect its returned `popup.window_id`, or call
  `get_window_state` with the browser pid and no window id to discover it.
  The main window's tree can omit the popup. If its controls remain absent,
  use a fresh popup screenshot; never treat an input acknowledgement as proof.
- The user can watch or take over with `cua-agent-view`.
- Native Cua and T3 preview are separate browser environments. Use the one
  requested by the user; a T3 preview tab does not appear on this desktop.
- If `cua-driver call health_report` fails, check
  `systemctl --user status cua-agent-desktop cua-driver` and report it.
