---
name: cua-agent-desktop
description: Required context for computer use on this Linux host. Use whenever you use cua-driver (CLI or MCP), computer use, or GUI automation here: it runs on a dedicated headless X11 agent desktop (DISPLAY=:47), not on the user's Hyprland screen. Read together with the cua-driver skill.
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
  - `cua-agent-run firefox --new-instance --profile <dir> <url> &`
  - `cua-agent-run chromium --user-data-dir=<dir> --force-renderer-accessibility <url> &`
  Use a scratch directory for `<dir>` unless the user names one. Electron and
  other single-instance apps need a separate profile or user-data directory too.
- Use `delivery_mode:"foreground"` for keyboard and pointer actions. This is
  authorized here: the agent desktop has its own pointer, focus, and
  clipboard, so it never interferes with the user.
- `set_window_frame` works for moving and sizing windows (screen 1920x1080).
- The user can watch or take over with `cua-agent-view`.
- Do not fall back to Playwright or other tools just because Wayland input
  failed elsewhere. That limitation is exactly what this desktop fixes.
- If `cua-driver call health_report` fails, check
  `systemctl --user status cua-agent-desktop cua-driver` and report it.
