#!/usr/bin/env bash
set -Eeuo pipefail

readonly REPOSITORY="matifuentes2/nixos-config"
readonly MAIN_BRANCH="main"
readonly REQUIRED_CHECK_REPOSITORY="Flake, shell, and public-repository checks"

repo_root=$(git rev-parse --show-toplevel)
cd "$repo_root"

command -v gh >/dev/null 2>&1 || {
  printf 'GitHub settings audit: gh is required\n' >&2
  exit 1
}
gh auth status >/dev/null 2>&1 || {
  printf 'GitHub settings audit: authenticate gh before running this audit\n' >&2
  exit 1
}

expect_api_true() {
  local description=$1
  local endpoint=$2
  local query=$3
  local result

  result=$(gh api "$endpoint" --jq "$query")
  [[ $result == "true" ]] || {
    printf 'GitHub settings audit failed: %s\n' "$description" >&2
    exit 1
  }
  printf 'ok: %s\n' "$description"
}

protection_endpoint="repos/$REPOSITORY/branches/$MAIN_BRANCH/protection"
expect_api_true "required checks are strict" "$protection_endpoint" \
  '.required_status_checks.strict == true'
expect_api_true "repository validation is the only required check" "$protection_endpoint" \
  "(.required_status_checks.contexts == [\"$REQUIRED_CHECK_REPOSITORY\"])"
expect_api_true "branch protection applies to administrators" "$protection_endpoint" \
  '.enforce_admins.enabled == true'
expect_api_true "pull requests are required" "$protection_endpoint" \
  '.required_pull_request_reviews != null'
expect_api_true "linear history is required" "$protection_endpoint" \
  '.required_linear_history.enabled == true'
expect_api_true "conversation resolution is required" "$protection_endpoint" \
  '.required_conversation_resolution.enabled == true'
expect_api_true "force pushes are disabled" "$protection_endpoint" \
  '.allow_force_pushes.enabled == false'
expect_api_true "branch deletion is disabled" "$protection_endpoint" \
  '.allow_deletions.enabled == false'

printf 'GitHub branch protection controls passed.\n'
