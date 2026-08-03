{
  description = "NixOS configuration for nixos";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";
    herdr = {
      url = "github:herdrdev/herdr/v0.8.0";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    home-manager = {
    url = "github:nix-community/home-manager";
    inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { nixpkgs, nixpkgs-unstable, herdr, home-manager, ... }: {
    nixosConfigurations.nixos = nixpkgs.lib.nixosSystem {
      system = "aarch64-linux";
      specialArgs = { inherit nixpkgs-unstable; };
      modules = [
        ./configuration.nix
        home-manager.nixosModules.home-manager
        {
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.users.pi = import ./home.nix;
          home-manager.extraSpecialArgs = { inherit herdr; };
        }
      ];
    };
  };
}
