{ lib, username, ... }:

{
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

      bindkey -v
    '';
  };
}
