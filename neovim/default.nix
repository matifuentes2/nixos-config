{
  config,
  lib,
  pkgs,
  ...
}:

let
  inherit (pkgs) vimPlugins;

  mkLockedPlugin =
    {
      pname,
      owner,
      repo,
      rev,
      hash,
    }:
    pkgs.vimUtils.buildVimPlugin {
      inherit pname;
      version = builtins.substring 0 7 rev;
      src = pkgs.fetchFromGitHub {
        inherit
          owner
          repo
          rev
          hash
          ;
      };
    };

  # These three plugins are part of the imported config but are not packaged
  # by nixpkgs. Their revisions come from the imported lazy-lock.json.
  tailwindcssColorizerCmp = mkLockedPlugin {
    pname = "tailwindcss-colorizer-cmp.nvim";
    owner = "roobert";
    repo = "tailwindcss-colorizer-cmp.nvim";
    rev = "3d3cd95e4a4135c250faf83dd5ed61b8e5502b86";
    hash = "sha256-PIkfJzLt001TojAnE/rdRhgVEwSvCvUJm/vNPLSWjpY=";
  };

  telescopeTerraformDoc =
    (mkLockedPlugin {
      pname = "telescope-terraform-doc.nvim";
      owner = "ANGkeith";
      repo = "telescope-terraform-doc.nvim";
      rev = "28efe1f3cb2ed4c83fa69000ae8afd2f85d62826";
      hash = "sha256-ZMdsaW9wjmep0CMNCj8k2jSvV8aLMYmiOFm3iD8/pJw=";
    }).overrideAttrs
      {
        # Upstream derives this from its .git directory, which fixed-output Nix
        # sources intentionally omit. Avoid a noisy `git remote` failure on load.
        postPatch = ''
          printf '%s\n' 'lua vim.g.terraform_doc_git_namespace = "ANGkeith"' > plugin/init.vim
        '';
      };

  telescopeTerraform = mkLockedPlugin {
    pname = "telescope-terraform.nvim";
    owner = "cappyzawa";
    repo = "telescope-terraform.nvim";
    rev = "072c97023797ca1a874668aaa6ae0b74425335df";
    hash = "sha256-uXWW7ewAHZlTF1BDpwgCkB4969PD6K1T5kLte5CJvTg=";
  };

  treesitterWithDependencies = vimPlugins.nvim-treesitter.withPlugins (
    parsers: with parsers; [
      bash
      c
      diff
      dockerfile
      hcl
      html
      javascript
      jsdoc
      json
      json5
      lua
      luadoc
      luap
      markdown
      markdown_inline
      ninja
      prisma
      printf
      python
      query
      regex
      rst
      terraform
      toml
      tsx
      typescript
      vim
      vimdoc
      xml
      yaml
    ]
  );

  # nixpkgs exposes parsers and queries as plugin dependencies. Merge them into
  # the directory handed to lazy.nvim so they enter the runtime path together.
  treesitter = pkgs.symlinkJoin {
    name = "nvim-treesitter-with-parsers";
    paths = [ treesitterWithDependencies ] ++ treesitterWithDependencies.dependencies;
  };

  # Lazy still owns plugin configuration and lazy-loading, but every source is
  # supplied by Nix. The keys must match lazy.nvim's normalized plugin names.
  pluginSources = {
    "LazyVim" = vimPlugins.LazyVim;
    "LuaSnip" = vimPlugins.luasnip;
    "SchemaStore.nvim" = vimPlugins.SchemaStore-nvim;
    "blink.cmp" = vimPlugins.blink-cmp;
    "bufferline.nvim" = vimPlugins.bufferline-nvim;
    "catppuccin" = vimPlugins.catppuccin-nvim;
    "cmp-buffer" = vimPlugins.cmp-buffer;
    "cmp-nvim-lsp" = vimPlugins.cmp-nvim-lsp;
    "cmp-path" = vimPlugins.cmp-path;
    "cmp_luasnip" = vimPlugins.cmp_luasnip;
    "conform.nvim" = vimPlugins.conform-nvim;
    "dressing.nvim" = vimPlugins.dressing-nvim;
    "flash.nvim" = vimPlugins.flash-nvim;
    "flutter-tools.nvim" = vimPlugins.flutter-tools-nvim;
    "friendly-snippets" = vimPlugins.friendly-snippets;
    "fzf-lua" = vimPlugins.fzf-lua;
    "gitsigns.nvim" = vimPlugins.gitsigns-nvim;
    "grug-far.nvim" = vimPlugins.grug-far-nvim;
    "harpoon" = vimPlugins.harpoon2;
    "lazy.nvim" = vimPlugins.lazy-nvim;
    "lazydev.nvim" = vimPlugins.lazydev-nvim;
    "lualine.nvim" = vimPlugins.lualine-nvim;
    "markdown-preview.nvim" = vimPlugins.markdown-preview-nvim;
    "mason-lspconfig.nvim" = vimPlugins.mason-lspconfig-nvim;
    "mason-nvim-dap.nvim" = vimPlugins.mason-nvim-dap-nvim;
    "mason.nvim" = vimPlugins.mason-nvim;
    "mini.ai" = vimPlugins.mini-ai;
    "mini.icons" = vimPlugins.mini-icons;
    "mini.pairs" = vimPlugins.mini-pairs;
    "neo-tree.nvim" = vimPlugins.neo-tree-nvim;
    "neotest" = vimPlugins.neotest;
    "neotest-python" = vimPlugins.neotest-python;
    "noice.nvim" = vimPlugins.noice-nvim;
    "nui.nvim" = vimPlugins.nui-nvim;
    "nvim-cmp" = vimPlugins.nvim-cmp;
    "nvim-dap" = vimPlugins.nvim-dap;
    "nvim-dap-python" = vimPlugins.nvim-dap-python;
    "nvim-dap-ui" = vimPlugins.nvim-dap-ui;
    "nvim-dap-virtual-text" = vimPlugins.nvim-dap-virtual-text;
    "nvim-lint" = vimPlugins.nvim-lint;
    "nvim-lspconfig" = vimPlugins.nvim-lspconfig;
    "nvim-nio" = vimPlugins.nvim-nio;
    "nvim-snippets" = vimPlugins.nvim-snippets;
    "nvim-treesitter" = treesitter;
    "nvim-treesitter-textobjects" = vimPlugins.nvim-treesitter-textobjects;
    "nvim-ts-autotag" = vimPlugins.nvim-ts-autotag;
    "oil.nvim" = vimPlugins.oil-nvim;
    "persistence.nvim" = vimPlugins.persistence-nvim;
    "plenary.nvim" = vimPlugins.plenary-nvim;
    "render-markdown.nvim" = vimPlugins.render-markdown-nvim;
    "snacks.nvim" = vimPlugins.snacks-nvim;
    "tailwindcss-colorizer-cmp.nvim" = tailwindcssColorizerCmp;
    "telescope-terraform-doc.nvim" = telescopeTerraformDoc;
    "telescope-terraform.nvim" = telescopeTerraform;
    "telescope.nvim" = vimPlugins.telescope-nvim;
    "todo-comments.nvim" = vimPlugins.todo-comments-nvim;
    "tokyonight.nvim" = vimPlugins.tokyonight-nvim;
    "trouble.nvim" = vimPlugins.trouble-nvim;
    "ts-comments.nvim" = vimPlugins.ts-comments-nvim;
    "uv.nvim" = vimPlugins.uv-nvim;
    "venv-selector.nvim" = vimPlugins.venv-selector-nvim;
    "vim-fugitive" = vimPlugins.vim-fugitive;
    "which-key.nvim" = vimPlugins.which-key-nvim;
  };

  # Lazy's module loader identifies plugins by their directory basename. Nix
  # store derivation names include hashes and versions, so expose stable links
  # whose basenames exactly match lazy.nvim's normalized plugin names.
  pluginRoot = pkgs.linkFarm "nvim-lazy-plugins" (
    lib.mapAttrsToList (name: path: { inherit name path; }) pluginSources
  );

  pluginPathsLua = lib.concatStringsSep "\n" (
    lib.mapAttrsToList (
      name: _: "  [${builtins.toJSON name}] = ${builtins.toJSON "${pluginRoot}/${name}"},"
    ) pluginSources
  );

  jsDebugAdapter = pkgs.writeShellScriptBin "js-debug-adapter" ''
    exec ${lib.getExe pkgs.vscode-js-debug} "$@"
  '';

  # The imported Terraform tooling invokes `terraform`. Use the compatible,
  # open-source OpenTofu CLI rather than enabling HashiCorp's unfree package.
  terraformCompat = pkgs.writeShellScriptBin "terraform" ''
    exec ${lib.getExe pkgs.opentofu} "$@"
  '';
in
{
  # Keep the checked-in Lua configuration as the source of truth. init.lua is
  # generated below so Nix can inject immutable plugin store paths before Lazy
  # starts; it is equivalent to the imported one-line init.lua.
  xdg.configFile = {
    "nvim/lua" = {
      source = ./config/lua;
      recursive = true;
    };
    "nvim/lazyvim.json".source = ./config/lazyvim.json;
    "nvim/lazy-lock.json".source = ./config/lazy-lock.json;
    "nvim/.neoconf.json".source = ./config/.neoconf.json;
    "nvim/stylua.toml".source = ./config/stylua.toml;
  };

  programs.neovim = {
    enable = true;
    defaultEditor = true;
    viAlias = true;
    vimAlias = true;
    vimdiffAlias = true;
    withNodeJs = true;
    withPython3 = true;
    withRuby = false;

    initLua = ''
      -- Generated by Home Manager. Plugin versions and paths come from the
      -- flake-locked nixpkgs input, not from mutable runtime downloads.
      vim.g.nix_plugin_paths = {
      ${pluginPathsLua}
      }

      require("config.lazy")
    '';

    extraPackages =
      with pkgs;
      [
        # Core commands used by LazyVim and the imported plugins.
        fd
        fzf
        git
        lazygit
        nodejs
        ripgrep
        uv

        # Lua and shell tooling.
        lua-language-server
        shellcheck
        shfmt
        stylua

        # Python LSP, linting, virtual environments, and DAP.
        basedpyright
        python3Packages.debugpy
        ruff

        # Docker.
        docker-compose-language-service
        dockerfile-language-server
        hadolint

        # JSON and Markdown.
        markdown-toc
        markdownlint-cli2
        marksman
        prettier
        vscode-langservers-extracted

        # Prisma, Tailwind, Terraform, TOML, and TypeScript.
        prisma-language-server
        tailwindcss-language-server
        taplo
        terraformCompat
        terraform-ls
        tflint
        vtsls

        # JavaScript/TypeScript DAP expects this executable name.
        jsDebugAdapter

        # Required by flutter-tools.nvim. This also provides Dart.
        flutter
      ]
      ++ lib.optionals pkgs.stdenv.isLinux [
        # Clipboard providers used by the Linux desktop.
        pkgs.wl-clipboard
        pkgs.xclip
      ];
  };

  # LazyVim uses Nerd Font glyphs throughout its UI.
  fonts.fontconfig.enable = true;
  home.packages = [
    pkgs.git
    pkgs.nerd-fonts.jetbrains-mono
  ];
}
