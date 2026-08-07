#!/usr/bin/env bash
set -Eeuo pipefail

readonly REPOSITORY_URL="https://github.com/matifuentes2/nixos-config.git"
readonly EXPECTED_USERNAME="matif"
readonly TARGET_DIRECTORY="$HOME/nixos-config"
readonly EXPECTED_REVISION="${NIXOS_CONFIG_REVISION:-}"
readonly BOOTSTRAP_SOURCE_DIRECTORY="${NIXOS_CONFIG_SOURCE_DIRECTORY:-}"
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
[[ $EXPECTED_REVISION =~ ^[0-9a-f]{40}$ ]] || die \
  "NIXOS_CONFIG_REVISION must be the full 40-character commit selected by the installation guide"

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
  [[ -n $BOOTSTRAP_SOURCE_DIRECTORY ]] || die \
    "Git is unavailable and NIXOS_CONFIG_SOURCE_DIRECTORY was not provided"
  [[ -f $BOOTSTRAP_SOURCE_DIRECTORY/flake.nix && -f $BOOTSTRAP_SOURCE_DIRECTORY/flake.lock ]] || die \
    "NIXOS_CONFIG_SOURCE_DIRECTORY is not a complete repository archive"

  log "Building Git from the archive's locked nixpkgs input"
  git_package=$("${nix_command[@]}" build \
    --no-link \
    --no-write-lock-file \
    --print-out-paths \
    "$BOOTSTRAP_SOURCE_DIRECTORY#bootstrap-git")
  git_command=("$git_package/bin/git")
  [[ -x ${git_command[0]} ]] || die "the locked bootstrap Git executable was not built"
fi

verify_checkout() {
  local directory=$1
  local origin head dirty

  [[ ! -L $directory ]] || die "$directory must not be a symbolic link"
  "${git_command[@]}" -C "$directory" rev-parse --is-inside-work-tree >/dev/null 2>&1 || die \
    "$directory exists but is not a valid Git worktree"
  origin=$("${git_command[@]}" -C "$directory" remote get-url origin 2>/dev/null) || die \
    "$directory does not have an origin remote"
  [[ $origin == "$REPOSITORY_URL" ]] || die \
    "$directory has an unexpected origin: $origin"
  head=$("${git_command[@]}" -C "$directory" rev-parse --verify 'HEAD^{commit}') || die \
    "$directory does not have a valid HEAD commit"
  [[ $head == "$EXPECTED_REVISION" ]] || die \
    "$directory is at $head, but this bootstrap release requires $EXPECTED_REVISION; use the normal update procedure instead"
  dirty=$("${git_command[@]}" -C "$directory" status --porcelain --untracked-files=normal) || die \
    "could not inspect the checkout at $directory"
  [[ -z $dirty ]] || die \
    "$directory has uncommitted or untracked files; preserve or remove them before bootstrapping"
}

if [[ -e $TARGET_DIRECTORY || -L $TARGET_DIRECTORY ]]; then
  log "Verifying the existing checkout at $TARGET_DIRECTORY"
  verify_checkout "$TARGET_DIRECTORY"
else
  log "Fetching the immutable configuration revision $EXPECTED_REVISION"
  "${git_command[@]}" init --quiet "$staged_checkout"
  "${git_command[@]}" -C "$staged_checkout" remote add origin "$REPOSITORY_URL"
  "${git_command[@]}" -C "$staged_checkout" fetch --depth 1 origin "$EXPECTED_REVISION"
  fetched_revision=$("${git_command[@]}" -C "$staged_checkout" rev-parse --verify 'FETCH_HEAD^{commit}')
  [[ $fetched_revision == "$EXPECTED_REVISION" ]] || die \
    "Git fetched $fetched_revision instead of $EXPECTED_REVISION"
  "${git_command[@]}" -C "$staged_checkout" checkout --quiet -B main "$EXPECTED_REVISION"
  "${git_command[@]}" -C "$staged_checkout" config branch.main.remote origin
  "${git_command[@]}" -C "$staged_checkout" config branch.main.merge refs/heads/main
  verify_checkout "$staged_checkout"
  mv "$staged_checkout" "$TARGET_DIRECTORY"
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
