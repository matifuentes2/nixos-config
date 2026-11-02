{ lib, pkgs, ... }:

{
  # Claude Code is proprietary; allow just this package on shared hosts.
  nixpkgs.config.allowUnfreePredicate = pkg: lib.getName pkg == "claude-code";

  # Pin every NixOS host to Chile's mainland time zone instead of relying on
  # imperative timedatectl changes or WSL/hardware defaults.
  time.timeZone = lib.mkIf pkgs.stdenv.isLinux "America/Santiago";

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
