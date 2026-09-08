{ ... }:

{
  imports = [ ../../modules/system/orca-server.nix ];

  services.orcaServer = {
    enable = true;
    user = "pi";
    mobilePairing = true;
    # Preserve the existing Pi agent discovery path.
    extraPath = [ "/home/pi/.nix-profile/bin" ];
  };
}
