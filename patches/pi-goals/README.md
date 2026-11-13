# Local PR-review reliability fixes

These patches apply to the exact Git inputs in `flake.nix`. Nix applies them to
copied packages; the source inputs, generated user files and installed packages
are never edited imperatively. Rebase the patches and run the packaged lifecycle
smoke test when upgrading either input. The companion patch targets its shipped
JavaScript bundle because that is the entrypoint Pi actually loads.

- Failed reviewer attempts remain failed evidence. Two failures allow the active
  parent to diagnose setup, repair the checkout or retry the same reviewer. The
  third consecutive failure pauses the goal. Cancellation pauses immediately.
  The counter persists in the execution record and resets after success.
- Preparation errors retain exit/timeout/truncation information and bounded
  stderr instead of hiding the cause behind a command name.
- Automatic Codex PR-review inspection and connector-specific replies are removed.
- Reviewer and parent instructions distinguish source review, repository
  requirements and applicable runtime/browser validation, including zero-fix
  reviews. Reviewer model/provider selection and existing completion gates stay
  enforced.

The context-mode adapter separately preserves goal-control and codemode results.
Those results carry structured control state; excerpting them hid objectives and
made JSON consumers fail in observed sessions. Other tool results still use the
upstream compression hooks.

## Remaining boundary

The host mechanically checks fresh reviewer execution, its verdict, PR head/base,
mergeability and CI. It does **not** mechanically certify browser interactions,
repository-specific validation. The stronger
instructions address observed omissions but are not a new proof of those checks.
Pi now runs on pinned Node 24: Bun 1.4.0 advertises node:sqlite support but
fails context-mode migrations with disk I/O errors. The adapter identifies its
Nix registration, passes the live worktree to doctor, and resets cached project
and session state on a switch. Old v1 data is preserved; a D4 legacy-directory
warning is not permission to delete session history.

## Large reviews without a fixed agent script

The trusted host partitions large diffs into roughly 32,000-character sections
and includes the complete file manifest in each prompt. Oversized files are
continued without dropping text. A final integration pass checks cross-file
contracts. Small PRs still use a single review. Sections execute sequentially
with the persisted provider/model, and raw section verdicts are stored alongside
the aggregate execution evidence. Every section must be valid and current;
malformed, stale, interrupted or failed sections never produce approval.

This bounds input size, not investigative freedom: reviewers choose which
source, callers and tests to inspect, and the parent chooses fixes and relevant
validation. Missing parent runtime checks are not code defects. Browser harness
failures must be investigated rather than accepted as product failures. This
change does not install dependencies or adapt scripts in unrelated repositories.

## Validation and activation

Review progress is persisted at preparation, each section start and validated
completion, final head validation, and terminal success/failure. The optional
integration pass has its own phase. `get_goal` exposes a compact `review` record
with the attempt, commit, reviewer, failure count, phase, counts and timestamps;
it does not repeat section verdicts. `run_goal_review` also streams these updates
through Pi's tool update callback for the active tool display. Display delivery
is best effort; the persisted record remains authoritative. Concurrent review
launches are refused, and superseded attempts cannot publish progress.

Counts include integration and advance only after verdict validation. All steps
being validated still does not authorize completion until the PR head/checkout
is checked again. Cancellation and session restoration retain progress but mark
the attempt interrupted. Each section also publishes subprocess diagnostics on launch, every ten seconds,
and exit: elapsed time, PID, transport byte counts, parsed event count, last event
kind/time, stop reason, exit code/signal and the ten-minute timeout. A pulse only
shows that the host is observing the process; the separate last-event timestamp
shows whether the reviewer has emitted activity. It does not establish reviewer
health or advance validated counts. Subprocess diagnostics reset at each section.

Failures retain their phase, section and attempt ID in the tool error, plus
bounded stderr/provider error text with common credential and URL redaction.
Malformed transport/verdict errors omit payload excerpts. Diagnostics survive in
`get_goal` and terminal streamed updates, including zero-exit provider errors.
Streamed summaries omit accumulated verdicts, prompts, reasoning, tool arguments
and tool results. Error redaction is best effort: keep session journals private. This patch does not
add T3 frontend components or expose private model reasoning.

`nix build --no-link .#checks.aarch64-darwin.pi-goal-lifecycle` tests the packaged
pair without an external model. The context-mode test is
`node tests/context-mode-live-tools.mjs <built-context-mode-package-root>`;
use Node 24.15 or later for upstream context-mode hooks. The flake also exposes
`pi-context-state`, `review-batches`, and `pi-runtime` checks. The lifecycle
fixture runs the packaged host and multiple section subprocesses, without
external models. These tests do not establish that a live PR has been reviewed.

After the normal Mac rebuild, restart affected Pi/T3 sessions to load the new
extensions. Existing paused goals need `/goal resume`; an already completed goal
is not retroactively re-reviewed. No automatic merge or activation is added.

For a paused protected goal, preserve its identity and reviewer. After activation
and a supported session reload, inspect `get_goal` before resuming. An existing
goal retains its stored objective; the new host batching still applies when its
policy re-registers. Do not replace the protected goal or edit Pi journals.
Apply on the Mac with `sudo darwin-rebuild switch --flake ~/nixos-config#macbook`,
then reload the affected Pi/T3 session and resume its existing goal.
