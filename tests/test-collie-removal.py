#!/usr/bin/env python3
"""Evaluate Collie removal without building or switching any host."""
import json
import os
import pathlib
import re
import subprocess
import sys
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
                self.assertIn("remove-collie-plugin.py", config["cleanup"])
                subprocess.run(["bash", "-n"], input=config["cleanup"], text=True, check=True)
                self.check_replaced_mapping(config["cleanup"], host)

    def check_replaced_mapping(self, cleanup, host):
        """Mock all external actions: a refused Serve cleanup must not abort removal."""
        with tempfile.TemporaryDirectory(prefix="collie-removal-test-") as temporary:
            root = pathlib.Path(temporary)
            log = root / "actions"
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
            self.assertIn("remove-collie-plugin.py", actions)
            if host == "mac":
                self.assertIn("Library/LaunchAgents/herdr.collie.plist", actions)
            else:
                self.assertIn("systemd/user/collie.service", actions)
            self.assertNotIn("serve reset", actions)


class OfflineCollieRemoval(unittest.TestCase):
    def test_offline_registry_migration(self):
        with tempfile.TemporaryDirectory(prefix="collie-offline-test-") as temporary:
            root = pathlib.Path(temporary)
            herdr = root / "herdr"
            herdr.write_text(
                "#!/bin/sh\n"
                "echo '{\"error\":{\"code\":\"server_not_running\"}}'\nexit 1\n"
            )
            herdr.chmod(0o755)
            helper = REPO / "modules/home/remove-collie-plugin.py"
            command = [sys.executable, str(helper), str(root), str(herdr)]
            registry = root / "plugins.json"
            # Missing registries are an idempotent no-op.
            subprocess.run(command, check=True, capture_output=True)
            self.assertFalse(registry.exists())
            target = root / "registry-target.json"
            registry.symlink_to(target.name)
            other = {"plugin_id": "worktrunk", "enabled": True, "custom": ["preserve"]}
            target.write_text(json.dumps([other, {"plugin_id": "herdr.collie"}]))
            target.chmod(0o600)
            subprocess.run(command, check=True, capture_output=True)
            self.assertTrue(registry.is_symlink())
            self.assertEqual(json.loads(target.read_text()), [other])
            self.assertEqual(target.stat().st_mode & 0o777, 0o600)
            unchanged = target.stat().st_mtime_ns
            subprocess.run(command, check=True, capture_output=True)
            self.assertEqual(target.stat().st_mtime_ns, unchanged)
            # Malformed data must fail without overwriting anything.
            target.write_text('{"unknown_schema": true}')
            self.assertNotEqual(subprocess.run(command, capture_output=True).returncode, 0)
            self.assertEqual(target.read_text(), '{"unknown_schema": true}')
            # Other server errors must not silently trigger an offline mutation.
            herdr.write_text("#!/bin/sh\necho '{\"error\":{\"code\":\"permission_denied\"}}'\nexit 1\n")
            original = json.dumps([other, {"plugin_id": "herdr.collie"}])
            target.write_text(original)
            self.assertNotEqual(subprocess.run(command, capture_output=True).returncode, 0)
            self.assertEqual(target.read_text(), original)
            # With a live server, trust its unlink result; do not edit its registry.
            herdr.write_text("#!/bin/sh\necho '{\"result\":{\"removed\":true}}'\nexit 0\n")
            subprocess.run(command, check=True, capture_output=True)
            self.assertEqual(target.read_text(), original)


if __name__ == "__main__":
    unittest.main()
