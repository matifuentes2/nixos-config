#!/usr/bin/env python3
"""Check that hgrai exposes leased CUA to its unprivileged Codex account."""
import json
from pathlib import Path
import subprocess
import unittest

REPO = Path(__file__).resolve().parents[1]


class HgraiCua(unittest.TestCase):
    def test_headless_pool_boundaries(self):
        result = json.loads(subprocess.check_output([
            "nix", "eval", "--impure", "--json", "--expr", '''
              let
                f = builtins.getFlake (toString ./.);
                c = f.nixosConfigurations.hgrai.config;
                h = c.home-manager.users.coding-agent;
                s = h.systemd.user.services;
              in {
                linger = c.users.users.coding-agent.linger;
                groups = c.users.users.coding-agent.extraGroups;
                ports = c.networking.firewall.allowedTCPPorts;
                xserver = c.services.xserver.enable;
                t3Start = c.systemd.user.services.t3-server.serviceConfig.ExecStart;
                broker = s.cua-pool-manager.Install.WantedBy;
                legacy = s.cua-agent-desktop.Install.WantedBy;
                legacyDriver = s.cua-driver.Install.WantedBy;
                slot = s.cua-pool-slot-1.Service;
                slice = h.systemd.user.slices.cua-pool.Slice;
                slots = h.services.cua-driver.agentDesktop.pool.slots;
                mcp = h.home.activation.configureCuaMcp.data;
                skills = builtins.attrNames h.home.file;
              }
            '''
        ], cwd=REPO, text=True, timeout=240))
        self.assertTrue(result["linger"])
        self.assertFalse(set(result["groups"]) & {"wheel", "docker"})
        self.assertEqual(result["ports"], [22])
        self.assertFalse(result["xserver"])
        self.assertIn("--host 127.0.0.1 --port 3773", result["t3Start"])
        self.assertEqual(result["broker"], ["default.target"])
        self.assertEqual(result["legacy"], [])
        self.assertEqual(result["legacyDriver"], [])
        self.assertEqual(result["slots"], 2)
        self.assertEqual(result["slice"]["MemoryMax"], "4G")
        self.assertEqual(result["slice"]["CPUQuota"], "200%")
        self.assertEqual(result["slot"]["KillMode"], "control-group")
        self.assertEqual(result["slot"]["RuntimeDirectoryMode"], "0700")
        self.assertIn("codex mcp add cua-driver --", result["mcp"])
        self.assertIn("/bin/cua-pool mcp", result["mcp"])
        for name in ("cua-driver", "cua-agent-desktop/SKILL.md"):
            self.assertIn(f".agents/skills/{name}", result["skills"])


if __name__ == "__main__":
    unittest.main()
