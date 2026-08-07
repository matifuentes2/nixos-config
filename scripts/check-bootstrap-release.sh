#!/usr/bin/env bash
set -Eeuo pipefail

repo_root=$(git rev-parse --show-toplevel)
cd "$repo_root"

# The repository root is resolved dynamically so the script works from any directory.
# shellcheck disable=SC1091
source "$repo_root/bootstrap-release.env"

[[ $BOOTSTRAP_RELEASE =~ ^bootstrap-v[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
  printf 'bootstrap release check: invalid release name: %s\n' "$BOOTSTRAP_RELEASE" >&2
  exit 1
}
[[ $BOOTSTRAP_REVISION =~ ^[0-9a-f]{40}$ ]] || {
  printf 'bootstrap release check: invalid Git revision: %s\n' "$BOOTSTRAP_REVISION" >&2
  exit 1
}
[[ $BOOTSTRAP_ARCHIVE == "nixos-config-$BOOTSTRAP_RELEASE.tar.gz" ]] || {
  printf 'bootstrap release check: archive name does not match release: %s\n' "$BOOTSTRAP_ARCHIVE" >&2
  exit 1
}
[[ $BOOTSTRAP_ARCHIVE_SHA256 =~ ^[0-9a-f]{64}$ ]] || {
  printf 'bootstrap release check: invalid archive SHA-256: %s\n' "$BOOTSTRAP_ARCHIVE_SHA256" >&2
  exit 1
}

for guide in docs/fresh-install.md docs/macos-fresh-install.md; do
  grep -Fq "release=\"$BOOTSTRAP_RELEASE\"" "$guide" || {
    printf 'bootstrap release check: %s does not contain release %s\n' \
      "$guide" "$BOOTSTRAP_RELEASE" >&2
    exit 1
  }
  grep -Fq "revision=\"$BOOTSTRAP_REVISION\"" "$guide" || {
    printf 'bootstrap release check: %s does not contain revision %s\n' \
      "$guide" "$BOOTSTRAP_REVISION" >&2
    exit 1
  }
  grep -Fq "archive=\"nixos-config-\$release.tar.gz\"" "$guide" || {
    printf 'bootstrap release check: %s does not derive the expected archive name\n' \
      "$guide" >&2
    exit 1
  }
  grep -Fq "archive_sha256=\"$BOOTSTRAP_ARCHIVE_SHA256\"" "$guide" || {
    printf 'bootstrap release check: %s does not contain the expected SHA-256\n' \
      "$guide" >&2
    exit 1
  }
done

printf 'Bootstrap release metadata and installation guides agree.\n'
