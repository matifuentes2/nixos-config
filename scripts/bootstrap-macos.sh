#!/usr/bin/env bash
set -Eeuo pipefail

readonly REPOSITORY_URL="https://github.com/matifuentes2/nixos-config.git"
readonly BRANCH="main"
readonly EXPECTED_USERNAME="matif"
readonly TARGET_DIRECTORY="$HOME/nixos-config"

log() {
  printf '\n==> %s\n' "$*"
}

die() {
  printf 'macOS bootstrap: %s\n' "$*" >&2
  exit 1
}

[[ $(uname -s) == "Darwin" ]] || die "this script must run on macOS"
[[ $(uname -m) == "arm64" ]] || die "this configuration currently requires an Apple Silicon Mac"
[[ $EUID -ne 0 ]] || die "run this script as your normal user, not with sudo"
[[ $(id -un) == "$EXPECTED_USERNAME" ]] || die \
  "this configuration expects the macOS short account name '$EXPECTED_USERNAME' (current: $(id -un))"

if ! command -v nix >/dev/null 2>&1; then
  log "Installing Lix (the Nix implementation recommended by nix-darwin)"
  curl --proto '=https' --tlsv1.2 -fsSL https://install.lix.systems/lix \
    | sh -s -- install --no-confirm
fi

# Make a newly installed Nix available without requiring a new Terminal window.
if ! command -v nix >/dev/null 2>&1; then
  for profile in \
    /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh \
    "$HOME/.nix-profile/etc/profile.d/nix.sh"
  do
    if [[ -r $profile ]]; then
      set +u
      # shellcheck disable=SC1090
      . "$profile"
      set -u
      break
    fi
  done
fi

if ! command -v nix >/dev/null 2>&1; then
  export PATH="/nix/var/nix/profiles/default/bin:$HOME/.nix-profile/bin:$PATH"
fi
command -v nix >/dev/null 2>&1 || die "Nix was installed but is not available; open a new Terminal and rerun this command"

nix_command=(nix --extra-experimental-features "nix-command flakes")

if [[ -e $TARGET_DIRECTORY ]]; then
  [[ -d $TARGET_DIRECTORY/.git ]] || die \
    "$TARGET_DIRECTORY already exists but is not a Git checkout; move it aside and rerun"
  log "Using the existing checkout at $TARGET_DIRECTORY"
else
  log "Cloning the configuration into $TARGET_DIRECTORY"
  if command -v git >/dev/null 2>&1 && git --version >/dev/null 2>&1; then
    git clone --branch "$BRANCH" --single-branch "$REPOSITORY_URL" "$TARGET_DIRECTORY"
  else
    "${nix_command[@]}" shell github:NixOS/nixpkgs/nixos-unstable#git -c \
      git clone --branch "$BRANCH" --single-branch "$REPOSITORY_URL" "$TARGET_DIRECTORY"
  fi
fi

log "Checking the pinned configuration"
"${nix_command[@]}" flake check --no-write-lock-file "$TARGET_DIRECTORY"

log "Building the macOS configuration"
system_path=$("${nix_command[@]}" build \
  --no-link \
  --no-write-lock-file \
  --print-out-paths \
  "$TARGET_DIRECTORY#darwinConfigurations.macbook.system")

darwin_rebuild="$system_path/sw/bin/darwin-rebuild"
[[ -x $darwin_rebuild ]] || die "the built system does not contain darwin-rebuild at $darwin_rebuild"

log "Activating nix-darwin, Home Manager, Homebrew, and the declared applications"
sudo "$darwin_rebuild" switch \
  --flake "$TARGET_DIRECTORY#macbook" \
  --option experimental-features "nix-command flakes"

printf '\nBootstrap complete. Open a new Terminal to use the configured environment.\n'
printf 'Future updates: cd %s && git pull --ff-only && rebuild\n' "$TARGET_DIRECTORY"
