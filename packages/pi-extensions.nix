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
    chrome-devtools-mcp.npmDepsHash = "sha256-/AdABlMiXTO8oQKmnfRYxZfGNgII5b6noJiDqKvH5/w=";
    context-mode.npmDepsHash = "sha256-asY1v6GNEqnZLr0JdUrsvfqbL++YbhmXyD3Im/QEAk8=";
    pi-ollama-cloud.npmDepsHash = "sha256-SqlCiuG3me6qSq5U/aXaz58OM1j2kpxEATe6oc31lDA=";
    pi-subagents.npmDepsHash = "sha256-8bpZrdenFk56VHRQ80CFdo/3R7kGeHA0laWKN3oxzj0=";
    pi-vim = {
      npmDepsHash = "sha256-asv7nv8IXfL5dm7OuTP8Ru+ozfsbPh66FfJuZHKxEYc=";
      bundle = "index.ts";
    };
    # These remain unbundled: web-access lazily loads optional extractors, and
    # subagents resolves background helper scripts relative to its source files.
    pi-web-access.npmDepsHash = "sha256-jmjDRr15LZjXr8uGTPe/+qqJ5N9AOg1GOtxZsSnFATo=";
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
