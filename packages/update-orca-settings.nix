{ pkgs }:

pkgs.writeShellApplication {
  name = "update-orca-settings";
  runtimeInputs = [
    pkgs.coreutils
    pkgs.jq
  ];
  text = builtins.readFile ../scripts/update-orca-settings.sh;
}
