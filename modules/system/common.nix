{ lib, pkgs, ... }:

{
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  # Retain recent rollback generations and collect unreferenced store paths
  # weekly. Active generations and other live GC roots remain protected.
  nix.gc = {
    automatic = true;
    options = "--delete-older-than 30d";
  }
  // lib.optionalAttrs pkgs.stdenv.isLinux {
    dates = "Sun *-*-* 04:00:00";
    randomizedDelaySec = "30min";
  }
  // lib.optionalAttrs pkgs.stdenv.isDarwin {
    interval = [
      {
        Weekday = 0;
        Hour = 4;
        Minute = 0;
      }
    ];
  };
}
