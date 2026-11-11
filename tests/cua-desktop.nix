# Small evaluation/build entrypoint for the Cua services, without evaluating a
# complete host or its unrelated application packages. Use the locked inputs.
let
  flake = builtins.getFlake (toString ../.);
  pkgs = flake.inputs.nixpkgs.legacyPackages.${builtins.currentSystem};
  makeHome =
    headless:
    flake.inputs.home-manager.lib.homeManagerConfiguration {
      inherit pkgs;
      modules = [
        ../modules/home/cua-driver.nix
        ({ lib, ... }: {
          options.pi.mcpServers = lib.mkOption {
            type = lib.types.attrs;
            default = { };
          };
          config = {
            home.username = "pi";
            home.homeDirectory = "/home/pi";
            home.stateVersion = "25.11";
            services.cua-driver.agentDesktop = {
              enable = true;
              inherit headless;
            };
          };
        })
      ];
    };
  home = (makeHome true).config;
  package = name: pkgs.lib.findFirst (p: p.name == name) (throw "Missing ${name}") home.home.packages;
in
{
  desktop = pkgs.writeShellScriptBin "cua-agent-desktop" ''
    exec ${builtins.head home.systemd.user.services.cua-agent-desktop.Service.ExecStart} "$@"
  '';
  run = package "cua-agent-run";
  browser = package "cua-agent-browser";
  editor = package "cua-agent-editor";
  smoke = package "cua-agent-smoke";
  t3 = pkgs.callPackage ../packages/t3-cli.nix { };
  units = home.systemd.user.services;
  graphicalUnits = (makeHome false).config.systemd.user.services;
  lifecycleCheck =
    let
      headless = home.systemd.user.services;
      graphical = (makeHome false).config.systemd.user.services;
    in
    assert headless.cua-agent-desktop.Install.WantedBy == [ "default.target" ];
    assert headless.cua-driver.Install.WantedBy == [ "default.target" ];
    assert headless.cua-agent-desktop.Unit.PartOf == [ ];
    assert !(builtins.elem "graphical-session.target" headless.cua-agent-desktop.Unit.After);
    assert headless.cua-driver.Unit.Requires == [ "cua-agent-desktop.service" ];
    assert headless.cua-driver.Unit.PartOf == [ "cua-agent-desktop.service" ];
    assert headless.cua-agent-desktop.Unit.Upholds == [ "cua-driver.service" ];
    assert graphical.cua-agent-desktop.Install.WantedBy == [ "graphical-session.target" ];
    assert graphical.cua-agent-desktop.Unit.PartOf == [ "graphical-session.target" ];
    "headless and graphical lifecycle checks passed";
}
