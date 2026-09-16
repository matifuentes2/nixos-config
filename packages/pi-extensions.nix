{
  lib,
  pkgs,
  upstreamPi,
  registry ? builtins.fromJSON (builtins.readFile ../pi-extensions/package.json),
}:
let
  upstreamNodeModules = "${upstreamPi}/lib/node_modules/pi-monorepo/node_modules";

  # Only Pi-owned APIs belong here, never another extension's dependency tree.
  # Git-sourced extensions and npm extensions resolve the same API instances.
  peers = pkgs.runCommand "pi-extension-peers" { } ''
    mkdir -p "$out/@earendil-works"
    for name in pi-agent-core pi-ai pi-tui; do
      ln -s "${upstreamNodeModules}/@earendil-works/$name" "$out/@earendil-works/$name"
    done
    ln -s "${upstreamPi}/lib/node_modules/pi-monorepo" "$out/@earendil-works/pi-coding-agent"
    ln -s "${upstreamNodeModules}/typebox" "$out/typebox"
  '';

  mkPackage =
    name:
    {
      npmDepsHash,
      bundle ? "",
      external ? [ "--packages=external" ],
    }:
    let
      manifest = builtins.fromJSON (builtins.readFile (../pi-extensions + "/${name}/package.json"));
    in
    pkgs.buildNpmPackage {
      pname = "${name}-package";
      version = manifest.version;
      # A sibling lockfile or a registration change cannot invalidate this source.
      src = ../pi-extensions + "/${name}";
      inherit npmDepsHash;
      dontNpmBuild = true;
      npmFlags = [ "--legacy-peer-deps" ];
      nativeBuildInputs = lib.optional (bundle != "") pkgs.esbuild;
      postInstall = ''
        modules="$out/lib/node_modules/${manifest.name}/node_modules"
        mkdir -p "$modules/@earendil-works"
        for name in pi-agent-core pi-ai pi-coding-agent pi-tui; do
          ln -s "${peers}/@earendil-works/$name" "$modules/@earendil-works/$name"
        done
        if [[ ! -e "$modules/typebox" ]]; then
          ln -s "${peers}/typebox" "$modules/typebox"
        fi
      ''
      + lib.optionalString (bundle != "") ''
        esbuild "$modules/${name}/${bundle}" \
          --bundle --platform=node --format=esm --target=node20 \
          --minify-syntax --minify-whitespace \
          ${lib.escapeShellArgs external} \
          --outfile="$modules/${name}/index.bundle.mjs"
      '';
      passthru.packageRoot = "lib/node_modules/${manifest.name}/node_modules/${name}";
    };

  packages = lib.mapAttrs mkPackage {
    chrome-devtools-mcp.npmDepsHash = "sha256-qnVowNtI4flKfeT3mtHwNT5qoH6h1Eg+gYFzjYFkq78=";
    context-mode.npmDepsHash = "sha256-asY1v6GNEqnZLr0JdUrsvfqbL++YbhmXyD3Im/QEAk8=";
    pi-mcp-adapter = {
      npmDepsHash = "sha256-8jJOP0oOf1NJu6X4z+7mNn9OFPumNUJ/ZzMP0rzVqPw=";
      bundle = "index.ts";
      external = [
        "--external:@earendil-works/*"
        "--external:@napi-rs/keyring"
        "--external:open"
      ];
    };
    pi-ollama-cloud.npmDepsHash = "sha256-R7Kn0cgg+lUNSXGyXWPhfuBNf1g1Bs8wGyE2l2prNYc=";
    pi-subagents.npmDepsHash = "sha256-XK8mP5YWjiaVC3qAMxK8MgtfrkSa/djY/d40mDrqVoU=";
    pi-vim = {
      npmDepsHash = "sha256-RshhKPh16cXUldezIZUEDF+Hk4cwMDR7JAoWsShEKEc=";
      bundle = "index.ts";
    };
    # These remain unbundled: web-access lazily loads optional extractors, and
    # subagents resolves background helper scripts relative to its source files.
    pi-web-access.npmDepsHash = "sha256-S92WIvKxTQ2pqdmPsWbRKP1LqwyQ0keJ44hp5ecS3JA=";
    pi-zentui = {
      npmDepsHash = "sha256-1aFUfLTj6HUcCkEt+1DKRJ4k3HbrssJ6Z8HIkVKR/o0=";
      bundle = "extensions/zentui/index.ts";
    };
  };

  # Registration is a cheap manifest + symlinks, not an npm build. Disabled
  # packages are not referenced by this derivation, even if still defined above.
  resourcePaths = lib.concatLists (builtins.attrValues registry.pi);
  names = lib.unique (map (path: builtins.elemAt (lib.splitString "/" path) 1) resourcePaths);
  registration = pkgs.runCommand "pi-extensions" { } ''
    mkdir -p "$out/node_modules"
    cp ${pkgs.writeText "pi-extension-registry.json" (builtins.toJSON registry)} "$out/package.json"
    ${lib.concatMapStringsSep "\n" (name: ''
      ln -s ${packages.${name}}/${packages.${name}.packageRoot} "$out/node_modules/${name}"
    '') names}
  '';
in
{
  inherit packages peers registration;
}
