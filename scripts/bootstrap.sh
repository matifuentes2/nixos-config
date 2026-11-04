#!/usr/bin/env bash
# Raspberry Pi 4 bootstrap. Run from the stock NixOS SD image with:
#   sudo nix --extra-experimental-features 'nix-command flakes' run github:matifuentes2/nixos-config
# The flake app supplies git, bitwarden-cli and age on PATH and sets
# NIXOS_CONFIG_REVISION to the commit that was run.
set -Eeuo pipefail

readonly REPOSITORY_URL="https://github.com/matifuentes2/nixos-config.git"
readonly TARGET_DIRECTORY="/etc/nixos"
readonly SOPS_AGE_KEY_FILE="/var/lib/sops-nix/key.txt"
readonly BITWARDEN_ITEM_NAME="${BITWARDEN_ITEM_NAME:-NixOS SOPS age identity}"
readonly EXPECTED_ROOT_UUID="44444444-4444-4444-8888-888888888888"
readonly REVISION="${NIXOS_CONFIG_REVISION:-}"

die() {
  printf 'bootstrap: %s\n' "$*" >&2
  exit 1
}

if [[ $EUID -ne 0 ]]; then
  exec sudo --preserve-env=BITWARDEN_ITEM_NAME "$0" "$@"
fi

for tool in git bw age-keygen nixos-rebuild; do
  command -v "$tool" >/dev/null || die "$tool is not available; run this through the flake app"
done

[[ $(uname -m) == "aarch64" ]] || die "this configuration requires an ARM64 system"
[[ -r /proc/device-tree/model ]] || die "cannot identify this computer as a Raspberry Pi"
model=$(tr -d '\0' </proc/device-tree/model)
[[ $model == *"Raspberry Pi 4"* ]] || die "this configuration targets a Raspberry Pi 4, not: $model"
root_uuid=$(findmnt -n -o UUID /)
[[ $root_uuid == "$EXPECTED_ROOT_UUID" ]] || die \
  "the root filesystem is not from the supported NixOS SD image (UUID: $root_uuid)"

work_directory=$(mktemp -d /etc/nixos-bootstrap.XXXXXX)
checkout="$work_directory/repository"
staged_age_key="$work_directory/nixos.agekey"

cleanup() {
  if [[ -n ${BW_SESSION:-} ]]; then
    bw logout >/dev/null 2>&1 || true
  fi
  unset BW_SESSION BITWARDENCLI_APPDATA_DIR
  rm -rf "$work_directory"
}
trap cleanup EXIT

printf 'Cloning %s...\n' "$REPOSITORY_URL"
git clone --quiet "$REPOSITORY_URL" "$checkout"
if [[ -n $REVISION ]]; then
  git -C "$checkout" checkout --quiet -B main "$REVISION"
  git -C "$checkout" branch --quiet --set-upstream-to=origin/main main
fi
printf 'Using configuration commit %s.\n' "$(git -C "$checkout" rev-parse HEAD)"

expected_sops_recipient=$(awk '$1 == "-" && $2 == "&nixos" { print $3 }' "$checkout/.sops.yaml")
[[ $expected_sops_recipient == age1* ]] || die \
  "could not identify the NixOS age recipient in .sops.yaml"

install -d -o root -g root -m 0700 "$(dirname "$SOPS_AGE_KEY_FILE")"
if [[ -f $SOPS_AGE_KEY_FILE ]]; then
  installed_recipient=$(age-keygen -y "$SOPS_AGE_KEY_FILE" 2>/dev/null) || die \
    "the installed SOPS age identity is invalid"
  [[ $installed_recipient == "$expected_sops_recipient" ]] || die \
    "the installed SOPS age identity does not match $expected_sops_recipient"
  printf 'Using the existing SOPS age identity at %s.\n' "$SOPS_AGE_KEY_FILE"
else
  : </dev/tty 2>/dev/null || die "Bitwarden login requires an interactive console"

  export BITWARDENCLI_APPDATA_DIR="$work_directory/bitwarden"
  mkdir -m 0700 "$BITWARDENCLI_APPDATA_DIR"
  printf '\nLog in to Bitwarden to retrieve the secure note %q.\n' "$BITWARDEN_ITEM_NAME"
  printf 'Use your master password and Authenticator app code when prompted.\n'
  BW_SESSION=$(bw login --raw --method 0 </dev/tty) || die "Bitwarden login failed"
  export BW_SESSION
  bw sync >/dev/null || die "Bitwarden vault sync failed"
  (umask 077; bw get notes "$BITWARDEN_ITEM_NAME" >"$staged_age_key") || die \
    "could not read Bitwarden secure note: $BITWARDEN_ITEM_NAME"
  bw logout >/dev/null 2>&1 || true
  unset BW_SESSION BITWARDENCLI_APPDATA_DIR

  fetched_recipient=$(age-keygen -y "$staged_age_key" 2>/dev/null) || die \
    "the Bitwarden note does not contain a valid age identity"
  [[ $fetched_recipient == "$expected_sops_recipient" ]] || die \
    "the Bitwarden age identity does not match $expected_sops_recipient"
  install -o root -g root -m 0600 "$staged_age_key" "$SOPS_AGE_KEY_FILE"
  printf 'Installed the SOPS age identity at %s.\n' "$SOPS_AGE_KEY_FILE"
fi

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

printf 'Applying the NixOS configuration (this takes a while)...\n'
nixos-rebuild switch \
  --flake "$TARGET_DIRECTORY#nixos" \
  --option experimental-features "nix-command flakes" || die \
  "nixos-rebuild failed; the previous configuration is at ${backup:-<no backup>}"

printf '\nThe system configuration is active. Set the login and sudo password for pi.\n'
passwd pi </dev/tty || printf 'Could not set the password. Run "sudo passwd pi".\n' >&2

printf '\nBootstrap complete. Reboot with: sudo reboot\n'
