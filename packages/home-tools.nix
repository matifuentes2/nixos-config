{
  lib,
  pkgs,
  nixpkgs-unstable,
  herdr-collie,
  pi-codex-goal,
  pi-pr-review-goal,
  pi-parallel-go-pr-herdr,
  pi-execution-time,
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
  piVersion = "1.4.0";
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
  # The web build is platform-independent once its service worker manifest is
  # sorted, so every system is expected to produce the same output.
  collieWebHash = "sha256-1HvKdonO5+9br+RlcQckoMGQGIzK7UcS9koOWC8GXAc=";
  collieWebHashes = {
    "aarch64-darwin" = collieWebHash;
    "aarch64-linux" = collieWebHash;
    "x86_64-linux" = collieWebHash;
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

      # Workbox lists precached files in directory order, which differs between
      # filesystems and builds. Sort the service worker manifest so the output
      # hash is reproducible.
      patched=0
      while IFS= read -r -d "" manifest; do
        substituteInPlace "$manifest" \
          --replace-fail \
            '    const count = transformedManifest.length;' \
            '    const entryKey = (entry) => (typeof entry === "string" ? entry : `''${entry.url} ''${entry.revision ?? ""}`);
          transformedManifest = [...transformedManifest].sort((a, b) => (entryKey(a) < entryKey(b) ? -1 : entryKey(a) > entryKey(b) ? 1 : 0));
          const count = transformedManifest.length;'
        patched=$((patched + 1))
      done < <(find web/node_modules -path '*/workbox-build/build/lib/transform-manifest.js' -print0)
      [ "$patched" -gt 0 ] || { echo "workbox-build transform-manifest.js not found" >&2; exit 1; }

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
  # Pin the current upstream release until nixos-unstable catches up.
  upstreamPi =
    let
      src = pkgs.fetchFromGitHub {
        owner = "earendil-works";
        repo = "pi";
        tag = "v${piVersion}";
        hash = "sha256-N9NOpiiZTbOMDMV+CxvJAgtLjJJ1/8NJBGS0cFHkhsc=";
      };
    in
    unstable.pi-coding-agent.overrideAttrs (_old: {
      version = piVersion;
      inherit src;
      npmDeps = pkgs.fetchNpmDeps {
        inherit src;
        hash = "sha256-aBzVz78IxZQlzPYC72Ufa2YFtkow6nZR24YBYZrv9W0=";
      };
      modelData = pkgs.fetchurl {
        url = "https://registry.npmjs.org/@earendil-works/pi-ai/-/pi-ai-${piVersion}.tgz";
        hash = "sha256-tA4rqLtvwzKQj4uW6DfcLR/ftF65zTgvWu0RFGKYHjw=";
      };

      # Pi 1.x reorganized its workspaces and CLI bundle. Build offline using
      # the matching published model catalog supplied by preConfigure above.
      buildPhase = ''
        runHook preBuild
        npm run build:offline
        runHook postBuild
      '';
      postInstall = ''
        local nm="$out/lib/node_modules/pi-monorepo/node_modules"
        for ws in telemetry chord tui codemode mcp ai durable env agent; do
          pkg=$(node -p "require('./packages/' + '$ws' + '/package.json').name")
          rm -f "$nm/$pkg"
          cp -r "packages/$ws" "$nm/$pkg"
        done
        find "$nm" -type l -lname '*/packages/*' -delete
        find "$nm/.bin" -xtype l -delete
      ''
      + lib.optionalString pkgs.stdenv.isDarwin ''
        rm -rf \
          "$nm/@anthropic-ai/sandbox-runtime/dist/vendor/seccomp" \
          "$nm/@anthropic-ai/sandbox-runtime/vendor/seccomp"
      '';
    });

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
        ${upstreamPi}/lib/node_modules/pi-monorepo/dist/bundle/cli.js "$@"
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
