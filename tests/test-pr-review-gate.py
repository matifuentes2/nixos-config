"""Regression tests for scripts/pr-review-gate.sh.

Usage: python3 tests/test-pr-review-gate.py [path/to/pr-review-gate.sh]

Runs the gate against a temporary Git checkout and a fake `gh` on PATH, so it
needs bash, git and jq but no network, GitHub credentials or model calls.
"""

import json
import os
import pathlib
import shutil
import stat
import subprocess
import sys
import tempfile
import unittest

REPO = pathlib.Path(__file__).resolve().parent.parent
GATE = pathlib.Path(sys.argv.pop(1) if len(sys.argv) > 1 else REPO / "scripts/pr-review-gate.sh")

PASSING = [{"name": f"passing-{i}", "state": "SUCCESS", "bucket": "pass"} for i in range(22)]
SKIPPED = [{"name": f"conditional-{i}", "state": "SKIPPED", "bucket": "skipping"} for i in range(11)]

# The fake gh reads its responses from files so a test can change them, and
# flips the head after the first `pr view` when asked to simulate a push.
# Its shebang is filled in with an absolute bash path: the Linux Nix build
# sandbox has no /usr/bin/env.
FAKE_GH = r"""#!@BASH@
set -eu
state="$FAKE_GH_STATE"
case "$1 $2" in
  "pr view")
    count=$(( $(cat "$state/views" 2>/dev/null || echo 0) + 1 ))
    echo "$count" > "$state/views"
    if [[ -f "$state/view-after" && "$count" -gt 1 ]]; then cat "$state/view-after"; else cat "$state/view"; fi
    ;;
  "pr checks")
    cat "$state/checks"
    exit "$(cat "$state/checks-code")"
    ;;
  *) echo "unexpected gh call: $*" >&2; exit 99 ;;
esac
"""


class PrReviewGateTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="pr-review-gate-")
        root = pathlib.Path(self.temporary.name)
        self.checkout = root / "checkout"
        self.state = root / "state"
        bin_dir = root / "bin"
        for directory in (self.checkout, self.state, bin_dir):
            directory.mkdir()
        gh = bin_dir / "gh"
        bash = shutil.which("bash")
        self.assertIsNotNone(bash, "bash must be on PATH")
        gh.write_text(FAKE_GH.replace("@BASH@", bash, 1))
        gh.chmod(gh.stat().st_mode | stat.S_IEXEC)

        git = ["git", "-C", str(self.checkout), "-c", "user.name=t", "-c", "user.email=t@example.invalid"]
        subprocess.run(git[:3] + ["init", "-q"], check=True)
        subprocess.run(git + ["commit", "-q", "--allow-empty", "-m", "fixture"], check=True)
        self.head = subprocess.check_output(git[:3] + ["rev-parse", "HEAD"], text=True).strip()

        self.env = {**os.environ, "PATH": f"{bin_dir}{os.pathsep}{os.environ['PATH']}",
                    "FAKE_GH_STATE": str(self.state)}
        self.set_view()
        self.set_checks(PASSING + SKIPPED)

    def tearDown(self):
        self.temporary.cleanup()

    def set_view(self, name="view", **overrides):
        view = {"baseRefName": "main", "headRefOid": self.head, "mergeable": "MERGEABLE", **overrides}
        (self.state / name).write_text(json.dumps(view))

    def set_checks(self, rows, code=0, raw=None):
        (self.state / "checks").write_text(raw if raw is not None else json.dumps(rows))
        (self.state / "checks-code").write_text(str(code))

    def gate(self, *args, base="main", head=None):
        argv = ["bash", str(GATE), "7", "--base", base, "--head", head or self.head,
                "--repo", str(self.checkout), *args]
        return subprocess.run(argv, env=self.env, text=True, capture_output=True, timeout=60)

    def assert_blocked(self, result, status, pattern):
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertTrue(result.stdout.startswith(f"{status}:"), result.stdout)
        self.assertRegex(result.stdout, pattern)

    def test_passing_and_skipped_checks_are_ready(self):
        result = self.gate()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("22 passing, 11 skipped", result.stdout)

    def test_blocking_check_states(self):
        for state, bucket in (("FAILURE", "fail"), ("PENDING", "pending"), ("CANCELLED", "cancel"),
                              ("ACTION_REQUIRED", "fail"), ("SUCCESS", "skipping")):
            with self.subTest(state=state, bucket=bucket):
                self.set_checks(PASSING + SKIPPED + [{"name": "prerequisite", "state": state, "bucket": bucket}],
                                code=8 if bucket == "pending" else 1)
                self.assert_blocked(self.gate(), "ci-blocked", r'"prerequisite"')

    def test_absent_all_skipped_and_malformed_checks_block(self):
        self.set_checks([])
        self.assert_blocked(self.gate(), "ci-blocked", "no passing checks")
        self.set_checks(SKIPPED)
        self.assert_blocked(self.gate(), "ci-blocked", "11 skipped")
        self.set_checks(None, code=1, raw="no checks reported on the 'x' branch")
        self.assert_blocked(self.gate(), "ci-blocked", "malformed")
        self.set_checks(PASSING + [{"state": "SUCCESS", "bucket": "pass"}])
        self.assert_blocked(self.gate(), "ci-blocked", "malformed check")
        self.set_checks(None, raw='{"name": "not-a-list"}')
        self.assert_blocked(self.gate(), "ci-blocked", "malformed")

    def test_nonzero_gh_exit_blocks_green_looking_rows(self):
        self.set_checks(PASSING, code=1)
        self.assert_blocked(self.gate(), "ci-blocked", "exit 1")
        self.set_checks(PASSING, code=4)
        self.assert_blocked(self.gate(), "ci-blocked", "exit 4")

    def test_pr_metadata_must_match(self):
        self.set_view(baseRefName="develop")
        self.assert_blocked(self.gate(), "blocked", "targets develop, not main")
        self.set_view(headRefOid="e" * 40)
        self.assert_blocked(self.gate(), "blocked", "review the current head")
        for mergeable in ("CONFLICTING", "UNKNOWN"):
            self.set_view(mergeable=mergeable)
            self.assert_blocked(self.gate(), "ci-blocked", mergeable)
        (self.state / "view").write_text("not json")
        self.assert_blocked(self.gate(), "blocked", "Malformed PR #7 metadata")

    def test_local_checkout_must_be_clean_at_reviewed_head(self):
        self.assert_blocked(self.gate(head="f" * 40), "blocked", "Local HEAD")
        (self.checkout / "untracked.txt").write_text("x")
        self.assert_blocked(self.gate(), "blocked", "uncommitted or untracked")

    def test_moving_head_during_gate_blocks(self):
        self.set_view("view-after", headRefOid="e" * 40)
        self.assert_blocked(self.gate(), "blocked", "changed during the gate")

    def test_usage_errors(self):
        for argv in (["7"], ["7", "--base", "main"], ["x", "--base", "main", "--head", self.head],
                     ["7", "--base", "main", "--head", "short"], ["7", "--base"]):
            with self.subTest(argv=argv):
                result = subprocess.run(["bash", str(GATE), *argv], env=self.env, text=True,
                                        capture_output=True, timeout=60)
                self.assertEqual(result.returncode, 2, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
