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
