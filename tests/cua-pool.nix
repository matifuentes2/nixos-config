{ pkgs }:
let
  driver = pkgs.callPackage ../packages/cua-driver.nix { };
  runtime = import ../modules/home/cua-runtime.nix {
    inherit pkgs driver;
    inherit (pkgs) lib;
    display = ":99";
  };
in
pkgs.runCommand "cua-pool-leases" { } ''
  ${pkgs.lib.getExe pkgs.python3} ${./cua-pool.py} ${../scripts/cua-pool.py}
  ${pkgs.lib.getExe pkgs.python3} ${./cua-pool-mcp.py} ${../scripts/cua-pool.py} ${pkgs.lib.getExe driver}

  # A delayed job retaining an old environment must fail before it can use
  # the new slot's bus or Xauthority, even when the display number is reused.
  mkdir -p "$TMPDIR/stale"
  printf '%s\n' replacement > "$TMPDIR/stale/lease.id"
  set +e
  XDG_RUNTIME_DIR="$TMPDIR/stale" CUA_POOL_LEASE=previous \
    ${pkgs.lib.getExe runtime.run} ${pkgs.coreutils}/bin/true
  result=$?
  set -e
  test "$result" = 2
  touch "$out"
''
