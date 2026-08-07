{
  config,
  homebrew-cask,
  homebrew-core,
  lib,
  pkgs,
  username,
  ...
}:

{
  imports = [
    ../../modules/system/common.nix
  ];

  networking.hostName = "macbook";
  networking.computerName = "MacBook";

  # Required by user-scoped nix-darwin options and Home Manager.
  system.primaryUser = username;
  users.users.${username}.home = "/Users/${username}";

  # Configure the shell shipped with macOS. User-level zsh configuration lives
  # in modules/home/darwin.nix.
  programs.zsh.enable = true;

  # Fully declarative taps replace Homebrew's mutable Library/Taps directory
  # with a Nix-store symlink. Preserve existing checkouts during the one-time
  # migration before nix-homebrew validates that path.
  system.activationScripts.setup-homebrew.text = lib.mkBefore ''
    taps="/opt/homebrew/Library/Taps"
    backup="/opt/homebrew/Library/Taps.pre-nix-homebrew"

    if [[ -d "$taps" && ! -L "$taps" ]]; then
      if [[ -e "$backup" || -L "$backup" ]]; then
        >&2 echo "error: Cannot preserve existing Homebrew taps because $backup already exists"
        exit 1
      fi

      >&2 echo "preserving existing Homebrew taps in $backup..."
      /bin/mv "$taps" "$backup"
    fi
  '';

  # Remove any legacy Homebrew/npm Pi install so the declarative Home Manager
  # wrapper wins on PATH. Old global installs have existed under both the
  # historical @mariozechner scope and the current @earendil-works scope.
  system.activationScripts.cleanup-legacy-pi.text = lib.mkAfter ''
    legacy_bin="/opt/homebrew/bin/pi"
    legacy_target="$(/usr/bin/readlink "$legacy_bin" 2>/dev/null || true)"
    remove_legacy_bin=false

    case "$legacy_target" in
      *"@mariozechner/pi-coding-agent"*|*"@earendil-works/pi-coding-agent"*)
        remove_legacy_bin=true
        ;;
    esac

    # npm normally creates a symlink, but also recognize a generated text shim.
    if [[ "$remove_legacy_bin" == false && -f "$legacy_bin" ]] \
      && /usr/bin/grep -aEq \
        '@(mariozechner|earendil-works)/pi-coding-agent' "$legacy_bin"; then
      remove_legacy_bin=true
    fi

    if [[ "$remove_legacy_bin" == true ]]; then
      >&2 echo "removing legacy Homebrew pi shim at $legacy_bin"
      /bin/rm -f "$legacy_bin"
    elif [[ -e "$legacy_bin" || -L "$legacy_bin" ]]; then
      >&2 echo "preserving unrelated executable at $legacy_bin"
    fi

    for legacy_lib in \
      /opt/homebrew/lib/node_modules/@mariozechner/pi-coding-agent \
      /opt/homebrew/lib/node_modules/@earendil-works/pi-coding-agent
    do
      if [[ -d "$legacy_lib" ]]; then
        >&2 echo "removing legacy Homebrew pi package at $legacy_lib"
        /bin/rm -rf "$legacy_lib"
      fi
    done
  '';

  # nix-homebrew installs the pinned Homebrew distribution. nix-darwin then
  # manages the applications below with Homebrew Bundle.
  nix-homebrew = {
    enable = true;
    user = username;
    autoMigrate = true;
    taps = {
      "homebrew/homebrew-core" = homebrew-core;
      "homebrew/homebrew-cask" = homebrew-cask;
    };
    mutableTaps = false;
  };

  homebrew = {
    enable = true;
    enableBashIntegration = false;
    enableZshIntegration = false;
    taps = builtins.attrNames config.nix-homebrew.taps;
    casks = [
      "betterdisplay"
      "bitwarden"
      "chatgpt"
      "google-chrome"
      "hiddenbar"
      "karabiner-elements"
      "kitty"
      "raycast"
      "rectangle"
      "whatsapp"
    ];
  };

  fonts.packages = [ pkgs.jetbrains-mono ];

  # Keep this value when upgrading nix-darwin; it controls compatibility
  # defaults rather than the installed macOS version.
  system.stateVersion = 6;
}
