# PR review goal (T3 Code native)

`/pr-review-goal` is a shared agent skill, `pi-skills/pr-review-goal/SKILL.md`.
Home Manager installs the same file for Pi (`~/.pi/agent/skills`), Claude Code
(`~/.claude/skills`) and Codex (`~/.agents/skills`). Pi also gets a
`/pr-review-goal` prompt template that loads it. Run it inside a T3 Code thread:

```text
/pr-review-goal <pr-number> [--base <branch>] [--reviewer <provider-instance>:<model>] [--reviewer-option <id>=<value>]
```

In Codex, mention `$pr-review-goal` with the same arguments. Without `--base`,
the PR must target `develop` or `dev`. The reviewer defaults to the invoking
thread's own provider, model and options. `--reviewer codex:gpt-6.2-sol` selects
any T3 provider instance that can run child tasks. A bare Pi model such as
`--reviewer anthropic/claude-x` means instance `pi`. An unknown reviewer stops
the run. There is never a fallback to another model.

## What T3 Code provides

| Concern | T3 Code mechanism | Replaces |
| --- | --- | --- |
| Fresh independent reviewers | `delegate_task` (`role: review`, `isolation: worktree`), one reviewer by default; above ~10,000 reviewable lines, up to 4 feature-cut sections in parallel plus a contract-focused integration pass | The Pi goal host's `pi --print` reviewer subprocesses |
| Waiting for CI, comments and conflicts | `link_pull_request` + `watch_pull_request` wakes the thread | `/goal` continuation turns and manual polling |
| Runtime and UI validation | The built-in preview browser (`preview_*`), with no Playwright fallback | Playwright MCP extension mode |
| Visibility | Reviewer child threads and the linked PR show in the T3 UI | `get_goal` review progress records |

Each reviewer gets its own worktree at the parent's commit. It cannot modify
the parent's checkout, and the parent must push before each round so that
commit is the PR head. Reviewers receive facts only: scope, manifest and prior
blockers, never the parent's opinion of the code. They return one JSON verdict
that separates blocking `findings` from non-blocking `advisories`.

## Review scope

The first round reviews the whole PR. Later rounds review only the fix diff
since the last reviewed head, and re-verify every prior blocking finding. A full
pass runs again after a rebase, force-push or merge, when the reviewer changes,
or when the base changed a file the PR also changes. Diffs are computed locally
from the merge base, never with `gh pr diff`, which fails on PRs with more than
300 files. Reviewers read the diff per file or directory, so a large diff is
not by itself a reason to split. Only the reviewable size (excluding lockfiles,
generated code, snapshots, vendored files and pure renames) decides whether a
round is split; file count never does. There is no round limit: the loop ends when a review of the current
head has no blocking findings. Per-round state is kept in
`$(git rev-parse --git-common-dir)/pr-review-goal/<pr>.json`, outside the
working tree, so the loop can resume after a wake or a context summary.

## Completion gate

`pr-review-gate` (`scripts/pr-review-gate.sh`, packaged with `gh`, `git` and
`jq`) is the deterministic part of completion:

```sh
pr-review-gate <pr> --base <branch> --head <reviewed-sha>
```

It prints `ready:` and exits 0 only when all of these hold:

- the local checkout is clean at the reviewed SHA;
- the PR still targets the branch and its head is that SHA;
- GitHub reports the PR as `MERGEABLE`;
- every latest-head check passed or was skipped, at least one passed, and
  nothing is failed, pending, cancelled or malformed;
- none of this changed while the gate ran.

Nonzero `gh pr checks` exits are never accepted.

## Trust boundary (changed)

The previous Pi implementation enforced completion in trusted host code. The
host launched the reviewer itself, stored the verdict in a protected ledger, and
refused `update_goal(complete)` until the verdict, the head/base and CI checked
out. That host, its patches and the `pi-pr-review-goal` input have been removed.

The skill is now provider-agnostic. Verdict validation, round scoping and
reruns are instructions the parent agent follows, not code that a model cannot
bypass. The mechanical checks that remain are the reviewers' worktree
isolation, `pr-review-gate`, and the remote safeguards: branch protection and
required CI. T3 reviewers are also not mechanically read-only the way the old
`--tools read,grep,find,ls` reviewers were. Their brief forbids edits, pushes
and comments, and worktree isolation keeps any stray edit out of the parent's
checkout, but a reviewer with push credentials could still push.

The generic Pi `/goal` package (`pi-codex-goal`) is still installed, unpatched.
A paused goal left over from an old `/pr-review-goal` run is still protected by
the old policy, and nothing now registers that policy, so the goal cannot
complete. Clear it with `/goal clear` and start the skill instead.

## Regression checks

```sh
nix build --no-link .#checks.aarch64-darwin.pr-review-gate
nix build --no-link .#checks.aarch64-darwin.pi-goal-lifecycle
```

`pr-review-gate` runs `tests/test-pr-review-gate.py` against a temporary
checkout and a fake `gh`. It covers green, skipped and blocking CI, absent and
malformed checks, nonzero `gh` exits, base/head/mergeability mismatches, a dirty
checkout and a head that moves during the gate. No network or credentials are
needed. The skill's orchestration itself needs a live T3 Code session and is
not exercised by CI.
