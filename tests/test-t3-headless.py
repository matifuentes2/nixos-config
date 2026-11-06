#!/usr/bin/env python3
"""Evaluate Pi headless integration and preserve the WSL release on any host."""
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[1]


class T3Headless(unittest.TestCase):
    def check_migration(self, script):
        # Exercise the evaluated activation without touching real user data or
        # systemd. Keep real mv/mktemp operations to verify backup and WAL safety.
        script = re.sub(r'/nix/store/[^/]+/bin/systemctl', 'mock_systemctl', script)
        script = re.sub(r'/nix/store/[^/]+/bin/fuser', 'mock_fuser', script)
        prelude = '''
set -eu
run() { if [ -z "${DRY_RUN:-}" ]; then "$@"; fi; }
mock_fuser() { return "${TEST_BUSY:-1}"; }
'''
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            systemctl = root / 'mock_systemctl'
            systemctl.write_text('#!/bin/sh\necho stopped >> "$TEST_STOP_LOG"\n')
            systemctl.chmod(0o700)
            script = script.replace('mock_systemctl', str(systemctl))
            legacy = root / '.local/share/t3-headless'
            target = root / '.t3'
            script = script.replace('/home/pi', tmp)
            env = dict(os.environ, TEST_STOP_LOG=str(root / 'stops'))

            def activate(**overrides):
                return subprocess.run(['bash', '-c', prelude + script],
                                      env=dict(env, **overrides), capture_output=True, text=True)

            legacy.mkdir(parents=True)
            (legacy / 'statev2.sqlite-wal').write_text('server WAL')
            target.mkdir()
            (target / 'desktop').write_text('desktop state')
            self.assertEqual(activate(DRY_RUN='1').returncode, 0)
            self.assertTrue(legacy.exists())
            self.assertFalse((root / 'stops').exists())
            self.assertNotEqual(activate(TEST_BUSY='0').returncode, 0)
            self.assertTrue(legacy.exists())
            self.assertEqual(activate().returncode, 0)
            self.assertFalse(legacy.exists())
            self.assertEqual((target / 'statev2.sqlite-wal').read_text(), 'server WAL')
            backups = list(root.glob('.t3-before-unification.*/state/desktop'))
            self.assertEqual(len(backups), 1)
            self.assertEqual(backups[0].read_text(), 'desktop state')
            self.assertEqual(activate().returncode, 0)
            self.assertEqual((root / 'stops').read_text().splitlines(), ['stopped'])
            # A fresh server with no pre-existing default state needs no backup.
            target.rename(legacy)
            self.assertEqual(activate().returncode, 0)
            self.assertTrue((target / 'statev2.sqlite-wal').exists())
            # Never follow a legacy symlink.
            legacy.symlink_to(target)
            self.assertNotEqual(activate().returncode, 0)

    def test_pi_service_and_architectures(self):
        result = json.loads(subprocess.check_output([
            "nix", "eval", "--impure", "--json", "--expr", '''
              let
                f = builtins.getFlake (toString ./.);
                c = f.nixosConfigurations.nixos.config;
                h = c.home-manager.users.pi;
                package = system:
                  let p = f.inputs.nixpkgs.legacyPackages.${system}.callPackage
                        ./packages/t3-cli.nix { };
                  in {
                    inherit (p.src) url outputHash;
                    inherit (p) dontFixup;
                  };
              in {
                arm = package "aarch64-linux";
                x64 = package "x86_64-linux";
                service = h.systemd.user.services.t3-server;
                migration = h.home.activation.unifyT3State.data;
                homePackages = map (p: p.pname or p.name) h.home.packages;
                nixLd = c.programs.nix-ld.enable;
                libraries = map (p: p.pname or p.name) c.programs.nix-ld.libraries;
                linger = c.users.users.pi.linger;
                firewall = c.networking.firewall.allowedTCPPorts;
                wslService = f.nixosConfigurations.wsl2.config.home-manager.users.matif.systemd.user.services.t3-server.Service.ExecStart;
              }
            '''
        ], cwd=REPO, text=True, timeout=240))
        self.assertTrue(result["arm"]["url"].endswith("-linux-arm64.tar.gz"))
        self.assertEqual(result["arm"]["outputHash"],
                         "5a528e23af394cc6f359036d3cb8441fda14129d477630fc6c53e4f4a1025bc8")
        self.assertTrue(result["x64"]["url"].endswith("-linux-x64.tar.gz"))
        self.assertEqual(result["x64"]["outputHash"],
                         "c089892bf7922e2e73c6f44a5d1ea125c99f70e378c18361cbbed2fba1920e6c")
        self.assertTrue(result["arm"]["dontFixup"])
        self.assertTrue(result["x64"]["dontFixup"])
        for package in ("t3-cli", "t3-code"):
            self.assertIn(package, result["homePackages"])
        self.assertNotIn("t3-headless", result["homePackages"])
        migration = result["migration"]
        self.check_migration(migration)
        self.assertIn('/home/pi/.local/share/t3-headless', migration)
        self.assertIn('/home/pi/.t3', migration)
        self.assertLess(migration.index('stop t3-server.service'),
                        migration.index('mv -- "$legacy" "$target"'))
        self.assertIn('mv -- "$target" "$backup/state"', migration)
        service = result["service"]
        self.assertIn("/bin/t3 serve --host 127.0.0.1 --port 3774 --no-browser /home/pi",
                      service["Service"]["ExecStart"][0])
        self.assertIn("/etc/profiles/per-user/pi/bin", service["Service"]["Environment"][0])
        self.assertNotIn("T3CODE_HOME", json.dumps(service))
        self.assertEqual(service["Service"]["Restart"], "on-failure")
        self.assertEqual(service["Service"]["UMask"], "0077")
        self.assertEqual(service["Install"]["WantedBy"], ["default.target"])
        self.assertTrue(result["nixLd"])
        self.assertTrue(result["linger"])
        self.assertIn("libsecret", result["libraries"])
        self.assertIn("libffi", result["libraries"])
        self.assertNotIn(3774, result["firewall"])
        self.assertIn("--host 0.0.0.0 --port 3773", result["wslService"][0])


if __name__ == "__main__":
    unittest.main()
