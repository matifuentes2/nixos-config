#!/usr/bin/env bash
set -Eeuo pipefail

if [[ $# != 2 ]]; then
  echo 'usage: update-orca-settings PROFILE_PATH SETTINGS_JSON' >&2
  exit 2
fi

data_file=$1
managed_settings=$2
umask 077
mkdir -p -- "$(dirname -- "$data_file")"
tmp_file=$(mktemp "$data_file.tmp.XXXXXX")
trap 'rm -f -- "$tmp_file"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

if [[ -e "$data_file" || -L "$data_file" ]]; then
  # Slurping also rejects empty files and multiple top-level JSON values.
  # Never replace the original unless parsing and schema validation succeed.
  jq --exit-status --slurp --argjson managedSettings "$managed_settings" '
    if length != 1 or (.[0] | type) != "object" then
      error("Orca profile must contain exactly one JSON object")
    else .[0] end
    | if .settings != null and (.settings | type) != "object" then
        error("Orca settings must be an object")
      else . end
    | if ($managedSettings | type) != "object" then
        error("Managed Orca settings must be an object")
      else .settings = ((.settings // {}) + $managedSettings) end
  ' "$data_file" >"$tmp_file"
else
  jq --exit-status --null-input --argjson managedSettings "$managed_settings" '
    if ($managedSettings | type) != "object" then
      error("Managed Orca settings must be an object")
    else {schemaVersion: 1, settings: $managedSettings} end
  ' >"$tmp_file"
fi

# The temporary file is on the same filesystem, so replacement is atomic.
mv -- "$tmp_file" "$data_file"
