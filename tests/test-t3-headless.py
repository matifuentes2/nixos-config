#!/usr/bin/env python3
"""Evaluate Pi headless integration and preserve the WSL release on any host."""
import json
from pathlib import Path
import subprocess
import unittest

REPO = Path(__file__).resolve().parents[1]


class T3Headless(unittest.TestCase):
    def test_pi_service_and_architectures(self):
        result = json.loads(subprocess.check_output([
            "nix", "eval", "--impure", "--json", "--expr", '''
              let
                f = builtins.getFlake (toString ./.);
                c = f.nixosConfigurations.nixos.config;
                h = c.home-manager.users.pi;
                headless = builtins.head (builtins.filter
                  (p: (p.pname or p.name) == "t3-headless") h.home.packages);
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
                wrapper = headless.text;
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
        for package in ("t3-cli", "t3-headless", "t3-code"):
            self.assertIn(package, result["homePackages"])
        self.assertIn("T3CODE_HOME=/home/pi/.local/share/t3-headless", result["wrapper"])
        self.assertIn('exec t3 "$@"', result["wrapper"])
        service = result["service"]
        self.assertIn("t3-headless serve --host 127.0.0.1 --port 3774 --no-browser /home/pi",
                      service["Service"]["ExecStart"][0])
        self.assertIn("/etc/profiles/per-user/pi/bin", service["Service"]["Environment"][0])
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
