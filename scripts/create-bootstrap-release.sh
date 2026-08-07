#!/usr/bin/env bash
set -Eeuo pipefail

readonly REPOSITORY="matifuentes2/nixos-config"

usage() {
  printf 'Usage: %s bootstrap-vMAJOR.MINOR.PATCH [40-character-revision]\n' "$0" >&2
  exit 2
}

die() {
  printf 'bootstrap release: %s\n' "$*" >&2
  exit 1
}

[[ $# -ge 1 && $# -le 2 ]] || usage
new_release=$1
[[ $new_release =~ ^bootstrap-v[0-9]+\.[0-9]+\.[0-9]+$ ]] || usage

repo_root=$(git rev-parse --show-toplevel)
cd "$repo_root"

for command_name in awk cmp gh git gzip shasum; do
  command -v "$command_name" >/dev/null 2>&1 || die "required command is unavailable: $command_name"
done
gh auth status >/dev/null 2>&1 || die "authenticate gh before creating a release"

# The repository root is resolved dynamically so the script works from any directory.
# shellcheck disable=SC1091
source "$repo_root/bootstrap-release.env"
old_release=$BOOTSTRAP_RELEASE
old_revision=$BOOTSTRAP_REVISION
old_sha256=$BOOTSTRAP_ARCHIVE_SHA256

[[ -z $(git status --porcelain) ]] || die "the working tree must be clean"
[[ $(git branch --show-current) == "main" ]] || die "create bootstrap releases from main"
git fetch --quiet origin main --tags
head_revision=$(git rev-parse HEAD)
origin_revision=$(git rev-parse origin/main)
[[ $head_revision == "$origin_revision" ]] || die "local main is not synchronized with origin/main"
new_revision=${2:-$head_revision}
[[ $new_revision =~ ^[0-9a-f]{40}$ ]] || die "revision must be a full 40-character commit"
[[ $new_revision == "$head_revision" ]] || die "the release revision must be the current, validated main commit"

"$repo_root/scripts/audit-github-settings.sh" >/dev/null

if gh release view "$new_release" --repo "$REPOSITORY" >/dev/null 2>&1; then
  die "release already exists: $new_release"
fi
if [[ -n $(git ls-remote origin "refs/tags/$new_release") ]]; then
  die "tag already exists: $new_release"
fi

run_conclusion=$(gh run list --repo "$REPOSITORY" --workflow validate.yml \
  --commit "$new_revision" --limit 1 --json conclusion --jq '.[0].conclusion // ""')
run_url=$(gh run list --repo "$REPOSITORY" --workflow validate.yml \
  --commit "$new_revision" --limit 1 --json url --jq '.[0].url // ""')
[[ $run_conclusion == "success" && -n $run_url ]] || die \
  "the validation workflow has not succeeded for $new_revision"

work_directory=$(mktemp -d)
published=false
cleanup() {
  rm -rf "$work_directory"
}
on_error() {
  if [[ $published == true ]]; then
    printf 'The immutable release was published, but local metadata was not fully updated.\n' >&2
    printf 'Recover with release=%s revision=%s and the checksum in the release notes.\n' \
      "$new_release" "$new_revision" >&2
  fi
}
trap cleanup EXIT
trap on_error ERR

new_archive="nixos-config-$new_release.tar.gz"
git archive --format=tar --prefix="nixos-config-$new_revision/" "$new_revision" \
  | gzip -n -9 >"$work_directory/$new_archive"
new_sha256=$(shasum -a 256 "$work_directory/$new_archive" | awk '{ print $1 }')
printf '%s  %s\n' "$new_sha256" "$new_archive" >"$work_directory/$new_archive.sha256"

cat >"$work_directory/release-notes.md" <<EOF
# Bootstrap ${new_release#bootstrap-}

Reviewed configuration commit: [\`$new_revision\`](https://github.com/$REPOSITORY/commit/$new_revision)

Validation workflow: $run_url

The attached deterministic source archive has SHA-256:

\`$new_sha256\`

The installation guides pin this full commit and checksum for a reviewed, immutable installation.
EOF

gh release create "$new_release" --repo "$REPOSITORY" --draft \
  --target "$new_revision" --title "Bootstrap ${new_release#bootstrap-}" \
  --notes-file "$work_directory/release-notes.md" >/dev/null
gh release upload "$new_release" --repo "$REPOSITORY" \
  "$work_directory/$new_archive" "$work_directory/$new_archive.sha256"
gh release edit "$new_release" --repo "$REPOSITORY" --draft=false >/dev/null
published=true

replace_literal() {
  local file=$1
  local old_value=$2
  local new_value=$3
  local temporary
  temporary=$(mktemp)

  awk -v old="$old_value" -v new="$new_value" '
    {
      line = $0
      output = ""
      while ((position = index(line, old)) != 0) {
        output = output substr(line, 1, position - 1) new
        line = substr(line, position + length(old))
      }
      print output line
    }
  ' "$file" >"$temporary"

  if cmp -s "$file" "$temporary"; then
    rm -f "$temporary"
    die "expected value $old_value was not found in $file"
  fi
  cat "$temporary" >"$file"
  rm -f "$temporary"
}

for guide in docs/fresh-install.md docs/macos-fresh-install.md; do
  replace_literal "$guide" "$old_release" "$new_release"
  replace_literal "$guide" "$old_revision" "$new_revision"
  replace_literal "$guide" "$old_sha256" "$new_sha256"
done

cat >bootstrap-release.env <<EOF
# Current reviewed bootstrap release. This file is sourced by repository
# maintenance scripts; keep values shell-safe and unquoted.
BOOTSTRAP_RELEASE=$new_release
BOOTSTRAP_REVISION=$new_revision
BOOTSTRAP_ARCHIVE=$new_archive
BOOTSTRAP_ARCHIVE_SHA256=$new_sha256
EOF

"$repo_root/scripts/check-bootstrap-release.sh"

printf '\nPublished immutable release: https://github.com/%s/releases/tag/%s\n' \
  "$REPOSITORY" "$new_release"
printf 'Archive SHA-256: %s\n' "$new_sha256"
printf 'The manifest and installation guides are updated in the working tree.\n'
printf 'Create a documentation branch, run validation, and merge those changes through a pull request.\n'
