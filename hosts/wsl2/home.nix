{
  config,
  lib,
  pkgs,
  username,
  ...
}:

{
  # The Linux module currently owns the Raspberry Pi's Hyprland desktop, so a
  # terminal-oriented WSL environment imports only the portable shared module.
  imports = [
    ../../modules/home/common.nix
  ];

  home.username = username;
  home.homeDirectory = "/home/${username}";

  # Keep this at the Home Manager version used for the first WSL2 activation.
  home.stateVersion = "26.11";

  home.packages = [
    (pkgs.callPackage ../../packages/t3-code.nix { })
    pkgs.tree
  ];

  home.shellAliases.rebuild = "sudo nixos-rebuild switch --flake ~/nixos-config#wsl2";

  home.sessionVariables.T3CODE_PORT = "3773";

  # T3 Code Desktop chooses its bind address from this setting, rather than
  # T3CODE_HOST. Merge it into the writable file so other app preferences survive.
  home.activation.configureT3NetworkAccess = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    settings_dir=${lib.escapeShellArg "${config.home.homeDirectory}/.t3/userdata"}
    settings_file="$settings_dir/desktop-settings.json"
    if [[ ! -v DRY_RUN ]]; then
      mkdir -p "$settings_dir"
      settings_input=/dev/null
      if [[ -f "$settings_file" ]]; then
        settings_input="$settings_file"
      fi
      settings_tmp=$(mktemp "$settings_dir/desktop-settings.json.XXXXXX")
      if ${lib.getExe pkgs.jq} --slurp '(.[0] // {}) + {serverExposureMode: "network-accessible"}' \
        "$settings_input" \
        > "$settings_tmp"; then
        mv "$settings_tmp" "$settings_file"
      else
        rm -f "$settings_tmp"
        exit 1
      fi
    fi
  '';
}
