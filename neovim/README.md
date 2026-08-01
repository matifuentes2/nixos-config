# Neovim on NixOS

The Lua configuration in `config/` was imported from only the
`nvim/.config/nvim` subtree of
[`matifuentes2/dotfiles`](https://github.com/matifuentes2/dotfiles), commit
`a46b316058a6abeedc2b04b4469b80e6d26ec5c6` (2026-07-23).

`default.nix` adapts that macOS-oriented LazyVim setup for a reproducible NixOS
Home Manager configuration:

- Home Manager deploys the checked-in Lua files.
- Plugins come from the flake-locked nixpkgs revision; the three plugins absent
  from nixpkgs are fixed-output derivations pinned to the imported lock file.
- Treesitter parsers, LSPs, formatters, linters, and DAP adapters come from Nix.
- Lazy.nvim still handles configuration and lazy-loading, but plugin install,
  update checks, package rocks, and runtime downloads are disabled on NixOS.
- Mason is disabled because its mutable package store is not reproducible.

The imported `lazy-lock.json` is retained for provenance and non-Nix use. On
NixOS, `flake.lock` is authoritative for package/plugin versions.
