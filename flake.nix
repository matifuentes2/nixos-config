{
  description = "Shared NixOS and nix-darwin configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";
    nix-darwin = {
      url = "github:nix-darwin/nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-homebrew.url = "github:zhaofengli/nix-homebrew";
    homebrew-core = {
      url = "github:homebrew/homebrew-core";
      flake = false;
    };
    homebrew-cask = {
      url = "github:homebrew/homebrew-cask";
      flake = false;
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
      nix-homebrew,
      homebrew-core,
      homebrew-cask,
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
      # Intel-based or its local short account name is not "matif".
      darwinSystem = "aarch64-darwin";
      darwinUsername = "matif";

      homeSpecialArgs = {
        inherit
          herdr
          herdr-worktrunk
          herdr-collie
          mcp-nixos
          nixpkgs-unstable
          ;
      };

      bootstrapSystems = [
        "aarch64-linux"
        "aarch64-darwin"
        "x86_64-linux"
      ];
    in
    {
      # Bootstrap Git comes from this flake's locked nixpkgs input, avoiding a
      # mutable registry or branch reference on fresh systems. CI tools are
      # exposed for the repository's validation workflow.
      packages = nixpkgs.lib.genAttrs bootstrapSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          bootstrap-git = pkgs.git;
          ci-tools = pkgs.buildEnv {
            name = "nixos-config-ci-tools";
            paths = [
              pkgs.actionlint
              pkgs.exiftool
              pkgs.gitleaks
              pkgs.nixfmt
              pkgs.shellcheck
            ];
          };
        }
      );

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
          inherit homebrew-core homebrew-cask;
        };
        modules = [
          ./hosts/macbook
          nix-homebrew.darwinModules.nix-homebrew
          home-manager.darwinModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.backupFileExtension = "backup";
            home-manager.users.${darwinUsername} = import ./hosts/macbook/home.nix;
            home-manager.extraSpecialArgs = homeSpecialArgs // {
              username = darwinUsername;
            };
          }
        ];
      };
    };
}
