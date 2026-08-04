{
  description = "NixOS configuration for nixos";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";
    herdr = {
      url = "github:herdrdev/herdr/v0.8.0";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    herdr-worktrunk = {
      url = "github:devashish2203/herdr-worktrunk";
      flake = false;
    };
    worktrunk.url = "github:max-sixty/worktrunk";
    mcp-nixos.url = "github:utensils/mcp-nixos";
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      nixpkgs,
      nixpkgs-unstable,
      herdr,
      herdr-worktrunk,
      worktrunk,
      mcp-nixos,
      sops-nix,
      home-manager,
      ...
    }:
    {
      nixosConfigurations.nixos = nixpkgs.lib.nixosSystem {
        system = "aarch64-linux";
        specialArgs = { inherit nixpkgs-unstable; };
        modules = [
          ./configuration.nix
          sops-nix.nixosModules.sops
          home-manager.nixosModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.users.pi = import ./home.nix;
            home-manager.extraSpecialArgs = {
              inherit herdr herdr-worktrunk worktrunk mcp-nixos;
            };
          }
        ];
      };
    };
}
