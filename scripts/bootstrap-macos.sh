#!/usr/bin/env bash
set -Eeuo pipefail

readonly REPOSITORY_URL="https://github.com/matifuentes2/nixos-config.git"
readonly EXPECTED_USERNAME="matif"
readonly TARGET_DIRECTORY="$HOME/nixos-config"
readonly NIX_INSTALLER_VERSION="2.35.1"
readonly NIX_INSTALLER_URL="https://releases.nixos.org/nix/nix-${NIX_INSTALLER_VERSION}/install"
readonly NIX_INSTALLER_SHA256="34e0ef63ec1f3e552e15069660afd9a0a23f69009e340c33067595252888286c"

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

work_directory=$(mktemp -d "$HOME/.nixos-config-bootstrap.XXXXXX")
staged_checkout="$work_directory/repository"
nix_installer="$work_directory/nix-installer"

cleanup() {
  rm -rf "$work_directory"
}
trap cleanup EXIT

if ! command -v nix >/dev/null 2>&1; then
  log "Installing pinned Nix ${NIX_INSTALLER_VERSION} in multi-user daemon mode"
  curl --proto '=https' --tlsv1.2 -fsSL "$NIX_INSTALLER_URL" -o "$nix_installer"
  installer_sha256=$(shasum -a 256 "$nix_installer" | awk '{ print $1 }')
  [[ $installer_sha256 == "$NIX_INSTALLER_SHA256" ]] || die \
    "the Nix installer checksum did not match (expected $NIX_INSTALLER_SHA256, got $installer_sha256)"
  sh "$nix_installer" --daemon --yes
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
command -v nix >/dev/null 2>&1 || die \
  "Nix was installed but is not available; open a new Terminal and rerun the documented command"

nix_command=(nix --extra-experimental-features "nix-command flakes")
git_command=()
git_candidate=$(command -v git 2>/dev/null || true)

# The /usr/bin/git shim opens the Command Line Tools installer on a stock Mac.
# Avoid invoking it when the tools are absent and use the flake-pinned Git.
if [[ $git_candidate == "/usr/bin/git" ]] && ! xcode-select -p >/dev/null 2>&1; then
  git_candidate=""
fi
if [[ -n $git_candidate ]] && "$git_candidate" --version >/dev/null 2>&1; then
  git_command=("$git_candidate")
else
  log "Fetching Git from this repository's locked nixpkgs input"
  git_package=$("${nix_command[@]}" build \
    --no-link \
    --print-out-paths \
    "github:matifuentes2/nixos-config#bootstrap-git")
  git_command=("$git_package/bin/git")
  [[ -x ${git_command[0]} ]] || die "the bootstrap Git executable was not built"
fi

verify_checkout() {
  local directory=$1
  local origin

  [[ ! -L $directory ]] || die "$directory must not be a symbolic link"
  "${git_command[@]}" -C "$directory" rev-parse --is-inside-work-tree >/dev/null 2>&1 || die \
    "$directory exists but is not a valid Git worktree"
  origin=$("${git_command[@]}" -C "$directory" remote get-url origin 2>/dev/null) || die \
    "$directory does not have an origin remote"
  [[ $origin == "$REPOSITORY_URL" ]] || die \
    "$directory has an unexpected origin: $origin"
}

if [[ -e $TARGET_DIRECTORY || -L $TARGET_DIRECTORY ]]; then
  log "Reusing the existing checkout at $TARGET_DIRECTORY"
  verify_checkout "$TARGET_DIRECTORY"
else
  log "Cloning $REPOSITORY_URL"
  "${git_command[@]}" clone --quiet "$REPOSITORY_URL" "$staged_checkout"
  mv "$staged_checkout" "$TARGET_DIRECTORY"
fi

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
