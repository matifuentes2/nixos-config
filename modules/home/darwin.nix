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
  updateOrcaSettings = import ../../packages/update-orca-settings.nix { inherit pkgs; };
in

{
  # Orca's Homebrew cask exposes its version-matched CLI at this path. Setting
  # the command explicitly lets the shared Orca skills avoid ambiguous command
  # discovery and always target the Stably Orca CLI.
  home.sessionVariables.ORCA_CLI_COMMAND = "/opt/homebrew/bin/orca";

  # Reapply managed Orca settings on every activation so mutable UI choices
  # cannot override the declarative agent catalog or default.
  home.activation.configureOrcaSettings = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    run ${lib.getExe updateOrcaSettings} \
      "$HOME/Library/Application Support/Orca/profiles/local-default/orca-data.json" \
      ${lib.escapeShellArg (builtins.toJSON orcaSettings)}
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
