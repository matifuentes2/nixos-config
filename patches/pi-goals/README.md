# Local PR-review reliability fixes

These patches apply to the exact Git inputs in `flake.nix`. Nix applies them to
copied packages; the source inputs, generated user files and installed packages
are never edited imperatively. Rebase the patches and run the packaged lifecycle
smoke test when upgrading either input. The companion patch targets its shipped
JavaScript bundle because that is the entrypoint Pi actually loads.

- Failed reviewer attempts remain failed evidence and keep independent repair
  work active. Exhausted retries never pause the goal by themselves. Cancellation
  pauses immediately; user pauses and budget limits retain their behavior.
  The failure counter persists and resets after success. Deterministic local
  preparation failures carry an opaque input key; unchanged retries are refused
  before cloning, including after session restoration.
- A transient provider `error` is recoverable only when Pi emits a matching
  `auto_retry_start` / successful `auto_retry_end` pair and the retry produces a
  new successful assistant turn on the exact bound provider/model. Pi can emit
  `agent_end` before starting that retry; that intermediate end is not approval.
  A final successful assistant verdict and final `agent_end` are still required.
  Unpaired, mismatched, unfinished or exhausted retries remain failures, as do
  cancellation, truncation, extension errors and intermediate model substitution.
  This fixes false failures after Pi successfully recovers a request timeout;
  it never treats an interrupted or incomplete review as clean evidence.
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
mergeability and CI. It does **not** mechanically certify browser interactions
or repository-specific validation. Status labels CI as requiring a current-head
check and runtime validation as requiring parent evidence. These labels are not
certification. Every handback must report code review, CI and runtime validation
separately, with blockers and next actions, including after a failed tool. The
stronger instructions address observed omissions but are not a new proof of those checks.
Pi now runs on pinned Node 24: Bun 1.4.0 advertises node:sqlite support but
fails context-mode migrations with disk I/O errors. The adapter identifies its
Nix registration, passes the live worktree to doctor, and resets cached project
and session state on a switch. Old v1 data is preserved; a D4 legacy-directory
warning is not permission to delete session history.

## Pinned local diff preparation

The command never requests `gh pr diff`: GitHub can reject that endpoint for a
PR with more than 300 files. Metadata pins the head and base commits. A private
clone computes their unique merge base and writes the complete diff to a private
file, avoiding tool-output truncation. Binary changes, additions and deletions
remain represented. A 64 MiB input limit fails explicitly; it never authorizes
review of a prefix. Missing base objects and shallow history are fetched at the
pinned commits into the private clone using GitHub CLI credentials. Caller refs,
configuration, index, shallow boundary and artifacts are unchanged. Fetch failures
remain failures; no partial-history merge base is accepted.

Final verification checks the PR head, base branch, base SHA and caller HEAD.
The diff digest and merge-base SHA join the checkpoint identity. Changed inputs
invalidate approval. The paired command/host require review-recovery protocol v2;
`get_goal` reports the loaded host and required command versions, and each prepared
attempt records its actual command version. Rebuild and restart both extensions;
a journal's old objective is not proof that a new implementation is loaded.

## Structured lockfile review

Before batching, ordinary modified `flake.lock`, `package-lock.json` and
`npm-shrinkwrap.json` files can use a deterministic JSON value-change summary
when it is shorter than their raw diff. Every added, removed or changed value
is included at its JSON Pointer path, including hashes, URLs, unknown metadata
and ordered arrays. Only unchanged values, object key ordering and whitespace
are omitted. Reviewers check dependency provenance and manifest consistency.
The original full diff still supplies the checkpoint digest and size limit.

Both versions come from pinned Git blobs, never the caller's working files.
Malformed JSON, duplicate keys, lossy numbers, unavailable/capped blobs,
non-object roots, unusual paths, mode changes, additions and deletions retain
full diffs. Generated code, vendored files, other lock formats and unknown files
also retain full diffs; filenames alone never authorize excluding source.
No regeneration command or repository-provided filter is executed.
Summaries keep the same file manifest and participate in prompt checkpoint
identity, so old raw-diff checkpoints cannot approve changed review inputs.

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

## Focused review rounds

`focused-review-host.patch` and `focused-review-command.patch` apply after the
patches above. Only the first round reviews the full PR. Later rounds receive the
fix diff plus all prior blockers from a host-owned baseline, and any uncertainty
about history falls back to a full pass. Reviewers separate blocking `findings`
from non-blocking `advisories`; the aggregate verdict keeps its strict v1 shape
and contains blockers only. There is deliberately no round cap. Reviewer token
usage is recorded per attempt and per goal, and subprocess pulses no longer
append to the session journal. See [PR review recovery](../../docs/pi-pr-review-goal.md).

## Validation and activation

Review progress is persisted at preparation, each section start and validated
completion, final head validation, and terminal success/failure. Subprocess
pulses are held in memory for live status and are not journaled. The optional
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
