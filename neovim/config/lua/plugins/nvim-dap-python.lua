return {
  "mfussenegger/nvim-dap-python",
  -- stylua: ignore
  keys = {
    { "<leader>dPt", function() require('dap-python').test_method() end, desc = "Debug Method", ft = "python" },
    { "<leader>dPc", function() require('dap-python').test_class() end, desc = "Debug Class", ft = "python" },
  },
  config = function()
    if vim.fn.has("win32") == 1 then
      require("dap-python").setup(LazyVim.get_pkg_path("debugpy", "/venv/Scripts/pythonw.exe"))
    elseif vim.fn.executable("debugpy-adapter") == 1 then
      -- On NixOS, debugpy is supplied declaratively by Home Manager.
      require("dap-python").setup("debugpy-adapter")
    else
      -- Preserve the original portable fallback for non-Nix systems.
      require("dap-python").setup("uv")
    end

    local dap = require("dap")

    local function project_root()
      -- Prefer git root; fallback to CWD
      local ok, out = pcall(vim.fn.systemlist, "git rev-parse --show-toplevel")
      if ok and out and out[1] and out[1] ~= "" then
        return out[1]
      end
      return vim.fn.getcwd()
    end

    local root = project_root()

    -- Ensure all python configs use the project root + PYTHONPATH
    for _, cfg in ipairs(dap.configurations.python or {}) do
      cfg.cwd = root
      cfg.env = vim.tbl_extend("force", cfg.env or {}, { PYTHONPATH = root })
      -- (optional) see all code including site-packages
      -- cfg.justMyCode = false
      -- (optional) use terminal for stdin
      -- cfg.console = "integratedTerminal"
    end
  end,
}
