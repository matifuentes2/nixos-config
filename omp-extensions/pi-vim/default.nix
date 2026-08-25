{
  buildNpmPackage,
  esbuild,
  fetchzip,
}:

buildNpmPackage {
  pname = "omp-pi-vim";
  version = "0.14.1";

  src = fetchzip {
    url = "https://github.com/lajarre/pi-vim/archive/refs/tags/v0.14.1.tar.gz";
    hash = "sha256-VorcGMt3H4hGnbGTGUgTmJuXRK2ud+3ozT4glGX29Do=";
  };

  patches = [ ./omp.patch ];

  postPatch = ''
    cp ${./package.json} package.json
    cp ${./package-lock.json} package-lock.json
  '';

  npmDepsHash = "sha256-7Khxpq3Wb1Js8WAguIngyFN599ARqwKqCtxDi7jdE9k=";
  dontNpmBuild = true;
  nativeBuildInputs = [ esbuild ];

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/node_modules"
    esbuild index.ts \
      --bundle \
      --platform=node \
      --format=esm \
      --target=node20 \
      --minify-syntax \
      --minify-whitespace \
      --packages=external \
      --outfile="$out/index.js"
    cp -R node_modules/@mariozechner "$out/node_modules/"

    runHook postInstall
  '';
}
