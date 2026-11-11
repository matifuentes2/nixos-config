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
Context-mode database/doctor errors are a separate issue; this patch prevents
those hooks from rewriting control results but does not repair their database.

## Validation and activation

`nix build --no-link .#checks.aarch64-darwin.pi-goal-lifecycle` tests the packaged
pair without an external model. The context-mode test is
`node tests/context-mode-live-tools.mjs <built-context-mode-package-root>`;
use Node 24.15 or later for upstream context-mode hooks.

After the normal Mac rebuild, restart affected Pi/T3 sessions to load the new
extensions. Existing paused goals need `/goal resume`; an already completed goal
is not retroactively re-reviewed. No automatic merge or activation is added.
