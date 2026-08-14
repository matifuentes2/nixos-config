{ pkgs, ... }:

let
  # Keep the age identity root-only while allowing the wheel user to decrypt an
  # encrypted SOPS file after authenticating through sudo.
  sops-decrypt = pkgs.writeShellApplication {
    name = "sops-decrypt";
    text = ''
      if (( $# > 1 )); then
        echo "usage: sops-decrypt [encrypted-file]" >&2
        exit 2
      fi

      secret_file="''${1:-/etc/nixos/secrets/collie.yaml}"
      if [[ ! -f "$secret_file" ]]; then
        echo "sops-decrypt: file not found: $secret_file" >&2
        exit 1
      fi

      exec sudo ${pkgs.coreutils}/bin/env \
        SOPS_AGE_KEY_FILE=/var/lib/sops-nix/key.txt \
        ${pkgs.sops}/bin/sops --decrypt "$secret_file"
    '';
  };
in
{
  imports = [
    ../../modules/home/common.nix
    ../../modules/home/linux.nix
  ];

  home.username = "pi";
  home.homeDirectory = "/home/pi";

  # Keep this at the version used when Home Manager was first configured.
  home.stateVersion = "25.11";

  home.packages = [
    pkgs.sops
    pkgs.tree
  ];

  home.sessionPath = [ "$HOME/.local/bin" ];
  home.file.".local/bin/sops-decrypt".source = "${sops-decrypt}/bin/sops-decrypt";

  home.shellAliases.rebuild = "sudo nixos-rebuild switch --flake /etc/nixos#nixos";
}
