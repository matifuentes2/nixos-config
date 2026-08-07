#!/usr/bin/env bash
set -Eeuo pipefail

readonly REPOSITORY="matifuentes2/nixos-config"
readonly MAIN_BRANCH="main"
readonly TAG_RULESET_NAME="Protect bootstrap release tags"
readonly TAG_PATTERN="refs/tags/bootstrap-v*"
readonly REQUIRED_CHECK_REPOSITORY="Flake, shell, and public-repository checks"
readonly REQUIRED_CHECK_DARWIN="Build Apple Silicon nix-darwin configuration"

repo_root=$(git rev-parse --show-toplevel)
cd "$repo_root"

# The repository root is resolved dynamically so the script works from any directory.
# shellcheck disable=SC1091
source "$repo_root/bootstrap-release.env"

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
expect_api_true "repository validation check is required" "$protection_endpoint" \
  "([.required_status_checks.contexts[]] | index(\"$REQUIRED_CHECK_REPOSITORY\")) != null"
expect_api_true "Apple Silicon build check is required" "$protection_endpoint" \
  "([.required_status_checks.contexts[]] | index(\"$REQUIRED_CHECK_DARWIN\")) != null"
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

expect_api_true "immutable releases are enabled" "repos/$REPOSITORY/immutable-releases" \
  '.enabled == true'

ruleset_id=$(gh api "repos/$REPOSITORY/rulesets" --jq \
  ".[] | select(.name == \"$TAG_RULESET_NAME\" and .target == \"tag\" and .enforcement == \"active\") | .id")
[[ $ruleset_id =~ ^[0-9]+$ ]] || {
  printf 'GitHub settings audit failed: active bootstrap tag ruleset not found\n' >&2
  exit 1
}
ruleset_endpoint="repos/$REPOSITORY/rulesets/$ruleset_id"
expect_api_true "bootstrap release tags cannot be updated" "$ruleset_endpoint" \
  '([.rules[].type] | index("update")) != null'
expect_api_true "bootstrap release tags cannot be deleted" "$ruleset_endpoint" \
  '([.rules[].type] | index("deletion")) != null'
expect_api_true "bootstrap tag pattern is protected" "$ruleset_endpoint" \
  "([.conditions.ref_name.include[]] | index(\"$TAG_PATTERN\")) != null"

release_ok=$(gh release view "$BOOTSTRAP_RELEASE" --repo "$REPOSITORY" \
  --json isImmutable,targetCommitish,assets \
  --jq ".isImmutable == true and
    .targetCommitish == \"$BOOTSTRAP_REVISION\" and
    ([.assets[] | select(.name == \"$BOOTSTRAP_ARCHIVE\" and .digest == \"sha256:$BOOTSTRAP_ARCHIVE_SHA256\")] | length == 1)")
[[ $release_ok == "true" ]] || {
  printf 'GitHub settings audit failed: release target, immutability, or archive digest differs from bootstrap-release.env\n' >&2
  exit 1
}
printf 'ok: current bootstrap release and archive digest match the manifest\n'

tag_revision=$(git ls-remote "https://github.com/$REPOSITORY.git" "refs/tags/$BOOTSTRAP_RELEASE" | awk '{ print $1 }')
[[ $tag_revision == "$BOOTSTRAP_REVISION" ]] || {
  printf 'GitHub settings audit failed: %s points to %s instead of %s\n' \
    "$BOOTSTRAP_RELEASE" "${tag_revision:-<missing>}" "$BOOTSTRAP_REVISION" >&2
  exit 1
}
printf 'ok: protected release tag points to the manifest revision\n'

printf 'GitHub branch, tag, and immutable-release controls passed.\n'
