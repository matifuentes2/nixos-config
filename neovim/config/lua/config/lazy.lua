local nix_plugins = vim.g.nix_plugin_paths
local nix_managed = type(nix_plugins) == "table"
local lazypath = nix_managed and nix_plugins["lazy.nvim"] or (vim.fn.stdpath("data") .. "/lazy/lazy.nvim")

-- Keep the upstream bootstrap path for non-Nix systems. On NixOS, Home
-- Manager injects lazy.nvim and every other plugin from the Nix store.
if not (vim.uv or vim.loop).fs_stat(lazypath) then
  if nix_managed then
    error("Nix-managed lazy.nvim is missing at " .. tostring(lazypath))
  end

  local lazyrepo = "https://github.com/folke/lazy.nvim.git"
  local out = vim.fn.system({ "git", "clone", "--filter=blob:none", "--branch=stable", lazyrepo, lazypath })
  if vim.v.shell_error ~= 0 then
    vim.api.nvim_echo({
      { "Failed to clone lazy.nvim:\n", "ErrorMsg" },
      { out, "WarningMsg" },
      { "\nPress any key to exit..." },
    }, true, {})
    vim.fn.getchar()
    os.exit(1)
  end
end
vim.opt.rtp:prepend(lazypath)

require("lazy").setup({
  spec = {
    -- add LazyVim and import its plugins
    { "LazyVim/LazyVim", import = "lazyvim.plugins" },
    -- import/override with your plugins
    { import = "plugins" },
  },
  defaults = {
    -- By default, only LazyVim plugins will be lazy-loaded. Your custom plugins load during startup.
    lazy = false,
    version = false,
  },
  -- Resolve all plugins to immutable paths supplied by Home Manager. An
  -- undeclared plugin is a configuration error instead of a runtime download.
  dev = nix_managed and {
    patterns = { "" },
    fallback = false,
    path = function(plugin)
      local path = nix_plugins[plugin.name]
      if not path and (plugin.optional or plugin.enabled == false) then
        -- LazyVim uses optional/disabled specs to augment or replace plugins.
        -- Keep those absent unless another enabled spec includes them.
        return "/dev/null/nix-optional/" .. plugin.name
      end
      if not path then
        error(("Plugin %q is not declared in neovim/default.nix"):format(plugin.name))
      end
      return path
    end,
  } or nil,
  install = {
    missing = not nix_managed,
    colorscheme = { "tokyonight", "habamax" },
  },
  checker = {
    enabled = not nix_managed,
    notify = false,
  },
  change_detection = {
    enabled = not nix_managed,
    notify = false,
  },
  pkg = { enabled = not nix_managed },
  rocks = { enabled = not nix_managed },
  performance = {
    rtp = {
      -- disable some rtp plugins
      disabled_plugins = {
        "gzip",
        -- "matchit",
        -- "matchparen",
        -- "netrwPlugin",
        "tarPlugin",
        "tohtml",
        "tutor",
        "zipPlugin",
      },
    },
  },
})
