-- NixOS owns plugin binaries, parsers, LSP servers, formatters, and debuggers.
-- Keep this conditional so the same Lua config remains usable on non-Nix hosts.
if type(vim.g.nix_plugin_paths) ~= "table" then
  return {}
end

return {
  -- Mason's mutable package store conflicts with a flake-locked setup. With
  -- mason-lspconfig absent, LazyVim configures and enables PATH-provided LSPs.
  { "mason-org/mason.nvim", enabled = false },
  { "mason-org/mason-lspconfig.nvim", enabled = false },
  { "jay-babu/mason-nvim-dap.nvim", enabled = false },

  -- Parsers are compiled by Nix and included in the Treesitter plugin output.
  {
    "nvim-treesitter/nvim-treesitter",
    build = false,
    opts = function(_, opts)
      opts.ensure_installed = {}
      opts.auto_install = false
      opts.install_dir = vim.g.nix_plugin_paths["nvim-treesitter"]
    end,
  },

  -- These build steps write into the plugin directory. Nix packages their
  -- generated artifacts ahead of time, and Nix store paths are read-only.
  { "L3MON4D3/LuaSnip", build = false },
  { "saghen/blink.cmp", build = false },
  { "iamcco/markdown-preview.nvim", build = false },
}
