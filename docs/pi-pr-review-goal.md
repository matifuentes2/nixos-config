# PR review recovery

The Pi `/pr-review-goal` command and its companion goal host are packaged in
`packages/home-tools.nix`. The tracked patches are applied during the Nix build;
editing an installed package or Pi's generated settings is not a lasting fix.
Rebuild the affected host and start a fresh Pi session to load the changed pair.
The command requires the host's `reviewRecoveryVersion: 2` capability, so an old
host cannot silently run the new snapshot/checkpoint protocol.

## Large PRs and loaded versions

The complete diff is generated locally from the unique merge base of the pinned
PR head and base commits. The command does not call GitHub's size-limited PR diff
endpoint. A private clone repairs shallow or missing-base history without
changing the caller's checkout. Diff output goes to a private file; inputs above
64 MiB fail explicitly instead of silently dropping changes. Final verification
rejects a moving head, base or caller checkout. The diff digest and merge-base SHA
are included in the checkpoint identity.

`get_goal` exposes `reviewImplementation` (loaded host version, required command
version and local-diff capability), and a prepared attempt's `commandVersion`.
Protocol v2 rejects old hosts before policy registration. Restart both extensions
after rebuilding; preserve and resume the existing goal rather than replacing it.
Existing stored objectives are retained and can describe older instructions.

## Review evidence and recovery

Each source section runs sequentially in a fresh, read-only reviewer context on
the selected provider/model. A successful Pi retry can recover a transient
assistant error only when the event stream explicitly records retry success and
a subsequent successful response. Cancellation, truncation, extension errors,
exhausted retries, malformed output and model mismatches cannot authorize approval.
A transient provider failure can retry its section twice with bounded backoff.
Authentication, setup and invalid-verdict failures require diagnosis rather than
automatic repetition. Deterministic snapshot failures (empty/oversize diff,
unsupported submodules or missing/ambiguous merge base) save an opaque input key.
The host refuses another clone for the same failed head/base and local object
state, including after reload. Repair the prerequisite or change the PR inputs;
never reset the protected goal to bypass its failure. Transient command failures
remain diagnosable and do not grant approval.

The host persists each validated section verdict in its protected session ledger
before starting the next section. A retry resumes this checkpoint only when the
repository/PR, goal, head, base SHA, reviewer, policy, prompts and integration
scope are identical. Each saved verdict retains its original attempt ID; the
host aggregates validated evidence for the new attempt without rewriting those
verdicts. Changes to review inputs invalidate the checkpoint. Every section and
the integration review must finish before approval; CI remains a separate gate.
A moving base also invalidates approval even if the PR head has not changed.

Setup or runtime failures block approval and leave an active goal available for
diagnosis, fixes, CI repair and pending validation. The parent must investigate
before retrying after automatic recovery is exhausted. Explicit cancellation
pauses the goal; `/goal resume` continues it. A session restored during an
unfinished review remains paused with its validated checkpoint preserved.
Budget limits and user pauses retain their existing behavior. Status reports code
review independently from CI and runtime validation. CI still requires a current
head check and runtime checks still require parent evidence; the host does not
certify browser activity. Before ending a turn, report each gate, concrete
blockers and next actions. A failed browser harness is a setup failure, not a
product defect or permission to skip validation.

## Source isolation and diagnostics

Review preparation creates a private temporary clone at the committed PR head,
then removes its Git metadata. It includes all tracked files, including files
marked `export-ignore`, and excludes untracked browser artifacts and local edits.
The caller's checkout, index and unknown files are untouched. Submodules fail
preparation explicitly until materialized snapshot support is available.
The host removes only its own snapshot on success, failure or cancellation;
a hard process kill can leave a temporary directory for operating-system cleanup.

Status exposes the failed section, category, recovery action, retry history,
process exit/stop status and bounded sanitized error text. It excludes prompts,
reasoning, tool arguments/results and the full section-verdict ledger.

## Regression checks

Run `nix build --no-link .#checks.aarch64-darwin.pi-goal-lifecycle` on Apple
silicon, or replace the system with the local supported Linux system. This check
exercises the packaged entrypoints and runs the runner, section/checkpoint and
snapshot regressions, including 317-file diffs, shallow/missing-object repair,
oversize inputs, deterministic retry refusal and moving-head/base rejection,
without credentials or paid model calls. `nix flake check` also includes these
checks for the current system.
