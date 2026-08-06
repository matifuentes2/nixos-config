{
  description = "Shared NixOS and nix-darwin configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";
    nix-darwin = {
      url = "github:nix-darwin/nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    herdr = {
      url = "github:herdrdev/herdr/v0.8.0";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    herdr-worktrunk = {
      url = "github:devashish2203/herdr-worktrunk";
      flake = false;
    };
    herdr-collie = {
      url = "github:AltanS/collie/v0.24.0";
      flake = false;
    };
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
      nix-darwin,
      herdr,
      herdr-worktrunk,
      herdr-collie,
      mcp-nixos,
      sops-nix,
      home-manager,
      ...
    }:
    let
      # Change these two values before the first macOS activation if the Mac is
      # Intel-based or its local short account name is not "matias".
      darwinSystem = "aarch64-darwin";
      darwinUsername = "matias";

      homeSpecialArgs = {
        inherit
          herdr
          herdr-worktrunk
          herdr-collie
          mcp-nixos
          nixpkgs-unstable
          ;
      };
    in
    {
      nixosConfigurations.nixos = nixpkgs.lib.nixosSystem {
        system = "aarch64-linux";
        modules = [
          ./hosts/raspberry-pi
          sops-nix.nixosModules.sops
          home-manager.nixosModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.users.pi = import ./hosts/raspberry-pi/home.nix;
            home-manager.extraSpecialArgs = homeSpecialArgs;
          }
        ];
      };

      darwinConfigurations.macbook = nix-darwin.lib.darwinSystem {
        system = darwinSystem;
        specialArgs = {
          username = darwinUsername;
        };
        modules = [
          ./hosts/macbook
          home-manager.darwinModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.users.${darwinUsername} = import ./hosts/macbook/home.nix;
            home-manager.extraSpecialArgs = homeSpecialArgs // {
              username = darwinUsername;
            };
          }
        ];
      };
    };
}
