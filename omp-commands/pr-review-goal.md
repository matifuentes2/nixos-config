---
description: Run a fresh-review, fix, comment, and CI loop for a PR
argument-hint: "<pr-number> [--base <branch>]"
---

Run the OMP-native PR review/fix/comment loop.

Raw arguments: `$ARGUMENTS`

Accept exactly one positive PR number and, optionally, `--base <branch>`, `-b <branch>`, or `--base=<branch>`. Reject duplicates, missing values, unknown flags, and extra positional arguments with:

`Usage: /pr-review-goal <pr-number> [--base <branch>]`

This command replaces Pi's `pi-codex-goal` event loop with OMP's parent orchestration and a brand-new built-in `reviewer` task for every review round. Do not invoke Pi packages, `/goal`, or a persistent reviewer. The parent is the only writer and owns loop decisions.

## Preflight

1. Resolve and retain the exact current Git repository root. Require `gh` and readable PR metadata.
2. Read `baseRefName` and `headRefOid` with `gh pr view`.
3. If `--base` was supplied, validate it as a Git branch and require the PR target to match it exactly. Without `--base`, require the target to be exactly `develop` or `dev`.
4. Preserve unrelated local changes. If they make checking out or updating the PR unsafe, stop and explain the conflict rather than overwriting them.
5. Check out or update the PR head when needed for fixes. Before every completion decision, re-read the current base and latest head SHA.

Use OMP `todo` state to track the current round, valid findings, fixes, push/comment work, and final CI gate.

## Review loop

Repeat until the completion contract is satisfied:

1. Spawn exactly one fresh `reviewer` through OMP's `task` tool. Give it the repository root, PR number, required base, latest head SHA, and a complete read-only review assignment. It must inspect the latest PR diff and relevant code, report only evidence-backed correctness, security, regression, maintainability, or missing-validation concerns, and identify each finding by severity and exact file/location. It must explicitly report when it finds no valid change request. Never reuse or revive a reviewer from an earlier round.
2. While that reviewer runs, the parent may inspect GitHub's current review threads, pull-request review comments, and issue comments through `gh`/`gh api`, including `chatgpt-codex-connector` or Codex-authored conversations. Then consume the reviewer result; wait through `hub` only when no other actionable work remains.
3. Validate every reviewer and Codex concern against the code and current diff. Fix only valid, evidence-backed concerns. Use one writer path: the parent. Do not let the reviewer edit, commit, push, or comment.
4. Merge conflicts are workflow work, not a stop condition. Update from the exact target base, resolve, validate, commit, push, and continue. Stop only when resolution is genuinely impossible without user input.
5. After a fix round, run focused validation required by the repository and the changed behavior. Commit and push all fixes belonging to the PR.
6. For every pushed fix round, post a Spanish top-level PR summary preserving technical jargon in English. For every addressed Codex connector concern, also reply in Spanish directly to its original GitHub review comment or thread; a top-level summary is not a substitute.
7. Create every GitHub comment body as real Markdown in a temporary `.md` file with OMP's `write` tool, inspect it, and post it with a `--body-file` form. Never use shell heredocs or quoted strings containing literal `\n` escapes.
8. After each push, refresh PR metadata and start a brand-new reviewer against the new head. If the first reviewer has no valid requests and no valid Codex concern exists, record that zero fix rounds were needed.

## CI and completion gate

For the latest head, inspect `headRefOid`, `mergeStateStatus`, and `mergeable`, then inspect checks with `gh pr checks --json name,state,bucket,link`.

- Bad, pending, queued, or in-progress checks block completion. Fix failures or wait, then re-read metadata and checks.
- If no checks appear, do one quick refresh, then inspect merge/conflict state and the PR status before waiting longer. Resolve conflicts and re-check.
- After every push, all review and CI evidence from the previous head is stale.

Do not finish until all are true:

- the PR still targets the exact allowed base;
- the latest fresh reviewer has no valid request;
- all Codex connector conversations were inspected and no valid concern remains unresolved;
- every fix is validated, committed, and pushed;
- every addressed Codex concern has a direct reply and every pushed round has its Spanish summary;
- posted Markdown contains real newlines and no literal `\n` artifacts;
- conflicts are resolved and the latest-head CI/check state is green with nothing bad or pending.

Return the PR URL, final head SHA, review-round and fix-round counts, validation performed, comment/reply evidence, and final check state.
