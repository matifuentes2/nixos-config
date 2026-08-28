{
  lib,
  pkgs,
  worktrunk,
  username,
  ...
}:
let
  # Orca stores agent picker state in its mutable profile. Keep the macOS
  # catalog reproducible while leaving Pi and unrelated agents enabled.
  orcaSettings = {
    experimentalEphemeralVms = false;
    defaultTuiAgent = "omp";
    disabledTuiAgents = [
      "claude"
      "claude-agent-teams"
      "codex"
    ];
  };
  orcaSettingsJson = builtins.toJSON orcaSettings;
in

{
  # Orca's Homebrew cask exposes its version-matched CLI at this path. Setting
  # the command explicitly lets the shared Orca skills avoid ambiguous command
  # discovery and always target the Stably Orca CLI.
  home.sessionVariables.ORCA_CLI_COMMAND = "/opt/homebrew/bin/orca";

  # Reapply managed Orca settings on every activation so mutable UI choices
  # cannot override the declarative agent catalog or default.
  home.activation.configureOrcaSettings = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    data_dir="$HOME/Library/Application Support/Orca/profiles/local-default"
    data_file="$data_dir/orca-data.json"
    run mkdir -p "$data_dir"

    if [[ -f "$data_file" ]]; then
      tmp_file="$(${lib.getExe' pkgs.coreutils "mktemp"} "$data_file.tmp.XXXXXX")"
      ${lib.getExe pkgs.jq} \
        --argjson managedSettings '${orcaSettingsJson}' \
        '.settings = ((.settings // {}) + $managedSettings)' \
        "$data_file" >"$tmp_file"
      run mv "$tmp_file" "$data_file"
    else
      ${lib.getExe pkgs.jq} -n \
        --argjson managedSettings '${orcaSettingsJson}' \
        '{schemaVersion: 1, settings: $managedSettings}' \
        >"$data_file"
    fi
  '';

  # Clear completion state once when activating a generation. Deleting it from
  # every interactive shell startup would disable zsh's completion cache and
  # unnecessarily slow down new terminals.
  home.activation.clearStaleZshCompletionCache = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    run rm -f "$HOME"/.zcompdump "$HOME"/.zcompdump-*
  '';

  # zsh is the standard interactive shell on macOS. Shared shell tools enable
  # their zsh integration in modules/home/common.nix.
  programs.zsh = {
    enable = true;
    completionInit = ''
      # Ignore missing completion directories left by package-manager changes,
      # but preserve the Homebrew completion directory whenever it really exists.
      typeset -gaU fpath
      fpath=(''${^fpath}(N))
      autoload -U compinit && compinit
    '';
    initContent = ''
      # Prefer declarative Nix profiles over any mutable Homebrew/npm shims.
      typeset -U path
      path=(
        "/etc/profiles/per-user/${username}/bin"
        "$HOME/.nix-profile/bin"
        "/run/current-system/sw/bin"
        $path
      )

      # Worktrunk must run as a shell function so `wt switch` can change the
      # current shell's directory. Generate the integration from the pinned
      # Nix package instead of letting `wt config shell install` edit ~/.zshrc.
      eval "$(${
        lib.getExe worktrunk.packages.${pkgs.stdenv.hostPlatform.system}.default
      } config shell init zsh)"

      bindkey -v
    '';
  };
}
