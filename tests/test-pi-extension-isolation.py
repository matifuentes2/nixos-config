#!/usr/bin/env python3
"""Evaluate real derivation identities without building or switching the host."""
import json
import pathlib
import shutil
import subprocess
import tempfile
import unittest

REPO = pathlib.Path(__file__).resolve().parents[1]


class ExtensionIsolation(unittest.TestCase):
    def test_independent_build_inputs(self):
        with tempfile.TemporaryDirectory(prefix="pi-extension-isolation-") as temporary:
            root = pathlib.Path(temporary)
            shutil.copytree(REPO / "pi-extensions", root / "pi-extensions")
            (root / "packages").mkdir()
            for name in ("home-tools.nix", "pi-extensions.nix"):
                shutil.copyfile(REPO / "packages" / name, root / "packages" / name)

            def evaluate():
                expression = '''
                  let
                    f = builtins.getFlake REPOSITORY;
                    pkgs = f.inputs.nixpkgs.legacyPackages.${builtins.currentSystem};
                    tools = import MODULE {
                      inherit pkgs;
                      inherit (pkgs) lib;
                      inherit (f.inputs) nixpkgs-unstable herdr-collie
                        pi-codex-goal pi-pr-review-goal pi-parallel-go-pr-herdr
                        pi-execution-time orca;
                    };
                  in {
                    registration = tools.piExtensions.drvPath;
                    packages = builtins.mapAttrs (_: p: p.drvPath) tools.piExtensionPackages;
                    consumers = map (p: p.drvPath) [ tools.chromeDevtoolsMcp
                      tools.piCodexGoalPackage tools.piPrReviewGoalPackage
                      tools.piParallelGoPrHerdrPackage tools.piExecutionTimePackage ];
                  }
                '''.replace("REPOSITORY", json.dumps(str(REPO))).replace(
                    "MODULE", str(root / "packages/home-tools.nix")
                )
                return json.loads(subprocess.check_output(
                    ["nix", "eval", "--read-only", "--impure", "--json", "--expr", expression],
                    text=True, timeout=600,
                ))

            baseline = evaluate()
            registry_path = root / "pi-extensions/package.json"
            registry = json.loads(registry_path.read_text())
            registry["pi"]["extensions"].remove("node_modules/pi-ollama-cloud/index.ts")
            registry_path.write_text(json.dumps(registry))
            removed = evaluate()
            self.assertNotEqual(baseline["registration"], removed["registration"])
            self.assertEqual(baseline["packages"], removed["packages"])
            self.assertEqual(baseline["consumers"], removed["consumers"])

            # Re-adding registration also changes no package or consumer build.
            shutil.copyfile(REPO / "pi-extensions/package.json", registry_path)
            self.assertEqual(baseline, evaluate())

            # A real per-package source change invalidates exactly that package.
            package_path = root / "pi-extensions/pi-ollama-cloud/package.json"
            package = json.loads(package_path.read_text())
            package["description"] = "Isolation test source change"
            package_path.write_text(json.dumps(package))
            changed = evaluate()
            affected = [name for name in baseline["packages"]
                        if baseline["packages"][name] != changed["packages"][name]]
            self.assertEqual(affected, ["pi-ollama-cloud"])
            self.assertEqual(baseline["consumers"], changed["consumers"])
            print("Registration removal/addition: 8 packages and 5 consumers unchanged.")
            print("Ollama source edit: only Ollama and its registration change.")

    def test_lockfiles_match_manifests(self):
        for manifest_path in sorted((REPO / "pi-extensions").glob("*/package.json")):
            with self.subTest(package=manifest_path.parent.name):
                manifest = json.loads(manifest_path.read_text())
                lock = json.loads(manifest_path.with_name("package-lock.json").read_text())
                self.assertEqual(manifest["dependencies"], lock["packages"][""]["dependencies"])
                self.assertEqual(manifest["bundledDependencies"], lock["packages"][""]["bundleDependencies"])
                # Peer packages must come from Pi, not another npm Pi install.
                self.assertFalse(any("node_modules/@earendil-works/" in path
                                     for path in lock["packages"]))


if __name__ == "__main__":
    unittest.main()
