{
  lib,
  pkgs,
  nixpkgs-unstable,
  herdr-collie,
  pi-codex-goal,
  pi-pr-review-goal,
  pi-parallel-go-pr-herdr,
  pi-execution-time,
  orca,
}:

let
  unstable = import nixpkgs-unstable {
    system = pkgs.stdenv.hostPlatform.system;
  };
  miseVersion = "2026.9.1";
  miseSources = {
    "aarch64-darwin" = pkgs.fetchzip {
      url = "https://github.com/jdx/mise/releases/download/v${miseVersion}/mise-v${miseVersion}-macos-arm64.tar.gz";
      hash = "sha256-BXDSQ5H44YR8Xx7eW3jOYk2MM5qZEGHq/bP4gICgzSA=";
    };
    "aarch64-linux" = pkgs.fetchzip {
      url = "https://github.com/jdx/mise/releases/download/v${miseVersion}/mise-v${miseVersion}-linux-arm64-musl.tar.gz";
      hash = "sha256-c0dwC2fB3stf8AzRsjgWRV8/vkc4rvGdkRmuRUsuEsE=";
    };
    "x86_64-linux" = pkgs.fetchzip {
      url = "https://github.com/jdx/mise/releases/download/v${miseVersion}/mise-v${miseVersion}-linux-x64-musl.tar.gz";
      hash = "sha256-ICHS2mQ6wMdcmz+qnz7swUtP5LnQo3ZRk03xSaPdVrI=";
    };
  };
  # Use upstream's release binaries until nixpkgs catches up.
  misePackage = pkgs.stdenvNoCC.mkDerivation {
    pname = "mise";
    version = miseVersion;
    src =
      miseSources.${pkgs.stdenv.hostPlatform.system}
        or (throw "Unsupported mise system: ${pkgs.stdenv.hostPlatform.system}");
    dontBuild = true;
    installPhase = ''
      runHook preInstall
      install -Dm755 bin/mise "$out/bin/mise"
      install -Dm444 bin/mise.d "$out/bin/mise.d"
      install -Dm444 LICENSE "$out/share/licenses/mise/LICENSE"
      mkdir -p "$out/lib/mise"
      touch "$out/lib/mise/.disable-self-update"
      runHook postInstall
    '';
    meta = {
      description = "Dev tools, env vars, and task runner";
      homepage = "https://mise.jdx.dev";
      license = lib.licenses.mit;
      mainProgram = "mise";
    };
  };
  piVersion = "0.84.4";
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
  collieVersion = "0.36.1";
  collieWebHashes = {
    "aarch64-darwin" = "sha256-M1CNvbznQaE1/XVBWwi3WEua0QVOCAFJW2tWFA/OXMU=";
    "aarch64-linux" = "sha256-6j0QANkAitOc3e9mALm6I7BT2t/0jcggNXKapu0Mo8o=";
    "x86_64-linux" = "sha256-BZGNfQKAl0JnK8fmxeBnMFg68w80adEys+4BMZygUzE=";
  };
  # Build Collie's static web application as a fixed-output derivation. Bun may
  # fetch only the dependencies pinned by the two upstream lockfiles, while the
  # resulting store path is accepted only when its complete output hash matches.
  collieWeb = pkgs.stdenvNoCC.mkDerivation {
    pname = "collie-web";
    version = collieVersion;
    src = herdr-collie;
    nativeBuildInputs = [
      bun
      pkgs.nodejs
    ];
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
      collieWebHashes.${pkgs.stdenv.hostPlatform.system}
        or (throw "Unsupported Collie system: ${pkgs.stdenv.hostPlatform.system}");
  };
  colliePlugin = pkgs.runCommand "herdr-collie-${collieVersion}" { } ''
    cp -R ${herdr-collie} "$out"
    chmod -R u+w "$out"
    rm -rf "$out/web/dist"
    mkdir -p "$out/web/dist"
    cp -R ${collieWeb}/. "$out/web/dist/"

    ${lib.optionalString pkgs.stdenv.isDarwin ''
      # launchd does not inherit the interactive shell PATH. Collie's macOS
      # agent discovers the MagicDNS name when it starts, so give it the
      # declarative Tailscale CLI rather than starting with an empty Host
      # allowlist and rejecting every request from the tailnet.
      substituteInPlace "$out/scripts/collie-ctl.sh" \
        --replace-fail \
          '        <key>HERDR_PLUGIN_CONFIG_DIR</key>' \
          '        <key>PATH</key>
        <string>${
          lib.makeBinPath [
            bun
            pkgs.tailscale
          ]
        }:/usr/bin:/bin:/usr/sbin:/sbin</string>
        <key>HERDR_PLUGIN_CONFIG_DIR</key>'
    ''}

    # The web UI is already built by Nix, so never expose the upstream
    # install-time Bun build. Updates are likewise owned by the flake input.
    # On Linux, Home Manager owns service lifecycle actions as well. Process
    # blank-line-delimited TOML blocks so read-only actions remain available.
    awk -v remove_lifecycle=${if pkgs.stdenv.isLinux then "1" else "0"} '
      BEGIN { RS = ""; ORS = "\n\n" }
      /\[\[build\]\]/ { next }
      /\[\[actions\]\]/ && /id = "update(-major)?"/ { next }
      remove_lifecycle && /\[\[actions\]\]/ && /id = "(start|stop|restart|uninstall)"/ { next }
      { print }
    ' "$out/herdr-plugin.toml" > "$out/herdr-plugin.toml.tmp"
    mv "$out/herdr-plugin.toml.tmp" "$out/herdr-plugin.toml"
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
        hash = "sha256-7z8OXao1PzmBEepDkIqVqyfQBPHulBlKcGymDYsnMvc=";
      };
    in
    unstable.pi-coding-agent.overrideAttrs {
      version = piVersion;
      inherit src;
      npmDeps = pkgs.fetchNpmDeps {
        inherit src;
        hash = "sha256-35GC3Q4Jf4URvqoEYHeM63x49tTmrth62//PvKm4I7Q=";
      };
      modelData = pkgs.fetchurl {
        url = "https://registry.npmjs.org/@earendil-works/pi-ai/-/pi-ai-${piVersion}.tgz";
        hash = "sha256-39PJKc7lpzhxmaCiTfwb4glvHqj1n/uChRmKDtAev5M=";
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

  extensionPackages = import ./pi-extensions.nix { inherit lib pkgs upstreamPi; };
  piExtensions = extensionPackages.registration;
  piExtensionPackages = extensionPackages.packages;
  piExtensionNodeModules = extensionPackages.peers;

  mkPiExtensionPackage =
    name: src:
    pkgs.runCommand name { } ''
      cp -R ${src}/. "$out"
      chmod u+w "$out"
      ln -s ${piExtensionNodeModules} "$out/node_modules"
    '';

  # pi-pr-review-goal verifies pi-codex-goal through the command's source path.
  # Descriptive output names preserve package provenance in Pi's registry.
  piCodexGoalPackage = mkPiExtensionPackage "pi-codex-goal" pi-codex-goal;
  piPrReviewGoalPackage = mkPiExtensionPackage "pi-pr-review-goal" pi-pr-review-goal;
  piParallelGoPrHerdrPackage = mkPiExtensionPackage "pi-parallel-go-pr-herdr" pi-parallel-go-pr-herdr;
  piExecutionTimePackage = mkPiExtensionPackage "pi-execution-time" pi-execution-time;

  chromeDevtoolsMcp = pkgs.writeShellApplication {
    name = "chrome-devtools-mcp";
    runtimeInputs = lib.optionals pkgs.stdenv.isLinux [ pkgs.chromium ];
    text = ''
      export CHROME_DEVTOOLS_MCP_NO_UPDATE_CHECKS=1
      export CHROME_DEVTOOLS_MCP_NO_USAGE_STATISTICS=1

      exec ${lib.getExe pkgs.nodejs_22} \
        ${piExtensionPackages.chrome-devtools-mcp}/${piExtensionPackages.chrome-devtools-mcp.packageRoot}/build/src/bin/chrome-devtools-mcp.js \
        --autoConnect \
        --channel=stable \
        --experimentalPageIdRouting \
        --redactNetworkHeaders \
        --no-performance-crux \
        "$@"
    '';
  };
in
{
  inherit
    bun
    chromeDevtoolsMcp
    colliePlugin
    misePackage
    orcaSkills
    pi
    piVersion
    piExtensions
    piExtensionPackages
    piCodexGoalPackage
    piPrReviewGoalPackage
    piParallelGoPrHerdrPackage
    piExecutionTimePackage
    ;
}
