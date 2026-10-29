#!/usr/bin/env python3
"""Evaluate Collie removal without building or switching any host."""
import json
import os
import pathlib
import re
import subprocess
import tempfile
import unittest

REPO = pathlib.Path(__file__).resolve().parents[1]


class CollieRemoval(unittest.TestCase):
    def test_host_configuration(self):
        expression = '''
          let
            f = builtins.getFlake (toString ./.);
            inspect = host: user:
              let
                c = host.config;
                h = builtins.getAttr user c.home-manager.users;
              in {
                services = builtins.attrNames h.systemd.user.services;
                secrets = builtins.attrNames c.sops.secrets;
                tmpfiles = c.systemd.tmpfiles.rules;
                activation = builtins.attrNames h.home.activation;
                cleanup = h.home.activation.removeHerdrCollie.data;
              };
          in {
            pi = inspect f.nixosConfigurations.nixos "pi";
            lenovo = inspect f.nixosConfigurations.amd64-lenovo-legion-y720 "matif";
            mac = let h = f.darwinConfigurations.macbook.config.home-manager.users.matif; in {
              services = builtins.attrNames h.launchd.agents;
              secrets = [ ];
              tmpfiles = [ ];
              activation = builtins.attrNames h.home.activation;
              cleanup = h.home.activation.removeHerdrCollie.data;
            };
            wslLinksCollie = builtins.hasAttr "linkHerdrCollie"
              f.nixosConfigurations.wsl2.config.home-manager.users.matif.home.activation;
          }
        '''
        result = json.loads(subprocess.check_output(
            ["nix", "eval", "--impure", "--json", "--expr", expression],
            cwd=REPO, text=True, timeout=180,
        ))
        self.assertTrue(result["wslLinksCollie"])
        self.assertNotIn("systemctl", result["mac"]["cleanup"])
        self.assertNotIn("/systemd/", result["mac"]["cleanup"])
        for host in ("pi", "lenovo", "mac"):
            with self.subTest(host=host):
                config = result[host]
                for key in ("services", "secrets", "tmpfiles"):
                    self.assertFalse(any("collie" in item for item in config[key]))
                self.assertNotIn("linkHerdrCollie", config["activation"])
                self.assertIn("removeHerdrCollie", config["activation"])
                self.assertIn("collie-ctl.sh stop", config["cleanup"])
                self.assertIn("collie-ctl.sh unserve", config["cleanup"])
                self.assertIn("plugin unlink herdr.collie", config["cleanup"])
                subprocess.run(["bash", "-n"], input=config["cleanup"], text=True, check=True)
                self.check_replaced_mapping(config["cleanup"], host)

    def check_replaced_mapping(self, cleanup, host):
        """Mock all external actions: a refused Serve cleanup must not abort removal."""
        with tempfile.TemporaryDirectory(prefix="collie-removal-test-") as temporary:
            root = pathlib.Path(temporary)
            log = root / "actions"
            # Only these two tools are called outside Home Manager's run helper.
            for name, body in {
                "herdr": "printf '%s\\n' '{\"result\":{\"plugins\":[{}]}}'",
                "jq": "exit 0",
            }.items():
                tool = root / name
                tool.write_text("#!/bin/sh\n" + body + "\n")
                tool.chmod(0o755)
                cleanup = re.sub(r"/nix/store/[^/\s]+/bin/" + name, str(tool), cleanup)
            cleanup = re.sub(
                r"export HERDR_PLUGIN_CONFIG_DIR=.*",
                "export HERDR_PLUGIN_CONFIG_DIR=" + str(root / "config"), cleanup,
            )
            prefix = '''
              set -eu
              run() {
                printf '%s\\n' "$*" >> "$TEST_LOG"
                case "$*" in
                  *"collie-ctl.sh unserve") return 1 ;;
                esac
                return 0
              }
            '''
            completed = subprocess.run(
                ["bash"], input=prefix + cleanup, text=True, capture_output=True,
                env={**os.environ, "HOME": str(root), "TEST_LOG": str(log)},
            )
            self.assertEqual(completed.returncode, 0, completed.stderr)
            self.assertIn("preserved Tailscale Serve", completed.stderr)
            actions = log.read_text()
            self.assertIn("plugin unlink herdr.collie", actions)
            if host == "mac":
                self.assertIn("Library/LaunchAgents/herdr.collie.plist", actions)
            else:
                self.assertIn("systemd/user/collie.service", actions)
            self.assertNotIn("serve reset", actions)


if __name__ == "__main__":
    unittest.main()
