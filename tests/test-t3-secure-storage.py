#!/usr/bin/env python3
"""Check pinned Lenovo PAM and exercise T3 wrapping without a Linux builder."""
import json
import os
from pathlib import Path
import shlex
import subprocess
import unittest

REPO = Path(__file__).resolve().parents[1]


def nix_json(*args):
    return json.loads(subprocess.check_output(
        ["nix", *args], cwd=REPO, text=True, timeout=240,
    ))


class T3SecureStorage(unittest.TestCase):
    def test_pinned_lenovo_keyring(self):
        result = nix_json("eval", "--impure", "--json", "--expr", '''
          let
            f = builtins.getFlake (toString ./.);
            c = f.nixosConfigurations.amd64-lenovo-legion-y720.config;
          in {
            enabled = c.services.gnome.gnome-keyring.enable;
            sddmEnabled = c.services.displayManager.sddm.enable;
            sddmKeyring = c.security.pam.services.sddm.enableGnomeKeyring;
            loginKeyring = c.security.pam.services.login.enableGnomeKeyring;
            sddmPam = c.security.pam.services.sddm.text;
            loginPam = c.security.pam.services.login.text;
            dbusPackages = map (p: p.pname or p.name) c.services.dbus.packages;
            homePackages = map (p: p.pname or p.name) c.home-manager.users.matif.home.packages;
            piKeyring = f.nixosConfigurations.nixos.config.services.gnome.gnome-keyring.enable;
            wslKeyring = f.nixosConfigurations.wsl2.config.services.gnome.gnome-keyring.enable;
          }
        ''')
        for key in ("enabled", "sddmEnabled", "sddmKeyring", "loginKeyring"):
            self.assertTrue(result[key], key)
        self.assertFalse(result["piKeyring"])
        self.assertFalse(result["wslKeyring"])
        self.assertIn("gnome-keyring", result["dbusPackages"])
        self.assertIn("seahorse", result["homePackages"])
        # Pinned SDDM uses the login stack, not the default per-service rules.
        self.assertRegex(result["sddmPam"], r"auth\s+substack\s+login")
        self.assertRegex(result["sddmPam"], r"session\s+include\s+login")
        for facility in ("auth", "session"):
            lines = [line for line in result["loginPam"].splitlines()
                     if line.startswith(facility) and "pam_gnome_keyring.so" in line]
            self.assertTrue(lines, facility)
            if facility == "session":
                self.assertIn("auto_start", lines[0])

    def test_real_install_commands_with_mock_fhs_launcher(self):
        # Use the actual package expression and makeWrapper hook. Only the
        # AppImage/FHS boundary is mocked, so this also runs on macOS without
        # downloading or executing the Linux AppImage.
        builds = nix_json("build", "--no-link", "--impure", "--json", "--expr", r'''
          let
            f = builtins.getFlake (toString ./.);
            pkgs = f.inputs.nixpkgs.legacyPackages.${builtins.currentSystem};
            launcher = pkgs.writeShellScript "mock-t3-fhs-launcher" ''
              printf '%s\n' "$@"
            '';
          in pkgs.callPackage ./packages/t3-code.nix {
            appimageTools.wrapType2 = args:
              pkgs.runCommand "t3-secure-storage-launcher-test" {
                inherit (args) nativeBuildInputs;
              } ''
                mkdir -p "$out/bin"
                ln -s ${launcher} "$out/bin/t3-code"
                ${args.extraInstallCommands}
                test -L "$out/bin/.t3-code-wrapped"
                test "$(readlink "$out/bin/.t3-code-wrapped")" = "${launcher}"
              '';
          }
        ''')
        output = Path(builds[0]["outputs"]["out"])
        command = output / "bin/t3-code"
        extra = ["--example", "argument with spaces"]
        expected = ["--password-store=gnome-libsecret", *extra]
        self.assertEqual(subprocess.check_output([str(command), *extra], text=True).splitlines(), expected)
        desktop = (output / "share/applications/t3-code.desktop").read_text()
        entry = next(line.removeprefix("Exec=") for line in desktop.splitlines() if line.startswith("Exec="))
        self.assertEqual(shlex.split(entry), ["t3-code"])
        env = {**os.environ, "PATH": str(output / "bin") + os.pathsep + os.environ["PATH"]}
        self.assertEqual(subprocess.check_output(
            [*shlex.split(entry), *extra], text=True, env=env,
        ).splitlines(), expected)


if __name__ == "__main__":
    unittest.main()
