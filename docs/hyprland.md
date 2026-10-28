# Hyprland desktop

Hyprland is the default desktop session on the Raspberry Pi and the Lenovo
Legion Y720 and starts from SDDM. The WSL2 host does not import this module.
The configuration is managed through Home Manager in
[`../hyprland/`](../hyprland/) and follows
[Omarchy](https://github.com/basecamp/omarchy)'s look and keybindings: the
Tokyo Night palette, square corners, an icon-only Waybar, a centered launcher,
and an on-screen display for volume and brightness.

| File | Contents |
| --- | --- |
| [`default.nix`](../hyprland/default.nix) | Hyprland Lua configuration, keybindings, and helper scripts |
| [`desktop.nix`](../hyprland/desktop.nix) | Kitty, Fuzzel, Mako, SwayOSD, Hyprpaper, Hyprlock, Hypridle, and GTK theming |
| [`waybar.nix`](../hyprland/waybar.nix) | Waybar layout and style |
| [`palette.nix`](../hyprland/palette.nix) | Tokyo Night colors shared by every component |

Hyprland 0.57 removed the hyprlang `hyprland.conf` format, so Home Manager
generates `~/.config/hypr/hyprland.lua` and loads the files under
`~/.config/hypr/desktop/`.

## Versions

The Lenovo Legion Y720 runs the Hyprland release pinned by the `hyprland`
flake input, currently v0.57.0, through
[`modules/system/hyprland-upstream.nix`](../modules/system/hyprland-upstream.nix).
That module adds Hyprland's Cachix substituter. Cachix only publishes x86-64
binaries, so the Raspberry Pi keeps the Hyprland package from the system
nixpkgs instead of compiling Hyprland locally.

Do not replace the system Mesa with the one from Hyprland's nixpkgs. When that
revision uses a newer glibc than the system, programs built against the system
nixpkgs cannot load its drivers, and SDDM's greeter exits to a black screen.

The running system only trusts Hyprland's Cachix after a configuration that
declares it has been activated. Pass the substituter explicitly for the first
switch so that Hyprland is downloaded instead of compiled:

```sh
sudo nixos-rebuild switch --flake /etc/nixos#amd64-lenovo-legion-y720 \
  --option extra-substituters https://hyprland.cachix.org \
  --option extra-trusted-public-keys hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIBMioiJM7ypFP8PwtkuGc=
```

To upgrade Hyprland, change the tag in the `hyprland` input of
[`flake.nix`](../flake.nix) and run `nix flake lock`.

## Displays

On the Lenovo, `nwg-displays` owns `~/.config/hypr/monitors.lua` and
`~/.config/hypr/workspaces.lua`. Home Manager seeds empty files only when they
are absent. Layouts saved by older versions in `monitors.conf` are not read;
apply the layout again from `nwg-displays` to write the Lua files.

The **Super** modifier is usually the Windows key on a standard keyboard. Press
`Super+/` to search every binding below.

## Applications

| Keybind | Action |
| --- | --- |
| `Super+Return` | Open the Kitty terminal |
| `Super+Space` | Open the Fuzzel application launcher |
| `Super+Alt+Space` | Switch to an open window |
| `Super+Shift+B` | Open Firefox |
| `Super+Shift+F` | Open the Thunar file manager |
| `Super+Shift+T` | Open btop |

## Menus and utilities

| Keybind | Action |
| --- | --- |
| `Super+Escape` | Open the system menu: lock, suspend, log out, restart, or shut down |
| `Super+/` | Show the keybindings |
| `Super+Ctrl+V` | Pick an entry from the clipboard history |
| `Super+Ctrl+A` | Open the PulseAudio volume control |
| `Super+Ctrl+N` | Open the NetworkManager connection editor |
| `Super+Ctrl+I` | Toggle locking when idle |
| `Super+Ctrl+L` | Lock the session |
| `Super+Shift+Space` | Toggle the top bar |
| `Super+Shift+E` | Log out immediately without confirmation |

## Notifications

| Keybind | Action |
| --- | --- |
| `Super+,` | Dismiss the last notification |
| `Super+Shift+,` | Dismiss all notifications |
| `Super+Alt+,` | Restore the last dismissed notification |
| `Super+Ctrl+,` | Toggle do not disturb |

## Window management

| Keybind | Action |
| --- | --- |
| `Super+W` or `Super+Q` | Close the focused window |
| `Super+F` | Toggle fullscreen |
| `Super+Alt+F` | Toggle full width |
| `Super+T` | Toggle floating mode |
| `Super+P` | Toggle pseudotiling for the focused window |
| `Super+Ctrl+J` | Toggle the split direction |
| `Super+H/J/K/L` or `Super+Arrow keys` | Focus a window in the selected direction |
| `Super+Shift+H/J/K/L` | Move the focused window in the selected direction |
| `Super+Shift+Arrow keys` | Swap the focused window in the selected direction |
| `Alt+Tab` / `Alt+Shift+Tab` | Focus the next or previous window |
| `Super+-` / `Super+=` | Widen or narrow the focused window |
| `Super+Shift+-` / `Super+Shift+=` | Shorten or lengthen the focused window |
| `Super+left mouse drag` | Move a window |
| `Super+right mouse drag` | Resize a window |

## Groups

| Keybind | Action |
| --- | --- |
| `Super+G` | Toggle grouping for the focused window |
| `Super+Alt+G` | Move the focused window out of its group |
| `Super+Alt+Arrow keys` | Move the focused window into the group in that direction |
| `Super+Alt+Tab` / `Super+Alt+Shift+Tab` | Focus the next or previous window in the group |

## Workspaces

| Keybind | Action |
| --- | --- |
| `Super+1` through `Super+9`, `Super+0` | Switch to workspace 1 through 10 |
| `Super+Shift+1` through `Super+Shift+0` | Move the focused window to that workspace and follow it |
| `Super+Shift+Alt+1` through `Super+Shift+Alt+0` | Move the focused window to that workspace silently |
| `Super+Tab` / `Super+Shift+Tab` | Switch to the next or previous workspace |
| `Super+Ctrl+Tab` | Switch to the previously used workspace |
| `Super+scroll` | Cycle through workspaces |
| `Super+S` | Toggle the scratchpad |
| `Super+Alt+S` | Move the focused window to the scratchpad |
| Three-finger horizontal swipe | Switch workspaces on a touchpad |

Hypridle locks the session after five minutes of inactivity and turns off the
displays 30 seconds later. Activity turns the displays back on. Red indicators
next to the clock show when idle locking is disabled or notifications are
silenced.

## Screenshots

| Keybind | Action |
| --- | --- |
| `Print` | Select an area and copy the screenshot to the clipboard |
| `Shift+Print` | Select an area, copy it, and save it |
| `Ctrl+Print` | Copy and save the current display |
| `Super+Print` | Pick a color from the screen |

## Media keys

The standard keyboard media keys are configured for:

- Raising, lowering, and muting output volume, with an on-screen display
- Muting the microphone
- Raising and lowering display brightness, with an on-screen display
- Playing or pausing media
- Selecting the next or previous track

## Applying configuration changes

After editing the declarative configuration, rebuild the host with:

```sh
# Raspberry Pi
sudo nixos-rebuild switch --flake /etc/nixos#nixos
# Lenovo Legion Y720
sudo nixos-rebuild switch --flake /etc/nixos#amd64-lenovo-legion-y720
```
