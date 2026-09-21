{
  config,
  lib,
  pkgs,
  nixpkgs-unstable,
  herdr,
  worktrunk,
  herdr-worktrunk,
  herdr-collie,
  mcp-nixos,
  pi-codex-goal,
  pi-pr-review-goal,
  pi-parallel-go-pr-herdr,
  pi-execution-time,
  orca,
  enableCollieService ? false,
  ...
}:

let
  homeTools = import ../../packages/home-tools.nix {
    inherit
      lib
      pkgs
      nixpkgs-unstable
      herdr-collie
      pi-codex-goal
      pi-pr-review-goal
      pi-parallel-go-pr-herdr
      pi-execution-time
      orca
      ;
  };
  inherit (homeTools)
    bun
    chromeDevtoolsMcp
    colliePlugin
    misePackage
    orcaSkills
    pi
    piVersion
    piExtensions
    piCodexGoalPackage
    piPrReviewGoalPackage
    piParallelGoPrHerdrPackage
    piExecutionTimePackage
    ;

  playwrightMcp = import ../../packages/playwright-mcp.nix { inherit lib pkgs; };

  collieConfigDir = "${config.home.homeDirectory}/.config/herdr/plugins/config/herdr.collie";
  # The encrypted dotenv is shared with the Raspberry Pi and therefore contains
  # that host's allowlisted MagicDNS name. Resolve this host's name at runtime
  # and override only COLLIE_PUBLIC_HOSTS without exposing the tailnet suffix in
  # this public repository.
  collieLauncher = pkgs.writeShellScript "collie-launcher" ''
    public_host=""
    for _ in {1..30}; do
      public_host="$(${lib.getExe pkgs.tailscale} status --json 2>/dev/null \
        | ${lib.getExe pkgs.jq} -r '.Self.DNSName // "" | sub("\\.$"; "")')"
      if [[ -n "$public_host" ]]; then
        break
      fi
      ${lib.getExe' pkgs.coreutils "sleep"} 1
    done
    if [[ -z "$public_host" ]]; then
      echo "Collie could not resolve this host's Tailscale DNS name" >&2
      exit 1
    fi

    export COLLIE_PUBLIC_HOSTS="$public_host"
    exec ${lib.getExe bun} run ${colliePlugin}/bridge/index.ts
  '';
  collieServe = pkgs.writeShellScript "collie-tailscale-serve" ''
    export HERDR_PLUGIN_CONFIG_DIR=${lib.escapeShellArg collieConfigDir}
    export PATH=${
      lib.makeBinPath [
        bun
        pkgs.coreutils
        pkgs.git
        pkgs.jq
        pkgs.systemd
        pkgs.tailscale
      ]
    }
    exec ${lib.getExe pkgs.bash} ${colliePlugin}/scripts/collie-ctl.sh serve
  '';

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
    lazygit
    bun
    uv
    devenv
    android-tools
    worktrunk.packages.${pkgs.stdenv.hostPlatform.system}.default
    pi
    chromeDevtoolsMcp
    playwrightMcp
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

  # Link the pinned plugin with its web UI already built in the Nix store. This
  # avoids runtime package installation and keeps activation network-independent.
  home.activation.linkHerdrCollie = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    run ${lib.getExe herdr.packages.${pkgs.stdenv.hostPlatform.system}.default} \
      plugin link ${colliePlugin} --enabled

    ${lib.optionalString pkgs.stdenv.isDarwin ''
      # launchd remains managed by Collie's supported control script on macOS.
      # Linux uses the declarative Home Manager units below instead.
      if [[ -S "$HOME/.config/herdr/herdr.sock" ]]; then
        if ! run ${lib.getExe herdr.packages.${pkgs.stdenv.hostPlatform.system}.default} \
          plugin action invoke restart --plugin herdr.collie; then
          echo "Could not restart the live Collie bridge; the plugin remains linked"
        fi
      else
        echo "Herdr is not running; skipping the Collie bridge restart"
      fi
    ''}
  '';

  # Replace Collie's generated mutable Linux unit with Home Manager-owned units.
  # The companion oneshot declaratively maintains the tailnet-only HTTPS proxy.
  systemd.user.services = lib.mkIf (pkgs.stdenv.isLinux && enableCollieService) {
    collie = {
      Unit = {
        Description = "Collie";
        After = [ "default.target" ];
        StartLimitIntervalSec = 0;
      };
      Service = {
        Type = "simple";
        WorkingDirectory = "${colliePlugin}";
        ExecStart = "${collieLauncher}";
        Restart = "on-failure";
        RestartSec = 5;
        NoNewPrivileges = true;
        PrivateTmp = true;
        Environment = [
          "HERDR_SOCKET_PATH=${config.home.homeDirectory}/.config/herdr/herdr.sock"
          "COLLIE_PORT=8787"
          "HERDR_PLUGIN_CONFIG_DIR=${collieConfigDir}"
        ];
        EnvironmentFile = "-${collieConfigDir}/.env";
      };
      Install.WantedBy = [ "default.target" ];
    };

    collie-tailscale-serve = {
      Unit = {
        Description = "Publish Collie through Tailscale Serve";
        After = [ "collie.service" ];
        Requires = [ "collie.service" ];
      };
      Service = {
        Type = "oneshot";
        ExecStart = "${collieServe}";
        RemainAfterExit = true;
      };
      Install.WantedBy = [ "default.target" ];
    };
  };

  # Collie's former control script may have created this unit as a regular file.
  # Allow Home Manager to replace it with the declarative generation symlink.
  xdg.configFile."systemd/user/collie.service" = lib.mkIf (
    pkgs.stdenv.isLinux && enableCollieService
  ) { force = true; };
  xdg.configFile."systemd/user/default.target.wants/collie.service" = lib.mkIf (
    pkgs.stdenv.isLinux && enableCollieService
  ) { force = true; };

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

  # Pi loads a cheap registration manifest pointing to independently built
  # packages, each pinned by pi-extensions/<name>/package-lock.json.
  home.file.".pi/agent/settings.json" = {
    force = true;
    text = builtins.toJSON {
      # This file is immutable, so Pi cannot persist the version after showing
      # an update. Keep it aligned with the packaged version to suppress the
      # automatic startup changelog; /changelog remains available on demand.
      lastChangelogVersion = piVersion;
      theme = "dark";
      defaultProvider = "openai-codex";
      defaultModel = "gpt-6-astra";
      defaultThinkingLevel = "medium";
      subagents.agentOverrides = {
        scout = {
          model = "openai-codex/gpt-5.6-luna";
          thinking = "low";
        };
        worker = {
          model = "openai-codex/gpt-5.6-luna";
          thinking = "medium";
        };
        reviewer = {
          model = "openai-codex/gpt-5.6-luna";
          thinking = "medium";
        };
        oracle = {
          model = "inherit";
          thinking = "high";
        };
      };
      # Preserve the existing compaction token budget across model changes.
      compaction = {
        enabled = true;
        reserveTokens = 54400;
        keepRecentTokens = 20000;
      };
      packages = [
        "${piExtensions}"
        "${piCodexGoalPackage}"
        "${piPrReviewGoalPackage}"
        "${piParallelGoPrHerdrPackage}"
        "${piExecutionTimePackage}"
      ];
    };
  };

  # Install Pi agent skills declaratively from pinned or tracked sources.
  home.file.".pi/agent/skills/herdr/SKILL.md".source = "${herdr}/skills/herdr/SKILL.md";
  home.file.".pi/agent/skills/devenv-setup/SKILL.md".source = ../../pi-skills/devenv-setup/SKILL.md;

  # ~/.agents/skills is discovered by both Pi and Orca. Installing the complete
  # directories here lets Orca detect the skills and activate their setup UI,
  # while preserving any references or assets shipped beside SKILL.md.
  home.file.".agents/skills" = {
    source = orcaSkills;
    recursive = true;
  };

  # Keep shared Pi prompt templates reproducible across every host.
  home.file.".pi/agent/prompts/go-pr.md" = {
    force = true;
    source = ../../pi-prompts/go-pr.md;
  };

  # Append routing rules without replacing Pi's built-in prompt or the user's
  # existing global AGENTS.md (which other extensions may maintain).
  home.file.".pi/agent/APPEND_SYSTEM.md".source = ../../pi-prompts/browser-routing.md;

  # pi-mcp-adapter reads this configuration and starts each pinned server only
  # when one of its tools is first used.
  home.file.".pi/agent/mcp.json" = {
    force = true;
    text = builtins.toJSON {
      mcpServers = {
        playwright = {
          command = lib.getExe playwrightMcp;
          args = [ "--extension" ];
          lifecycle = "lazy";
        };
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
    package = misePackage;
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
