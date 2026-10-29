#!/usr/bin/env python3
"""Evaluate Collie removal without building or switching either Linux host."""
import json
import pathlib
import subprocess
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
            macLinksCollie = builtins.hasAttr "linkHerdrCollie"
              f.darwinConfigurations.macbook.config.home-manager.users.matif.home.activation;
            wslLinksCollie = builtins.hasAttr "linkHerdrCollie"
              f.nixosConfigurations.wsl2.config.home-manager.users.matif.home.activation;
          }
        '''
        result = json.loads(subprocess.check_output(
            ["nix", "eval", "--impure", "--json", "--expr", expression],
            cwd=REPO, text=True, timeout=180,
        ))
        self.assertTrue(result["macLinksCollie"])
        self.assertTrue(result["wslLinksCollie"])
        for host in ("pi", "lenovo"):
            with self.subTest(host=host):
                config = result[host]
                for key in ("services", "secrets", "tmpfiles"):
                    self.assertFalse(any("collie" in item for item in config[key]))
                self.assertNotIn("linkHerdrCollie", config["activation"])
                self.assertIn("removeHerdrCollie", config["activation"])
                self.assertIn("collie-ctl.sh uninstall", config["cleanup"])
                self.assertIn("plugin unlink herdr.collie", config["cleanup"])
                subprocess.run(["bash", "-n"], input=config["cleanup"], text=True, check=True)


if __name__ == "__main__":
    unittest.main()
