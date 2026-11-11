---
name: cua-agent-desktop
description: >-
  Host context for native GUI automation with cua-driver on the isolated X11
  agent desktop. Read alongside cua-driver when operating applications here;
  the target is DISPLAY=:47, separate from the user's Hyprland screen.
---

# Cua agent desktop (Linux)

On this host, cua-driver operates a dedicated, headless X11 desktop
(`DISPLAY=:47`, Xvnc + Openbox), **not** the user's Hyprland session.

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
- The user can watch or take over with `cua-agent-view`.
- Native Cua and T3 preview are separate browser environments. Use the one
  requested by the user; a T3 preview tab does not appear on this desktop.
- If `cua-driver call health_report` fails, check
  `systemctl --user status cua-agent-desktop cua-driver` and report it.
