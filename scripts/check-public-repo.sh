#!/usr/bin/env bash
set -Eeuo pipefail

readonly REQUIRED_EMAIL="55928941+matifuentes2@users.noreply.github.com"
readonly GITHUB_PLATFORM_EMAIL="noreply@github.com"

for command_name in exiftool git gitleaks grep; do
  command -v "$command_name" >/dev/null 2>&1 || {
    printf 'public-repository check: required command is unavailable: %s\n' "$command_name" >&2
    exit 1
  }
done

printf 'Scanning the working tree with Gitleaks...\n'
gitleaks dir . --no-banner --redact

printf 'Scanning reachable Git history with Gitleaks...\n'
gitleaks git . --no-banner --redact

printf 'Checking author and committer email addresses...\n'
bad_email=false
while IFS=$'\t' read -r commit author_email committer_name committer_email; do
  if [[ $author_email != "$REQUIRED_EMAIL" ]]; then
    printf 'Unexpected author email in %s: %s\n' "$commit" "$author_email" >&2
    bad_email=true
  fi

  if [[ $committer_email == "$REQUIRED_EMAIL" ]]; then
    continue
  fi

  # GitHub creates protected-branch squash commits server-side. Its verified
  # platform committer is public infrastructure metadata, not a personal email.
  if [[ $committer_name == "GitHub" && $committer_email == "$GITHUB_PLATFORM_EMAIL" ]]; then
    continue
  fi

  printf 'Unexpected committer in %s: %s <%s>\n' \
    "$commit" "$committer_name" "$committer_email" >&2
  bad_email=true
done < <(git log --all --format='%H%x09%ae%x09%cn%x09%ce')
[[ $bad_email == false ]] || exit 1

printf 'Checking tracked media metadata...\n'
media_found=false
while IFS= read -r -d '' media_file; do
  case $media_file in
    *.jpg|*.JPG|*.jpeg|*.JPEG|*.png|*.PNG|*.gif|*.GIF|*.webp|*.WEBP|*.heic|*.HEIC|*.tif|*.TIF|*.tiff|*.TIFF|*.pdf|*.PDF|*.mp4|*.MP4|*.mov|*.MOV)
      media_found=true
      metadata=$(exiftool -q -q -G1 -s "$media_file")
      if grep -Eiq '^\[(ExifIFD|IFD[0-9]*|GPS|XMP|IPTC|MakerNotes|Apple|Canon|Nikon|Sony|Pentax|Panasonic|Olympus|Samsung|DJI|QuickTime|UserData|Keys)[^]]*\]' <<<"$metadata"; then
        printf 'Identifying metadata group found in %s\n' "$media_file" >&2
        exit 1
      fi
      if grep -Eiq '^\[[^]]+\][[:space:]]+(Author|Artist|Creator|Copyright|Owner|SerialNumber|CameraSerialNumber|Make|Model|GPS[^:]*|Location|Latitude|Longitude|City|Country|Address|Email|Phone|Comment|Description|Title)[[:space:]]*:' <<<"$metadata"; then
        printf 'Identifying metadata field found in %s\n' "$media_file" >&2
        exit 1
      fi
      ;;
  esac
done < <(git ls-files --cached --others --exclude-standard -z)

if [[ $media_found == false ]]; then
  printf 'No tracked media files found.\n'
fi

printf 'Public-repository checks passed.\n'
