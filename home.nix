{
  config,
  lib,
  pkgs,
  herdr,
  herdr-worktrunk,
  herdr-collie,
  mcp-nixos,
  ...
}:

let
  piExtensions = pkgs.buildNpmPackage {
    pname = "pi-extensions";
    version = "1.0.0";
    src = ./pi-extensions;
    npmDepsHash = "sha256-FJiHY17b9uB8ycVM5x/fniYRnyvBBqYnj9cU/tgF2t8=";
    dontNpmBuild = true;
    npmFlags = [ "--omit=peer" ];
    nativeBuildInputs = [ pkgs.esbuild ];

    # Bundle large TypeScript extension graphs once during the Nix build so Pi
    # does not transpile and resolve them on every startup. Keep Pi's own API
    # packages external so every extension uses the instances owned by Pi.
    postInstall = ''
      extensions="$out/lib/node_modules/pi-extensions/node_modules"
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

      # pi-web-access intentionally remains unbundled: bundling eagerly loads
      # its optional extractor graph and was slower in startup benchmarks.
    '';
  };
in
{
  imports = [
    ./hyprland
    ./neovim
  ];

  home.username = "pi";
  home.homeDirectory = "/home/pi";

  # Keep this at the version used when Home Manager was first configured.
  home.stateVersion = "25.11";

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
  home.file.".pi/agent/skills/herdr/SKILL.md".source =
    "${herdr}/skills/herdr/SKILL.md";
  home.file.".pi/agent/skills/devenv-setup/SKILL.md".source =
    ./pi-skills/devenv-setup/SKILL.md;

  # pi-mcp-adapter reads this configuration and starts the pinned server only
  # when its tools are first used.
  home.file.".pi/agent/mcp.json" = {
    force = true;
    text = builtins.toJSON {
      mcpServers.nixos = {
        command = lib.getExe mcp-nixos.packages.${pkgs.stdenv.hostPlatform.system}.default;
        args = [ ];
        lifecycle = "lazy";
      };
    };
  };

  programs.mise = {
    enable = true;
    enableBashIntegration = true;
  };

  programs.direnv = {
    enable = true;
    enableBashIntegration = true;
    nix-direnv.enable = true;
  };

  programs.zoxide = {
    enable = true;
    enableBashIntegration = true;
  };

  programs.bash = {
    enable = true;

    shellAliases = {
      ll = "ls -alh";
      la = "ls -A";
      gs = "git status";
      rebuild = "sudo nixos-rebuild switch --flake /etc/nixos#nixos";
    };

    # Put Bash-specific functions and other interactive setup here.
    initExtra = ''
      set -o vi

      # Example:
      # mkcd() { mkdir -p "$1" && cd "$1"; }
    '';
  };

  # Ported from https://github.com/matifuentes2/dotfiles. The original prompt
  # uses an Apple glyph; use the NixOS glyph on this host instead.
  programs.starship = {
    enable = true;
    enableBashIntegration = true;

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

      character.vicmd_symbol = "N >";
    };
  };

  # Lets Home Manager manage itself for this user.
  programs.home-manager.enable = true;
}
