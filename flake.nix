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
    disko = {
      url = "github:nix-community/disko";
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
    omp = {
      url = "github:can1357/oh-my-pi";
      inputs.nixpkgs.follows = "nixpkgs";
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
      url = "github:AltanS/collie/v0.36.1";
      flake = false;
    };
    mcp-nixos.url = "github:utensils/mcp-nixos";
    pi-codex-goal = {
      url = "github:matifuentes2/pi-codex-goal";
      flake = false;
    };
    pi-pr-review-goal = {
      url = "github:matifuentes2/pi-pr-review-goal";
      flake = false;
    };
    pi-parallel-go-pr-herdr = {
      url = "github:matifuentes2/pi-parallel-go-pr-herdr";
      flake = false;
    };
    pi-execution-time = {
      url = "github:lukaspanni/pi-execution-time/81b18e039ddeac6d23cc1e6e176bdb158de19590";
      flake = false;
    };
    orca = {
      url = "github:stablyai/orca/v1.4.192";
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
      disko,
      nix-homebrew,
      homebrew-core,
      homebrew-cask,
      omp,
      herdr,
      worktrunk,
      herdr-worktrunk,
      herdr-collie,
      mcp-nixos,
      pi-codex-goal,
      pi-pr-review-goal,
      pi-parallel-go-pr-herdr,
      pi-execution-time,
      orca,
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
      amd64System = "x86_64-linux";
      amd64Username = "matif";

      homeSpecialArgs = {
        enableCollieService = false;
        inherit
          herdr
          worktrunk
          herdr-worktrunk
          herdr-collie
          mcp-nixos
          nixpkgs-unstable
          pi-codex-goal
          pi-pr-review-goal
          pi-parallel-go-pr-herdr
          pi-execution-time
          orca
          ;
      };

      bootstrapSystems = [
        "aarch64-linux"
        "aarch64-darwin"
        "x86_64-linux"
      ];
    in
    {
      # Importing this module is inert until its explicit enable option is set.
      # It includes sops-nix so future physical x86-64 hosts can opt in without
      # making local-worker behavior a default for NixOS or amd64 systems.
      nixosModules.ci-cd-local-worker = {
        imports = [
          sops-nix.nixosModules.sops
          ./modules/system/ci-cd-local-worker.nix
        ];
      };

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
        // nixpkgs.lib.optionalAttrs (system == amd64System) {
          inherit (disko.packages.${system}) disko disko-install;
        }
      );

      checks.${amd64System}.ci-cd-local-worker-module = import ./tests/ci-cd-local-worker-module.nix {
        inherit nixpkgs sops-nix;
      };

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
            home-manager.extraSpecialArgs = homeSpecialArgs // {
              enableCollieService = true;
            };
          }
        ];
      };

      nixosConfigurations.amd64-lenovo-legion-y720 = nixpkgs.lib.nixosSystem {
        system = amd64System;
        specialArgs = {
          username = amd64Username;
        };
        modules = [
          disko.nixosModules.disko
          sops-nix.nixosModules.sops
          ./hosts/amd64-lenovo-legion-y720
          home-manager.nixosModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.users.${amd64Username} = import ./hosts/amd64-lenovo-legion-y720/home.nix;
            home-manager.extraSpecialArgs = homeSpecialArgs // {
              username = amd64Username;
              enableCollieService = true;
            };
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
          inherit
            homebrew-core
            homebrew-cask
            ;
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
              inherit omp;
            };
          }
        ];
      };
    };
}
