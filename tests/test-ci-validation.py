#!/usr/bin/env python3
"""Regression tests for CI routing and the fail-closed merge gate."""

import copy
import importlib.util
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


sys.dont_write_bytecode = True
SCRIPT = Path(__file__).resolve().parents[1] / "scripts/ci-validation.py"
SPEC = importlib.util.spec_from_file_location("ci_validation", SCRIPT)
CI = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(CI)


class RoutingTests(unittest.TestCase):
    def test_documentation_only(self):
        self.assertFalse(any(CI.plan(["README.md", "docs/install.md"]).values()))

    def test_each_host(self):
        for directory, output in CI.HOSTS.items():
            with self.subTest(host=directory):
                selected = CI.plan([f"hosts/{directory}/home.nix"])
                self.assertEqual(
                    {key for key, value in selected.items() if value},
                    {output} | ({"linux"} if output != "macbook" else set()),
                )

    def test_shared_and_unknown_files_require_everything(self):
        for path in ("flake.lock", "flake.nix", "modules/home/common.nix",
                     "modules/home/darwin.nix", "pi-prompts/delegation-policy.md",
                     ".github/workflows/validate.yml", "scripts/ci-validation.py",
                     "tests/test-ci-validation.py", "hosts/new-host/default.nix",
                     "new-configuration", "docs/runtime.json"):
            with self.subTest(path=path):
                self.assertTrue(all(CI.plan([path]).values()))

    def test_full_even_with_no_changes(self):
        self.assertTrue(all(CI.plan([], full=True).values()))

    def test_combined_hosts(self):
        selected = CI.plan(["hosts/macbook/home.nix", "hosts/hgrai/home.nix"])
        self.assertTrue(selected["macbook"] and selected["hgrai"])
        self.assertFalse(selected["flake"] or selected["wsl2"])

    def test_git_diff_handles_moves_deletions_and_unusual_filenames(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)

            def git(*args):
                return subprocess.check_output(["git", "-C", directory, *args])

            git("init", "--quiet")
            git("config", "user.name", "CI test")
            git("config", "user.email", "55928941+matifuentes2@users.noreply.github.com")
            source = root / "hosts/macbook/file with\nnewline.nix"
            source.parent.mkdir(parents=True)
            source.write_text("{}\n")
            git("add", ".")
            git("commit", "--quiet", "-m", "Base")
            base = git("rev-parse", "HEAD").decode().strip()
            destination = root / "hosts/hgrai/moved.nix"
            destination.parent.mkdir(parents=True)
            source.rename(destination)
            git("add", "-A")
            git("commit", "--quiet", "-m", "Move")
            output = subprocess.check_output(
                ["python3", str(SCRIPT), "plan", "--base", base, "--head", "HEAD"],
                cwd=directory, text=True,
            )
            self.assertIn("macbook=true\n", output)
            self.assertIn("hgrai=true\n", output)
            self.assertIn("flake=false\n", output)


class GateTests(unittest.TestCase):
    def needs(self, paths):
        selections = CI.plan(paths)
        return {
            "plan": {"result": "success", "outputs": {
                key: str(value).lower() for key, value in selections.items()
            }},
            "quick": {"result": "success"},
            **{job: {"result": "success" if selections[job] else "skipped"}
               for job in ("flake", "macbook", "linux")},
        }

    def test_accepts_only_expected_successes_and_skips(self):
        for paths in (["README.md"], ["hosts/hgrai/home.nix"], ["flake.lock"]):
            CI.check_results(self.needs(paths))

    def test_required_failures_cancellations_and_skips_are_rejected(self):
        for job in ("plan", "quick", "flake", "macbook", "linux"):
            for result in ("failure", "cancelled", "skipped"):
                needs = self.needs(["flake.lock"])
                needs[job]["result"] = result
                with self.subTest(job=job, result=result), self.assertRaises(ValueError):
                    CI.check_results(needs)

    def test_missing_and_invalid_plan_outputs_are_rejected(self):
        for key in CI.SELECTIONS:
            for value in (None, "", "yes"):
                needs = self.needs(["README.md"])
                needs["plan"]["outputs"][key] = value
                with self.subTest(key=key, value=value), self.assertRaises(ValueError):
                    CI.check_results(needs)

    def test_unexpected_job_result_is_rejected(self):
        for result in ("failure", "cancelled", "success"):
            needs = self.needs(["README.md"])
            needs["macbook"]["result"] = result
            with self.assertRaises(ValueError):
                CI.check_results(needs)

    def test_inconsistent_linux_selection_is_rejected(self):
        needs = copy.deepcopy(self.needs(["hosts/hgrai/home.nix"]))
        needs["plan"]["outputs"]["linux"] = "false"
        needs["linux"]["result"] = "skipped"
        with self.assertRaises(ValueError):
            CI.check_results(needs)


if __name__ == "__main__":
    unittest.main()
