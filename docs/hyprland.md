# Hyprland desktop

Hyprland is the default desktop session and starts from SDDM. The configuration
is managed through Home Manager in [`../hyprland/default.nix`](../hyprland/default.nix).

The **Super** modifier is usually the Windows key on a standard keyboard.

## Applications

| Keybind | Action |
| --- | --- |
| `Super+Return` | Open the Kitty terminal |
| `Super+R` | Open the Fuzzel application launcher |
| `Super+E` | Open the Thunar file manager |
| `Super+N` | Open the NetworkManager connection editor |
| `Super+Shift+V` | Open the PulseAudio volume control |

## Window management

| Keybind | Action |
| --- | --- |
| `Super+Q` | Close the focused window |
| `Super+F` | Toggle fullscreen |
| `Super+V` | Toggle floating mode |
| `Super+P` | Toggle pseudotiling for the focused window |
| `Super+T` | Toggle the split direction |
| `Super+H/J/K/L` | Focus the window left/down/up/right |
| `Super+Arrow keys` | Focus a window in the selected direction |
| `Super+Shift+H/J/K/L` | Move the focused window left/down/up/right |
| `Super+left mouse drag` | Move a window |
| `Super+right mouse drag` | Resize a window |

## Workspaces

| Keybind | Action |
| --- | --- |
| `Super+1` through `Super+9` | Switch to workspace 1 through 9 |
| `Super+0` | Switch to workspace 10 |
| `Super+Shift+1` through `Super+Shift+9` | Move the focused window to workspace 1 through 9 |
| `Super+Shift+0` | Move the focused window to workspace 10 |

## Session controls

| Keybind | Action |
| --- | --- |
| `Super+Ctrl+L` | Lock the session |
| `Super+Shift+E` | Log out immediately without confirmation |

Hypridle locks the session after 10 minutes of inactivity and turns off the
displays one minute later. Activity turns the displays back on.

## Screenshots

| Keybind | Action |
| --- | --- |
| `Print` | Select an area and copy the screenshot to the clipboard |
| `Shift+Print` | Select an area and save the screenshot |

## Media keys

The standard keyboard media keys are configured for:

- Raising, lowering, and muting output volume
- Muting the microphone
- Raising and lowering display brightness
- Playing or pausing media
- Selecting the next or previous track

## Applying configuration changes

After editing the declarative configuration, rebuild the host with:

```sh
sudo nixos-rebuild switch --flake /etc/nixos#nixos
```
