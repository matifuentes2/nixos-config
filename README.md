# NixOS configuration

This repository is the declarative source of truth for the `nixos` host and the
Home Manager configuration for user `pi`.

## Rebuild

```sh
sudo nixos-rebuild switch --flake /etc/nixos#nixos
```

`flake.lock` pins NixOS, nixpkgs, and Home Manager. Neovim is configured under
[`neovim/`](./neovim/); its plugins, parsers, language servers, formatters, and
debug adapters are supplied by Nix rather than downloaded at runtime.

## Desktop

Hyprland is configured under [`hyprland/`](./hyprland/) and starts from SDDM.
See the [Hyprland desktop guide](./docs/hyprland.md) for the complete keybind
reference. The main shortcuts use the Super key:

- `Super+Return`: terminal
- `Super+R`: application launcher
- `Super+E`: file manager
- `Super+Q`: close the focused window
- `Super+Ctrl+L`: lock the session
- `Super+Shift+E`: log out
- `Super+1` through `Super+0`: switch workspaces
- `Super+Shift+1` through `Super+Shift+0`: move a window to a workspace
- `Print`: copy a selected screenshot to the clipboard
