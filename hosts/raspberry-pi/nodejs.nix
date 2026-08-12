{ nodejsNixpkgs, pkgs }:

let
  nodejs = nodejsNixpkgs.legacyPackages.${pkgs.stdenv.hostPlatform.system}.nodejs-slim_26;

  # Node.js 26.7.0 bundles npm 11.19.0. Package the self-contained npm 12.0.2
  # registry release separately and bind its entry points to the pinned Node.
  npm = pkgs.stdenvNoCC.mkDerivation {
    pname = "npm";
    version = "12.0.2";

    src = pkgs.fetchurl {
      url = "https://registry.npmjs.org/npm/-/npm-12.0.2.tgz";
      hash = "sha256-XbuGxx0HoZV/LpBzQJLdali9zZ68LY1ByhxuaiHTZOE=";
    };

    nativeBuildInputs = [ pkgs.makeWrapper ];
    dontBuild = true;

    installPhase = ''
      runHook preInstall

      mkdir -p "$out/lib/node_modules" "$out/bin"
      cp -R . "$out/lib/node_modules/npm"

      makeWrapper "${nodejs}/bin/node" "$out/bin/npm" \
        --add-flags "$out/lib/node_modules/npm/bin/npm-cli.js"
      makeWrapper "${nodejs}/bin/node" "$out/bin/npx" \
        --add-flags "$out/lib/node_modules/npm/bin/npx-cli.js"

      runHook postInstall
    '';

    doInstallCheck = true;
    installCheckPhase = ''
      test "$("$out/bin/npm" --version)" = "12.0.2"
      test "$("$out/bin/npx" --version)" = "12.0.2"
    '';
  };
in
assert nodejs.version == "26.7.0";
pkgs.symlinkJoin {
  name = "nodejs-26.7.0-npm-12.0.2";
  paths = [
    nodejs
    npm
  ];

  postBuild = ''
    test "$("$out/bin/node" --version)" = "v26.7.0"
    test "$("$out/bin/npm" --version)" = "12.0.2"
    test "$("$out/bin/npx" --version)" = "12.0.2"
  '';

  meta = {
    description = "Node.js 26.7.0 with npm 12.0.2 for the Raspberry Pi";
    mainProgram = "node";
    platforms = [ "aarch64-linux" ];
  };
}
