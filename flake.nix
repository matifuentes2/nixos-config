{
  description = "Shared NixOS, NixOS-WSL, and nix-darwin configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";
    nix-darwin = {
      url = "github:nix-darwin/nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixos-wsl = {
      url = "github:nix-community/NixOS-WSL/main";
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
    worktrunk = {
      url = "github:max-sixty/worktrunk/v0.72.0";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    herdr-worktrunk = {
      url = "github:devashish2203/herdr-worktrunk";
      flake = false;
    };
    herdr-collie = {
      url = "github:AltanS/collie/v0.26.0";
      flake = false;
    };
    mcp-nixos.url = "github:utensils/mcp-nixos";
    pi-codex-goal = {
      url = "github:matifuentes2/pi-codex-goal";
      flake = false;
    };
    pi-pr-review-goal = {
      url = "git+https://github.com/matifuentes2/pi-pr-review-goal.git";
      flake = false;
    };
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
      nixos-wsl,
      nix-homebrew,
      homebrew-core,
      homebrew-cask,
      herdr,
      worktrunk,
      herdr-worktrunk,
      herdr-collie,
      mcp-nixos,
      pi-codex-goal,
      pi-pr-review-goal,
      sops-nix,
      home-manager,
      ...
    }:
    let
      # Change these values before the first activation if the Mac is
      # Intel-based or either host uses a different local account name.
      darwinSystem = "aarch64-darwin";
      darwinUsername = "matif";
      wslSystem = "x86_64-linux";
      wslUsername = "matif";

      homeSpecialArgs = {
        inherit
          herdr
          worktrunk
          herdr-worktrunk
          herdr-collie
          mcp-nixos
          nixpkgs-unstable
          pi-codex-goal
          pi-pr-review-goal
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

      nixosConfigurations.wsl2 = nixpkgs.lib.nixosSystem {
        system = wslSystem;
        specialArgs = {
          username = wslUsername;
        };
        modules = [
          nixos-wsl.nixosModules.default
          ./hosts/wsl2
          home-manager.nixosModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.users.${wslUsername} = import ./hosts/wsl2/home.nix;
            home-manager.extraSpecialArgs = homeSpecialArgs // {
              username = wslUsername;
            };
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
