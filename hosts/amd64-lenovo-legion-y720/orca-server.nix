{ username, ... }:

{
  imports = [ ../../modules/system/orca-server.nix ];

  services.orcaServer = {
    enable = true;
    user = username;
  };
}
