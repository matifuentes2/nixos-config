---
description: Finish the work, commit and push it, then open the PR
argument-hint: "[target-branch]"
---

Finish the current task completely, then commit and push only the changes that belong to it. Preserve unrelated user changes.

Optional target branch: `$1`

- If a target branch was supplied, use it exactly.
- Otherwise target `develop`, or `dev` only when `develop` does not exist.
- Follow the repository's instructions for validation, privacy, authorship, protected branches, and PR workflow.
- Inspect the final diff, commits, and relevant code before writing the PR metadata.
- Resolve merge conflicts instead of treating them as completion.

Write the PR title and description in Spanish while preserving technical jargon in English. The description must reflect the implementation's current intent, not a stale initial plan. Include:

- a concise summary;
- the main code or behavior changes in readable groups;
- short before/after, usage, workflow, or user-facing examples when useful;
- validation actually performed;
- relevant caveats, follow-ups, or rollout notes.

Use OMP's `write` tool to create the PR body as Markdown at a unique temporary `.md` path, then pass that file to `gh pr create --body-file` or `gh pr edit --body-file`. Do not use a shell heredoc and never pass a multiline body containing escaped `\n` sequences through `--body`.

Before finishing, read the stored body with `gh pr view --json body --jq .body`. Fix literal escape artifacts or stale content. Return the PR URL and the validation evidence.
