# GlazeWM and Kanata on the WSL2 Windows host

Hyprland cannot run usefully under WSL2: there is no DRM device, so it can at
best run nested in a WSLg window with software rendering. Instead, the Windows
host underneath the `wsl2` flake output runs [GlazeWM](https://github.com/glzr-io/glazewm),
a tiling window manager configured to feel like this repository's Hyprland
desktop, and [Kanata](https://github.com/jtroo/kanata), a keyboard remapper that
ports the Mac's Karabiner-Elements tap/hold rules.

The setup has three tracked parts:

- [`hosts/wsl2/windows/glazewm.nix`](../hosts/wsl2/windows/glazewm.nix)
  generates GlazeWM's `config.yaml` from Nix, reusing the Hyprland palette.
- [`hosts/wsl2/windows/kanata.kbd`](../hosts/wsl2/windows/kanata.kbd) is the
  Kanata keymap.
- [`hosts/wsl2/windows/configuration.winget`](../hosts/wsl2/windows/configuration.winget)
  declares the Windows packages (GlazeWM, Zebar, Kanata, and T3 Code) as a WinGet
  configuration.

Every WSL2 Home Manager activation copies the configurations to
`%USERPROFILE%\.glzr\glazewm\config.yaml` and `%APPDATA%\kanata\kanata.kbd`.
The `windows-config-sync` command performs the same copy on demand. Edit the
tracked files, not the deployed copies: those are overwritten on each rebuild.

## Installation

1. Rebuild WSL2 so the configurations are written into the Windows profile:

   ```sh
   sudo nixos-rebuild switch --flake ~/nixos-config#wsl2
   ```

   If the activation prints a warning about Windows configs, run
   `windows-config-sync` from a WSL shell.

2. From PowerShell on Windows, apply the WinGet configuration. Substitute the
   WSL distribution and Linux user names if they differ:

   ```powershell
   winget configure -f \\wsl$\NixOS\home\matif\nixos-config\hosts\wsl2\windows\configuration.winget
   ```

3. Start GlazeWM from the Start menu. Enable its start-on-login option from the
   tray icon if you decide to keep it.

4. Start Kanata with the deployed keymap, and optionally add it to the Startup
   folder so it runs at login. The WinGet package ships several builds and no
   command alias; use the tray build with the default keyboard hook
   (`kanata_windows_gui_winIOv2_x64.exe`, no Interception driver needed):

   ```powershell
   $kanata = (Get-ChildItem "$env:LOCALAPPDATA\Microsoft\WinGet\Packages\jtroo.kanata_gui_*\kanata_windows_gui_winIOv2_x64.exe").FullName
   $config = "$env:APPDATA\kanata\kanata.kbd"
   Start-Process $kanata -ArgumentList "--cfg `"$config`""

   # Optional: start at login.
   $startup = [Environment]::GetFolderPath('Startup')
   $link = (New-Object -ComObject WScript.Shell).CreateShortcut("$startup\Kanata.lnk")
   $link.TargetPath = $kanata
   $link.Arguments = "--cfg `"$config`""
   $link.Save()
   ```

   After a rebuild changes the keymap, reload it from Kanata's tray icon.

## Keyboard remapping

| Key | Tap | Hold |
| --- | --- | --- |
| `Caps Lock` | `Esc` | `Ctrl` |
| `Left Shift+Caps Lock` | `Page Down` | |
| `Right Shift+Caps Lock` | Task View (`Win+Tab`) | |
| `Esc` | `Esc` | Hyper (`Ctrl+Alt+Shift`) |
| `Hyper+Tab` | `Shift+F1` (tmux prefix) | |
| `Space` | `Space` | `Win`, once another key is pressed and released |

Hyper omits `Win` because Windows reserves `Ctrl+Alt+Shift+Win` for Office.
A long `Space` hold with no other key still types a space, so it never opens
the Start menu by itself. Kanata's standard build cannot remap keys in windows
running as administrator unless Kanata itself runs elevated.

## GlazeWM key bindings

The left Windows key acts as `SUPER`. Bindings follow Hyprland wherever GlazeWM
has an equivalent.

| Keys | Action |
| --- | --- |
| `Win+Enter` | Windows Terminal |
| `Win+Shift+F` | File Explorer |
| `Win+W`, `Win+Q` | Close window |
| `Win+H/J/K`, `Win+arrows` | Focus window |
| `Win+Shift+H/J/K`, `Win+Shift+arrows` | Move window |
| `Win+1`…`Win+0` | Switch to workspace 1–10 |
| `Win+Shift+1`…`0` | Move window to workspace and follow |
| `Win+Shift+Alt+1`…`0` | Move window to workspace silently |
| `Win+Tab`, `Win+Shift+Tab` | Next or previous workspace |
| `Win+Ctrl+Tab` | Former workspace |
| `Win+T` | Toggle floating or tiling |
| `Win+F`, `Win+Alt+F` | Full screen, maximized |
| `Win+Ctrl+J` | Toggle tiling direction |
| `Win+-`, `Win+=` (add `Shift` for height) | Shrink or grow window |
| `Win+R` | Resize mode (HJKL or arrows, `Esc` to leave) |
| `Win+Shift+P` | Pause GlazeWM and return all keys to Windows |
| `Win+Shift+R` | Reload configuration |
| `Win+Shift+E` | Exit GlazeWM |

## Limitations

- Windows always handles `Win+L` (lock), so focusing right uses `Win+Right`.
- There is no equivalent of Hyprland groups, the scratchpad, or launcher
  bindings. Use the Start menu or PowerToys Command Palette to launch apps.
- GlazeWM ignores Linux GUI applications from WSLg (process `msrdc`), such as
  T3 Code. They are RDP RemoteApp windows: every resize round-trips through
  Weston and the Linux app, so tiling shows stale frames and fights Linux-side
  maximize, even with GPU rendering (enabled in `hosts/wsl2/default.nix`).
  Arrange them manually; the rule applies to windows opened after GlazeWM
  loads it. Prefer native Windows builds where they exist.
