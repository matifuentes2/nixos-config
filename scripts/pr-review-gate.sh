#!/usr/bin/env bash
# Deterministic completion gate for the pr-review-goal skill.
#
# Usage: pr-review-gate <pr-number> --base <branch> --head <reviewed-sha> [--repo <dir>]
#
# Exits 0 and prints "ready: ..." only when all of these hold:
#   - the local checkout is clean and its HEAD is the reviewed SHA;
#   - the PR targets exactly <branch> and its head is the reviewed SHA;
#   - GitHub reports the PR as MERGEABLE;
#   - every latest-head check passed (SUCCESS/NEUTRAL) or was skipped
#     (SKIPPED), and at least one passed;
#   - none of the above changed while the gate ran.
# Otherwise it prints "blocked: ..." or "ci-blocked: ..." and exits 1.
# Usage errors exit 2. Malformed or unreadable GitHub data never passes.
set -euo pipefail

usage() {
  echo "Usage: pr-review-gate <pr-number> --base <branch> --head <reviewed-sha> [--repo <dir>]" >&2
  exit 2
}

pr=""
base=""
head=""
repo="."
while (($# > 0)); do
  case "$1" in
    --base) base="${2-}"; shift 2 || usage ;;
    --base=*) base="${1#--base=}"; shift ;;
    --head) head="${2-}"; shift 2 || usage ;;
    --head=*) head="${1#--head=}"; shift ;;
    --repo) repo="${2-}"; shift 2 || usage ;;
    --repo=*) repo="${1#--repo=}"; shift ;;
    -*) usage ;;
    *)
      [[ -z "$pr" ]] || usage
      pr="$1"
      shift
      ;;
  esac
done
[[ "$pr" =~ ^[1-9][0-9]*$ && -n "$base" && "$head" =~ ^[0-9a-f]{40}$ ]] || usage

block() {
  echo "$1: $2"
  exit 1
}

# Runs in a command substitution: on failure it prints the reason and the
# subshell exits 1, which the caller relays.
metadata() {
  local json
  json="$(cd "$repo" && gh pr view "$pr" --json baseRefName,headRefOid,mergeable 2>/dev/null)" ||
    block blocked "Unable to read PR #$pr metadata with gh."
  jq -er 'select(type == "object") | [.baseRefName, .headRefOid, .mergeable] | map(tostring) | join(" ")' \
    <<<"$json" 2>/dev/null || block blocked "Malformed PR #$pr metadata."
}

check_metadata() {
  local actual_base actual_head mergeable
  read -r actual_base actual_head mergeable <<<"$1"
  [[ "$actual_base" == "$base" ]] ||
    block blocked "PR #$pr targets ${actual_base}, not ${base}."
  [[ "$actual_head" == "$head" ]] ||
    block blocked "PR head is ${actual_head}, not the reviewed ${head}; review the current head."
  [[ "$mergeable" == MERGEABLE ]] ||
    block ci-blocked "PR mergeability is ${mergeable}; resolve conflicts or wait for GitHub to compute it."
}

local_head="$(git -C "$repo" rev-parse HEAD 2>/dev/null)" || block blocked "$repo is not a git checkout."
[[ "$local_head" == "$head" ]] ||
  block blocked "Local HEAD is ${local_head}, not the reviewed ${head}; commit, push and re-review."
[[ -z "$(git -C "$repo" status --porcelain 2>/dev/null)" ]] ||
  block blocked "Local checkout has uncommitted or untracked changes."

before="$(metadata)" || { echo "$before"; exit 1; }
check_metadata "$before"

# gh exits 1 for failed checks and 8 for pending ones. Inspect those rows for a
# useful reason, but never accept a nonzero exit even if the rows look green.
checks_code=0
checks="$(cd "$repo" && gh pr checks "$pr" --json name,state,bucket,link 2>/dev/null)" || checks_code=$?
case "$checks_code" in
  0 | 1 | 8) ;;
  *) block ci-blocked "Unable to read latest-head checks (gh exit ${checks_code})." ;;
esac

# A skipped dependent job must not hide a failing or pending prerequisite, so
# every row is inspected and all-skipped CI is rejected.
summary="$(jq -ec '
  if type != "array" then error("not an array") else
    reduce .[] as $row ({passing: 0, skipped: 0, blockers: []};
      if ($row | type) != "object" or ($row.name | type) != "string" or ($row.name | test("^\\s*$"))
      then .blockers += ["malformed check"]
      elif $row.bucket == "pass" and ($row.state == "SUCCESS" or $row.state == "NEUTRAL")
      then .passing += 1
      elif $row.bucket == "skipping" and $row.state == "SKIPPED"
      then .skipped += 1
      else .blockers += ["\($row.name[0:80] | @json) (state=\($row.state | @json), bucket=\($row.bucket | @json))"]
      end)
  end' <<<"$checks" 2>/dev/null)" || block ci-blocked "Latest-head CI has no checks or malformed check data."

read -r passing skipped blocker_count <<<"$(jq -r '"\(.passing) \(.skipped) \(.blockers | length)"' <<<"$summary")"
if ((blocker_count > 0)); then
  block ci-blocked "Latest-head CI has ${blocker_count} blocking or malformed check(s): $(jq -r '.blockers[:5] | join("; ")' <<<"$summary")."
fi
((passing > 0)) || block ci-blocked "Latest-head CI has no passing checks (${skipped} skipped); at least one must pass."
((checks_code == 0)) ||
  block ci-blocked "GitHub CLI reported unsuccessful CI (exit ${checks_code}) despite nonblocking-looking checks."

after="$(metadata)" || { echo "$after"; exit 1; }
[[ "$after" == "$before" ]] || block blocked "PR head, base or mergeability changed during the gate; re-run it."

echo "ready: PR #$pr at ${head} targets ${base}, is mergeable, and has green CI (${passing} passing, ${skipped} skipped)."
