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
  unstable = import nixpkgs-unstable {
    system = pkgs.stdenv.hostPlatform.system;
  };
  piVersion = "0.84.2";
  bunVersion = "1.4.0";
  bunSources = {
    "aarch64-darwin" = pkgs.fetchurl {
      url = "https://github.com/oven-sh/bun/releases/download/bun-v${bunVersion}/bun-darwin-aarch64.zip";
      hash = "sha256-xmnpf2Fk4cluBwF0jbmN+ndJKQjL2DlMdVcTSnNd44E=";
    };
    "aarch64-linux" = pkgs.fetchurl {
      url = "https://github.com/oven-sh/bun/releases/download/bun-v${bunVersion}/bun-linux-aarch64.zip";
      hash = "sha256-SxozLuhhmD65O8/m93D/+U4+MbLDiL2uo8jtNeWO7Q4=";
    };
    "x86_64-linux" = pkgs.fetchurl {
      url = "https://github.com/oven-sh/bun/releases/download/bun-v${bunVersion}/bun-linux-x64.zip";
      hash = "sha256-LQP7X7g6yLVnrKCigbLOGhoZ1Ij1bClo2Iw/Jekv5FI=";
    };
  };
  # Pin the current Bun release until nixpkgs catches up.
  bun = pkgs.bun.overrideAttrs (oldAttrs: {
    version = bunVersion;
    src =
      bunSources.${pkgs.stdenv.hostPlatform.system}
        or (throw "Unsupported Bun system: ${pkgs.stdenv.hostPlatform.system}");
    passthru = oldAttrs.passthru // {
      sources = bunSources;
    };
  });
  collieVersion = "0.26.0";
  # Build Collie's static web application as a fixed-output derivation. Bun may
  # fetch only the dependencies pinned by the two upstream lockfiles, while the
  # resulting store path is accepted only when its complete output hash matches.
  collieWeb = pkgs.stdenvNoCC.mkDerivation {
    pname = "collie-web";
    version = collieVersion;
    src = herdr-collie;
    nativeBuildInputs = [ bun ];
    dontConfigure = true;

    buildPhase = ''
      runHook preBuild
      export HOME="$TMPDIR/home"
      export XDG_CACHE_HOME="$TMPDIR/cache"
      export SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt
      mkdir -p "$HOME" "$XDG_CACHE_HOME"

      substituteInPlace web/vite.config.ts \
        --replace-fail \
          'const buildTime = new Date().toISOString();' \
          'const buildTime = new Date(${toString (herdr-collie.lastModified * 1000)}).toISOString();'

      bun install --frozen-lockfile
      (cd web && bun install --frozen-lockfile)
      (cd web && bun ./node_modules/vite/bin/vite.js build)
      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall
      cp -R web/dist "$out"
      runHook postInstall
    '';

    outputHashMode = "recursive";
    outputHashAlgo = "sha256";
    outputHash =
      if pkgs.stdenv.hostPlatform.isDarwin then
        "sha256-+svLTgDnCi2ujEqeqUrdVVvL2FDoufZ5uSWh2D1/TCg="
      else
        "sha256-fm9DRwYnNPNSMl5tJGCt6jWVtyeDRViNWX6tSvDoAOA=";
  };
  colliePlugin = pkgs.runCommand "herdr-collie-${collieVersion}" { } ''
    cp -R ${herdr-collie} "$out"
    chmod -R u+w "$out"
    rm -rf "$out/web/dist"
    mkdir -p "$out/web/dist"
    cp -R ${collieWeb}/. "$out/web/dist/"

    # The web UI is already built by Nix, so never expose the upstream
    # install-time Bun build. Updates are likewise owned by the flake input.
    # On Linux, Home Manager owns service lifecycle actions as well. Process
    # blank-line-delimited TOML blocks so read-only actions remain available.
    awk -v remove_lifecycle=${if pkgs.stdenv.isLinux then "1" else "0"} '
      BEGIN { RS = ""; ORS = "\n\n" }
      /\[\[build\]\]/ { next }
      /\[\[actions\]\]/ && /id = "update"/ { next }
      remove_lifecycle && /\[\[actions\]\]/ && /id = "(start|stop|restart|uninstall)"/ { next }
      { print }
    ' "$out/herdr-plugin.toml" > "$out/herdr-plugin.toml.tmp"
    mv "$out/herdr-plugin.toml.tmp" "$out/herdr-plugin.toml"
  '';
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
  orcaSkillNames = [
    "orca-cli"
    "orchestration"
    "computer-use"
    "orca-linear"
    "orca-emulator"
    "orca-emulator-android"
  ];
  orcaSkills = pkgs.runCommand "orca-agent-skills" { } ''
    mkdir -p "$out"
    ${lib.concatMapStringsSep "\n" (name: ''
      cp -R ${orca}/skills/${name} "$out/${name}"
    '') orcaSkillNames}
  '';
  # Pin the current upstream release until nixos-unstable catches up.
  upstreamPi =
    let
      src = pkgs.fetchFromGitHub {
        owner = "earendil-works";
        repo = "pi";
        tag = "v${piVersion}";
        hash = "sha256-d29ft9otYxdHRWYIAX8KMHPpppToX9ME5LbPb1rPcYo=";
      };
    in
    unstable.pi-coding-agent.overrideAttrs {
      version = piVersion;
      inherit src;
      npmDeps = pkgs.fetchNpmDeps {
        inherit src;
        hash = "sha256-6J5Efe+6ptCuR3VZojwYPZO8BBnnZsOQ4OAeB64uYOY=";
      };
      modelData = pkgs.fetchurl {
        url = "https://registry.npmjs.org/@earendil-works/pi-ai/-/pi-ai-${piVersion}.tgz";
        hash = "sha256-AmJ4Wnaw6y7sWWzYp6su4j7vidLvG7EhHE8KGUTaz0E=";
      };
    };

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

      exec -a "$0" ${lib.getExe bun} \
        ${upstreamPi}/lib/node_modules/pi-monorepo/dist/bun/cli.js "$@"
    '';
  };

  piExtensions = pkgs.buildNpmPackage {
    pname = "pi-extensions";
    version = "1.0.0";
    src = ../../pi-extensions;
    npmDepsHash = "sha256-F92tzB80NDYUHbxxm6UOCEpye4WZnqNyjRTkICbA3l8=";
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

  # pi-pr-review-goal verifies pi-codex-goal through the command's source path.
  # Flake source inputs otherwise use a generic "*-source" store name, so copy
  # each package into a descriptively named store path that preserves package
  # provenance for Pi's command registry.
  piCodexGoalPackage = pkgs.runCommand "pi-codex-goal" { } ''
    cp -R ${pi-codex-goal}/. "$out"
  '';

  piPrReviewGoalPackage = pkgs.runCommand "pi-pr-review-goal" { } ''
    cp -R ${pi-pr-review-goal}/. "$out"
  '';

  piParallelGoPrHerdrPackage = pkgs.runCommand "pi-parallel-go-pr-herdr" { } ''
    cp -R ${pi-parallel-go-pr-herdr}/. "$out"
  '';

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
    android-tools
    worktrunk.packages.${pkgs.stdenv.hostPlatform.system}.default
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

  # Pi loads this locally built package from the immutable Nix store. Its npm
  # dependency graph is pinned by pi-extensions/package-lock.json.
  home.file.".pi/agent/settings.json" = {
    force = true;
    text = builtins.toJSON {
      # This file is immutable, so Pi cannot persist the version after showing
      # an update. Keep it aligned with the packaged version to suppress the
      # automatic startup changelog; /changelog remains available on demand.
      lastChangelogVersion = piVersion;
      theme = "dark";
      defaultProvider = "openai-codex";
      defaultModel = "gpt-5.6-sol";
      defaultThinkingLevel = "minimal";
      # GPT-5.6 Sol has a 272k context window; reserving 20% triggers
      # auto-compaction when the conversation exceeds 80% (217,600 tokens).
      compaction = {
        enabled = true;
        reserveTokens = 54400;
        keepRecentTokens = 20000;
      };
      packages = [
        "${piExtensions}/lib/node_modules/pi-extensions"
        "${piCodexGoalPackage}"
        "${piPrReviewGoalPackage}"
        "${piParallelGoPrHerdrPackage}"
        "${pi-execution-time}"
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
