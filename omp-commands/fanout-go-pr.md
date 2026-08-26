---
description: Split a plan into independent Orca worktrees with OMP PR agents
argument-hint: "[--base <branch>] [--yes] [plan text...]"
---

Run the OMP-native fanout-to-PR workflow.

Raw arguments: `$ARGUMENTS`

Parse only these options:

- `--base <branch>`, `-b <branch>`, or `--base=<branch>`; default: `develop`;
- `--yes` or `-y`;
- all remaining text is optional plan text.

Reject missing option values and unknown flags. If no plan text was supplied, infer the concrete implementation plan from the preceding conversation. If the conversation does not contain one, ask for the missing details and do not launch workers.

This is the OMP variant. Use Orca worktrees with the `omp` agent. Never invoke `pi`, Pi extension packages, `pi-codex-goal`, Herdr, or the Pi-only `fanout_go_pr_*` tools. Load and follow the version-matched `orca-cli` skill before using Orca; select its CLI exactly as that skill requires.

## Decomposition contract

Turn the plan into the fewest coherent PR-sized pieces that preserve meaningful concurrency. Start from one PR. Add a piece only when its material concurrency benefit outweighs another CI run, review cycle, worktree, and agent session.

- Every piece must be independently useful, implementable, testable, commit-able, and PR-able from the selected base.
- No launched piece may require another launched piece to merge first.
- Combine work sharing an outcome, subsystem, likely files, validation path, or reviewer context.
- Tests, docs, changelogs, small configuration changes, and incidental cleanup travel with the functional change they support.
- If dependencies, ambiguity, or risky overlap prevent a clean split, keep the work together or ask before launching.
- Briefly explain why every additional PR deserves its separate CI and review cycle.
- Without `--yes`, present the split first; proceed when it is clear and low-risk, otherwise ask. With `--yes`, launch a clear split without an extra confirmation.

## Launch contract

Preflight the repository root, the selected base ref, `gh`, the selected Orca CLI, and Orca runtime/repository availability. Create each independent worker as a background Orca worktree using the repository root, a unique `agent/<slug>` name, the selected base branch, `--no-parent`, `--setup run`, `--agent omp`, `--prompt`, and `--json`. Do not pass `--activate` or steal focus.

Pass each multiline worker prompt through the Bash tool's `env` field rather than interpolating plan text into shell source. Launch independent `orca worktree create` calls concurrently in one tool-call wave when possible; do not use shell backgrounding. Treat each JSON response as authoritative. Retain the complete worktree id, path, branch, and sole startup terminal handle; verify the terminal is connected and writable. Never send the prompt twice.

Each worker prompt must include all of the following:

1. Its exact title, plan, base branch, and originating repository root.
2. A strict scope boundary: implement only that piece, obey repository instructions, preserve unrelated changes, and stop for genuine cross-piece overlap.
3. Complete implementation and focused validation.
4. The OMP-native `/go-pr <base>` contract: commit and push only its work; write Spanish PR metadata with technical jargon in English; use OMP `write` plus `gh --body-file`; inspect the stored body; resolve conflicts; return the PR number and URL.
5. A fresh OMP review handoff after the PR exists. The worker must load `orca-cli`, mark the active worktree `in-review`, optionally rename its display name to the PR number, create exactly one new OMP terminal in the same active worktree, wait for that returned terminal handle to reach `tui-idle`, and send `/pr-review-goal <pr-number> --base=<base>` to that exact handle. It must not create another worktree for review, guess a terminal, or send to both an old and replacement handle. Once delivery is confirmed, the implementation worker stops; the fresh review terminal owns the loop. If handoff cannot be completed, report the PR URL and exact manual recovery command.

After launch verification, report each piece's title, branch, complete Orca worktree id/path, and startup terminal handle. Do not claim the worker PRs are complete merely because their sessions launched.
