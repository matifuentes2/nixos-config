#!/usr/bin/env bash
set -Eeuo pipefail

readonly REPOSITORY_URL="https://github.com/matifuentes2/nixos-config.git"
readonly TARGET_DIRECTORY="/etc/nixos"
readonly SOPS_AGE_KEY_FILE="/var/lib/sops-nix/key.txt"
readonly BITWARDEN_ITEM_NAME="${BITWARDEN_ITEM_NAME:-NixOS SOPS age identity}"
readonly EXPECTED_ROOT_UUID="44444444-4444-4444-8888-888888888888"
readonly EXPECTED_REVISION="${NIXOS_CONFIG_REVISION:-}"
readonly BOOTSTRAP_SOURCE_DIRECTORY="${NIXOS_CONFIG_SOURCE_DIRECTORY:-}"

die() {
  printf 'bootstrap: %s\n' "$*" >&2
  exit 1
}

[[ $EUID -eq 0 ]] || die "run this script as root (for example, with sudo)"
[[ $(uname -m) == "aarch64" ]] || die "this configuration requires an ARM64 system"
[[ -r /proc/device-tree/model ]] || die "cannot identify this computer as a Raspberry Pi"
[[ $EXPECTED_REVISION =~ ^[0-9a-f]{40}$ ]] || die \
  "NIXOS_CONFIG_REVISION must be the full 40-character commit selected by the installation guide"

model=$(tr -d '\0' </proc/device-tree/model)
[[ $model == *"Raspberry Pi 4"* ]] || die "this configuration targets a Raspberry Pi 4, not: $model"

root_uuid=$(findmnt -n -o UUID /)
[[ $root_uuid == "$EXPECTED_ROOT_UUID" ]] || die \
  "the root filesystem is not from the supported NixOS SD image (UUID: $root_uuid)"

command -v nix >/dev/null || die "Nix is not available"
command -v nixos-rebuild >/dev/null || die "nixos-rebuild is not available"

work_directory=$(mktemp -d /etc/nixos-bootstrap.XXXXXX)
checkout="$work_directory/repository"
bitwarden_directory="$work_directory/bitwarden"
staged_age_key="$work_directory/nixos.agekey"

cleanup() {
  if [[ -n ${BW_SESSION:-} && -x ${bw:-} ]]; then
    "$bw" logout >/dev/null 2>&1 || true
  fi
  unset BW_SESSION BITWARDENCLI_APPDATA_DIR
  rm -rf "$work_directory"
}
trap cleanup EXIT

nix_command=(nix --extra-experimental-features "nix-command flakes")
git_command=()
if command -v git >/dev/null 2>&1 && git --version >/dev/null 2>&1; then
  git_command=(git)
else
  [[ -n $BOOTSTRAP_SOURCE_DIRECTORY ]] || die \
    "Git is unavailable and NIXOS_CONFIG_SOURCE_DIRECTORY was not provided"
  [[ -f $BOOTSTRAP_SOURCE_DIRECTORY/flake.nix && -f $BOOTSTRAP_SOURCE_DIRECTORY/flake.lock ]] || die \
    "NIXOS_CONFIG_SOURCE_DIRECTORY is not a complete repository archive"

  printf "Building Git from the archive's locked nixpkgs input...\n"
  git_package=$("${nix_command[@]}" build \
    --no-link \
    --no-write-lock-file \
    --print-out-paths \
    "$BOOTSTRAP_SOURCE_DIRECTORY#bootstrap-git")
  git_command=("$git_package/bin/git")
  [[ -x ${git_command[0]} ]] || die "the locked bootstrap Git executable was not built"
fi

printf 'Fetching immutable configuration revision %s...\n' "$EXPECTED_REVISION"
"${git_command[@]}" init --quiet "$checkout"
"${git_command[@]}" -C "$checkout" remote add origin "$REPOSITORY_URL"
"${git_command[@]}" -C "$checkout" fetch --depth 1 origin "$EXPECTED_REVISION"
fetched_revision=$("${git_command[@]}" -C "$checkout" rev-parse --verify 'FETCH_HEAD^{commit}')
[[ $fetched_revision == "$EXPECTED_REVISION" ]] || die \
  "Git fetched $fetched_revision instead of $EXPECTED_REVISION"
"${git_command[@]}" -C "$checkout" checkout --quiet -B main "$EXPECTED_REVISION"
"${git_command[@]}" -C "$checkout" config branch.main.remote origin
"${git_command[@]}" -C "$checkout" config branch.main.merge refs/heads/main
[[ -z $("${git_command[@]}" -C "$checkout" status --porcelain --untracked-files=normal) ]] || die \
  "the fetched checkout is unexpectedly dirty"

mapfile -t sops_recipients < <(
  awk '$1 == "-" && $2 == "&nixos" { print $3 }' "$checkout/.sops.yaml"
)
[[ ${#sops_recipients[@]} -eq 1 && ${sops_recipients[0]} == age1* ]] || die \
  "could not identify the expected NixOS age recipient in .sops.yaml"
expected_sops_recipient=${sops_recipients[0]}

printf 'Preparing the pinned Bitwarden and age tools...\n'
bitwarden_package=$("${nix_command[@]}" \
  build --no-link --no-write-lock-file --print-out-paths \
  "$checkout#nixosConfigurations.nixos.pkgs.bitwarden-cli")
age_package=$("${nix_command[@]}" \
  build --no-link --no-write-lock-file --print-out-paths \
  "$checkout#nixosConfigurations.nixos.pkgs.age")
bw="$bitwarden_package/bin/bw"
age_keygen="$age_package/bin/age-keygen"

install -d -o root -g root -m 0700 "$(dirname "$SOPS_AGE_KEY_FILE")"
if [[ -e $SOPS_AGE_KEY_FILE || -L $SOPS_AGE_KEY_FILE ]]; then
  [[ -f $SOPS_AGE_KEY_FILE && -r $SOPS_AGE_KEY_FILE ]] || die \
    "$SOPS_AGE_KEY_FILE is not a readable regular file"
  installed_recipient=$("$age_keygen" -y "$SOPS_AGE_KEY_FILE" 2>/dev/null) || die \
    "the installed SOPS age identity is invalid"
  [[ $installed_recipient == "$expected_sops_recipient" ]] || die \
    "the installed SOPS age identity does not match $expected_sops_recipient"
  chmod 0600 "$SOPS_AGE_KEY_FILE"
  chown root:root "$SOPS_AGE_KEY_FILE"
  printf 'Using the existing SOPS age identity at %s.\n' "$SOPS_AGE_KEY_FILE"
else
  if ! : </dev/tty 2>/dev/null; then
    die "Bitwarden login requires an interactive console"
  fi

  mkdir -m 0700 "$bitwarden_directory"
  export BITWARDENCLI_APPDATA_DIR="$bitwarden_directory"
  printf '\nLog in to Bitwarden to retrieve the secure note %q.\n' "$BITWARDEN_ITEM_NAME"
  printf 'Use your master password and Authenticator app code when prompted.\n'
  BW_SESSION=$("$bw" login --raw --method 0 </dev/tty) || die "Bitwarden login failed"
  export BW_SESSION
  [[ -n $BW_SESSION ]] || die "Bitwarden returned an empty session"

  "$bw" sync >/dev/null || die "Bitwarden vault sync failed"
  if ! (umask 077; "$bw" get notes "$BITWARDEN_ITEM_NAME" >"$staged_age_key"); then
    die "could not read Bitwarden secure note: $BITWARDEN_ITEM_NAME"
  fi
  "$bw" logout >/dev/null 2>&1 || true
  unset BW_SESSION BITWARDENCLI_APPDATA_DIR

  fetched_recipient=$("$age_keygen" -y "$staged_age_key" 2>/dev/null) || die \
    "the Bitwarden note does not contain a valid age identity"
  [[ $fetched_recipient == "$expected_sops_recipient" ]] || die \
    "the Bitwarden age identity does not match $expected_sops_recipient"

  install -o root -g root -m 0600 "$staged_age_key" "$SOPS_AGE_KEY_FILE"
  printf 'Installed the SOPS age identity at %s.\n' "$SOPS_AGE_KEY_FILE"
fi

printf 'Checking the flake...\n'
"${nix_command[@]}" flake check --no-write-lock-file "$checkout"

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
