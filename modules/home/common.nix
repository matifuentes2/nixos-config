{
  config,
  lib,
  pkgs,
  nixpkgs-unstable,
  herdr,
  herdr-worktrunk,
  herdr-collie,
  mcp-nixos,
  ...
}:

let
  unstable = import nixpkgs-unstable {
    system = pkgs.stdenv.hostPlatform.system;
  };
  upstreamPi = unstable.pi-coding-agent;

  # Run the unmodified upstream CLI with its supported Bun runtime. This avoids
  # Node's large ESM startup cost without maintaining a Pi fork.
  pi = pkgs.writeShellApplication {
    name = "pi";
    runtimeInputs = [
      pkgs.fd
      pkgs.ripgrep
    ];
    text = ''
      export PI_SKIP_VERSION_CHECK="''${PI_SKIP_VERSION_CHECK-1}"
      export PI_TELEMETRY="''${PI_TELEMETRY-0}"

      if [[ -z "''${BUN_RUNTIME_TRANSPILER_CACHE_PATH+x}" ]]; then
        cache_root="''${XDG_CACHE_HOME:-$HOME/.cache}"
        export BUN_RUNTIME_TRANSPILER_CACHE_PATH="$cache_root/bun/runtime-transpiler"
      fi

      exec -a "$0" ${lib.getExe pkgs.bun} \
        ${upstreamPi}/lib/node_modules/pi-monorepo/dist/bun/cli.js "$@"
    '';
  };

  piExtensions = pkgs.buildNpmPackage {
    pname = "pi-extensions";
    version = "1.0.0";
    src = ../../pi-extensions;
    npmDepsHash = "sha256-Kdl8pSx/CO1eHFFsKekGQaHXcaX3gkfkGemT0AVzYOo=";
    dontNpmBuild = true;
    npmFlags = [ "--omit=peer" ];
    nativeBuildInputs = [ pkgs.esbuild ];

    # Bundle large TypeScript extension graphs once during the Nix build so Pi
    # does not transpile and resolve them on every startup. Keep Pi's own API
    # packages external so every extension uses the instances owned by Pi.
    postInstall = ''
      extensions="$out/lib/node_modules/pi-extensions/node_modules"
      upstream_node_modules="${upstreamPi}/lib/node_modules/pi-monorepo/node_modules"
      common=(
        --bundle
        --platform=node
        --format=esm
        --target=node20
        --minify-syntax
        --minify-whitespace
      )

      esbuild "$extensions/pi-mcp-adapter/index.ts" \
        "''${common[@]}" \
        '--external:@earendil-works/*' \
        --external:@napi-rs/keyring \
        --external:open \
        --outfile="$extensions/pi-mcp-adapter/index.bundle.mjs"

      esbuild "$extensions/pi-vim/index.ts" \
        "''${common[@]}" \
        --packages=external \
        --outfile="$extensions/pi-vim/index.bundle.mjs"

      esbuild "$extensions/pi-zentui/extensions/zentui/index.ts" \
        "''${common[@]}" \
        --packages=external \
        --outfile="$extensions/pi-zentui/index.bundle.mjs"

      mkdir -p "$extensions/@earendil-works"
      ln -s "$upstream_node_modules/@earendil-works/pi-agent-core" \
        "$extensions/@earendil-works/pi-agent-core"
      ln -s "$upstream_node_modules/@earendil-works/pi-ai" \
        "$extensions/@earendil-works/pi-ai"
      ln -s "${upstreamPi}/lib/node_modules/pi-monorepo" \
        "$extensions/@earendil-works/pi-coding-agent"
      ln -s "$upstream_node_modules/@earendil-works/pi-tui" \
        "$extensions/@earendil-works/pi-tui"

      # pi-web-access intentionally remains unbundled: bundling eagerly loads
      # its optional extractor graph and was slower in startup benchmarks.
      # pi-subagents also stays unbundled because its background runner resolves
      # helper scripts relative to the original source-module locations.
    '';
  };

  chromeExecutable =
    if pkgs.stdenv.isDarwin then
      "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
    else
      lib.getExe pkgs.chromium;

  chromeDevtoolsMcp = pkgs.writeShellApplication {
    name = "chrome-devtools-mcp";
    runtimeInputs = lib.optionals pkgs.stdenv.isLinux [ pkgs.chromium ];
    text = ''
      export CHROME_DEVTOOLS_MCP_NO_UPDATE_CHECKS=1
      export CHROME_DEVTOOLS_MCP_NO_USAGE_STATISTICS=1

      exec ${lib.getExe pkgs.nodejs_22} \
        ${piExtensions}/lib/node_modules/pi-extensions/node_modules/chrome-devtools-mcp/build/src/bin/chrome-devtools-mcp.js \
        --executable-path=${lib.escapeShellArg chromeExecutable} \
        --isolated \
        --no-performance-crux \
        "$@"
    '';
  };
in
{
  imports = [
    ../../neovim
  ];

  # Packages installed only for this user.
  home.packages = with pkgs; [
    ripgrep
    fd
    jq
    fzf
    bun
    uv
    devenv
    worktrunk
    pi
    chromeDevtoolsMcp
    herdr.packages.${pkgs.stdenv.hostPlatform.system}.default
    mcp-nixos.packages.${pkgs.stdenv.hostPlatform.system}.default
  ];

  home.sessionVariables = {
    EDITOR = "nvim";
    VISUAL = "nvim";
  };

  # Herdr's plugin registry is mutable state, so register the pinned plugin
  # source on every Home Manager activation. This is idempotent and avoids a
  # network-backed `herdr plugin install`.
  home.activation.linkHerdrWorktrunk = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    run ${lib.getExe herdr.packages.${pkgs.stdenv.hostPlatform.system}.default} \
      plugin link ${herdr-worktrunk} --enabled
  '';

  # Collie's build writes generated assets into its checkout. Copy the pinned
  # flake source to mutable user state before linking it into Herdr.
  home.activation.linkHerdrCollie = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    collie_dir="$HOME/.local/share/herdr-collie"
    run rm -rf "$collie_dir"
    run cp -R ${herdr-collie} "$collie_dir"
    run chmod -R u+w "$collie_dir"
    run ${lib.getExe herdr.packages.${pkgs.stdenv.hostPlatform.system}.default} \
      plugin link "$collie_dir" --enabled
    run ${lib.getExe herdr.packages.${pkgs.stdenv.hostPlatform.system}.default} \
      plugin action invoke restart --plugin herdr.collie
  '';

  xdg.configFile."herdr/config.toml" = {
    force = true;
    text = ''
      onboarding = false

      [theme]
      name = "tokyo-night"
      auto_switch = false

      # Worktrunk plugin keybindings recommended by its README.
      [[keys.command]]
      key = "prefix+shift+g"
      type = "plugin_action"
      command = "worktrunk.open"
      description = "Worktree: switch / create from default branch"

      [[keys.command]]
      key = "prefix+shift+c"
      type = "plugin_action"
      command = "worktrunk.open-current"
      description = "Worktree: switch / create from current branch"

      [[keys.command]]
      key = "prefix+shift+d"
      type = "plugin_action"
      command = "worktrunk.remove"
      description = "Worktree: remove"
    '';
  };

  # Pi loads this locally built package from the immutable Nix store. Its npm
  # dependency graph is pinned by pi-extensions/package-lock.json.
  home.file.".pi/agent/settings.json" = {
    force = true;
    text = builtins.toJSON {
      lastChangelogVersion = "0.83.0";
      theme = "dark";
      defaultProvider = "openai-codex";
      defaultModel = "gpt-5.6-sol";
      defaultThinkingLevel = "minimal";
      packages = [ "${piExtensions}/lib/node_modules/pi-extensions" ];
    };
  };

  # Install Pi agent skills declaratively from pinned or tracked sources.
  home.file.".pi/agent/skills/herdr/SKILL.md".source = "${herdr}/skills/herdr/SKILL.md";
  home.file.".pi/agent/skills/devenv-setup/SKILL.md".source = ../../pi-skills/devenv-setup/SKILL.md;

  # pi-mcp-adapter reads this configuration and starts each pinned server only
  # when one of its tools is first used.
  home.file.".pi/agent/mcp.json" = {
    force = true;
    text = builtins.toJSON {
      mcpServers = {
        chrome-devtools = {
          command = lib.getExe chromeDevtoolsMcp;
          args = [ ];
          lifecycle = "lazy";
        };
        nixos = {
          command = lib.getExe mcp-nixos.packages.${pkgs.stdenv.hostPlatform.system}.default;
          args = [ ];
          lifecycle = "lazy";
        };
      };
    };
  };

  programs.mise = {
    enable = true;
    enableBashIntegration = true;
    enableZshIntegration = true;
  };

  programs.direnv = {
    enable = true;
    enableBashIntegration = true;
    enableZshIntegration = true;
    nix-direnv.enable = true;
  };

  programs.zoxide = {
    enable = true;
    enableBashIntegration = true;
    enableZshIntegration = true;
  };

  home.shellAliases = {
    ll = "ls -alh";
    la = "ls -A";
    gs = "git status";
  };

  programs.bash = {
    enable = true;

    # Put Bash-specific functions and other interactive setup here.
    initExtra = ''
      set -o vi

      # Example:
      # mkcd() { mkdir -p "$1" && cd "$1"; }
    '';
  };

  # Ported from https://github.com/matifuentes2/dotfiles.
  programs.starship = {
    enable = true;
    enableBashIntegration = true;
    enableZshIntegration = true;

    settings = {
      format = lib.concatStrings [
        "[░▒▓](#a3aed2)"
        "[  ](bg:#a3aed2 fg:#090c0c)"
        "[](bg:#3f5683 fg:#a3aed2)"
        "$directory"
        "[](fg:#3f5683 bg:#394260)"
        "$git_branch"
        "$git_status"
        "[](fg:#394260 bg:#212736)"
        "$nodejs"
        "$rust"
        "$golang"
        "$php"
        "[](fg:#212736 bg:#1d2230)"
        "$time"
        "[ ](fg:#1d2230)"
        "\n$character"
      ];

      directory = {
        style = "fg:#e3e5e5 bg:#3f5683";
        format = "[ $path ]($style)";
        truncation_length = 3;
        truncation_symbol = "…/";
        substitutions = {
          Documents = "󰈙 ";
          Downloads = " ";
          Music = " ";
          Pictures = " ";
        };
      };

      git_branch = {
        symbol = "";
        style = "bg:#394260";
        format = "[[ $symbol $branch ](fg:#769ff0 bg:#394260)]($style)";
      };

      git_status = {
        style = "bg:#394260";
        format = "[[($all_status$ahead_behind )](fg:#769ff0 bg:#394260)]($style)";
      };

      nodejs = {
        symbol = "";
        style = "bg:#212736";
        format = "[[ $symbol ($version) ](fg:#769ff0 bg:#212736)]($style)";
      };

      rust = {
        symbol = "";
        style = "bg:#212736";
        format = "[[ $symbol ($version) ](fg:#769ff0 bg:#212736)]($style)";
      };

      golang = {
        symbol = "";
        style = "bg:#212736";
        format = "[[ $symbol ($version) ](fg:#769ff0 bg:#212736)]($style)";
      };

      php = {
        symbol = "";
        style = "bg:#212736";
        format = "[[ $symbol ($version) ](fg:#769ff0 bg:#212736)]($style)";
      };

      time = {
        disabled = false;
        time_format = "%R";
        style = "bg:#1d2230";
        format = "[[  $time ](fg:#a0a9cb bg:#1d2230)]($style)";
      };

      character.vicmd_symbol = if pkgs.stdenv.isDarwin then " >" else "N >";
    };
  };

  # Lets Home Manager manage itself for this user.
  programs.home-manager.enable = true;
}
