# Exercise the real Darwin install branch with the current host's builder.
# A clean build must not require /Applications/CuaDriver.app to exist already.
let
  flake = builtins.getFlake (toString ../.);
  pkgs = flake.inputs.nixpkgs.legacyPackages.${builtins.currentSystem};
  darwinPkgs = pkgs // {
    stdenv = pkgs.stdenv // {
      hostPlatform = pkgs.stdenv.hostPlatform // {
        system = "aarch64-darwin";
        isDarwin = true;
        isLinux = false;
      };
    };
  };
  package = import ../packages/cua-driver.nix {
    inherit (pkgs) lib;
    pkgs = darwinPkgs;
  };
in
package.overrideAttrs (previous: {
  pname = "cua-darwin-wrapper-test";
  src = pkgs.writeTextDir "CuaDriver.app/Contents/MacOS/cua-driver" "test fixture";
  meta = previous.meta // {
    platforms = [ pkgs.stdenv.hostPlatform.system ];
  };
})
