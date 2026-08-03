#!/usr/bin/env bash
set -Eeuo pipefail

readonly REPOSITORY_URL="https://github.com/matifuentes2/nixos-config.git"
readonly BRANCH="main"
readonly TARGET_DIRECTORY="/etc/nixos"
readonly EXPECTED_ROOT_UUID="44444444-4444-4444-8888-888888888888"

die() {
  printf 'bootstrap: %s\n' "$*" >&2
  exit 1
}

[[ $EUID -eq 0 ]] || die "run this script as root (for example, with sudo)"
[[ $(uname -m) == "aarch64" ]] || die "this configuration requires an ARM64 system"
[[ -r /proc/device-tree/model ]] || die "cannot identify this computer as a Raspberry Pi"

model=$(tr -d '\0' </proc/device-tree/model)
[[ $model == *"Raspberry Pi 4"* ]] || die "this configuration targets a Raspberry Pi 4, not: $model"

root_uuid=$(findmnt -n -o UUID /)
[[ $root_uuid == "$EXPECTED_ROOT_UUID" ]] || die \
  "the root filesystem is not from the supported NixOS SD image (UUID: $root_uuid)"

command -v nix >/dev/null || die "Nix is not available"
command -v nixos-rebuild >/dev/null || die "nixos-rebuild is not available"

work_directory=$(mktemp -d /etc/nixos-bootstrap.XXXXXX)
checkout="$work_directory/repository"
trap 'rm -rf "$work_directory"' EXIT

printf 'Cloning %s (%s)...\n' "$REPOSITORY_URL" "$BRANCH"
if command -v git >/dev/null; then
  git clone --branch "$BRANCH" --single-branch "$REPOSITORY_URL" "$checkout"
else
  nix --extra-experimental-features "nix-command flakes" \
    shell nixpkgs#git -c \
    git clone --branch "$BRANCH" --single-branch "$REPOSITORY_URL" "$checkout"
fi

printf 'Checking the flake...\n'
nix --extra-experimental-features "nix-command flakes" flake check "$checkout"

backup=""
if [[ -e $TARGET_DIRECTORY || -L $TARGET_DIRECTORY ]]; then
  backup="${TARGET_DIRECTORY}.backup-$(date -u +%Y%m%dT%H%M%SZ)"
  printf 'Moving the existing configuration to %s...\n' "$backup"
  mv "$TARGET_DIRECTORY" "$backup"
fi

if ! mv "$checkout" "$TARGET_DIRECTORY"; then
  [[ -z $backup ]] || mv "$backup" "$TARGET_DIRECTORY"
  die "could not place the repository at $TARGET_DIRECTORY"
fi

printf 'Applying the NixOS configuration...\n'
if ! nixos-rebuild switch \
  --flake "$TARGET_DIRECTORY#nixos" \
  --option experimental-features "nix-command flakes"; then
  printf 'The previous configuration is still available at %s.\n' "${backup:-<no backup>}" >&2
  die "nixos-rebuild failed"
fi

printf '\nThe system configuration is active. Set the local login and sudo password for pi.\n'
if ! passwd pi </dev/tty; then
  printf 'Could not set the password automatically. Run "sudo passwd pi" from a local console.\n' >&2
fi

printf '\nBootstrap complete. Reboot with: sudo reboot\n'
printf 'After reboot, connect with: ssh pi@<raspberry-pi-address>\n'
