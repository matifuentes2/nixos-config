"""Regression checks for safe updates to mutable Orca profiles.

Run with: python3 tests/test-orca-settings.py (requires Bash and jq on PATH).
"""

import json
from pathlib import Path
import subprocess
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / "scripts/update-orca-settings.sh"


class OrcaSettingsTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix="orca-settings-test-")
        self.addCleanup(self.directory.cleanup)
        self.profile = Path(self.directory.name) / "profile with spaces" / "orca-data.json"

    def update(self, settings='{"defaultTuiAgent":"pi"}'):
        return subprocess.run(
            ["bash", str(SCRIPT), str(self.profile), settings],
            capture_output=True,
            text=True,
            check=False,
        )

    def write_profile(self, content):
        self.profile.parent.mkdir(parents=True, exist_ok=True)
        self.profile.write_bytes(content)

    def assert_no_temporary_files(self):
        self.assertEqual(list(self.profile.parent.glob("orca-data.json.tmp.*")), [])

    def test_creates_missing_profile_privately(self):
        result = self.update()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            json.loads(self.profile.read_text()),
            {"schemaVersion": 1, "settings": {"defaultTuiAgent": "pi"}},
        )
        self.assertEqual(self.profile.stat().st_mode & 0o777, 0o600)
        self.assert_no_temporary_files()

    def test_preserves_unmanaged_state_and_is_idempotent(self):
        self.write_profile(
            b'{"schemaVersion":1,"sessions":["keep"],'
            b'"settings":{"theme":"dark","defaultTuiAgent":"old"}}'
        )
        result = self.update()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            json.loads(self.profile.read_text()),
            {
                "schemaVersion": 1,
                "sessions": ["keep"],
                "settings": {"theme": "dark", "defaultTuiAgent": "pi"},
            },
        )
        first_result = self.profile.read_bytes()
        self.assertEqual(self.update().returncode, 0)
        self.assertEqual(self.profile.read_bytes(), first_result)
        self.assert_no_temporary_files()

    def test_accepts_missing_or_null_settings(self):
        for content in (b'{"schemaVersion":1}', b'{"settings":null}'):
            with self.subTest(content=content):
                self.write_profile(content)
                self.assertEqual(self.update().returncode, 0)
                self.assertEqual(
                    json.loads(self.profile.read_text())["settings"],
                    {"defaultTuiAgent": "pi"},
                )

    def test_rejects_invalid_profiles_without_modifying_them(self):
        for content in (
            b"",
            b"{broken",
            b"{}\n{}",
            b"null",
            b"[]",
            b'{"settings":"unexpected-type","saved":"keep-me"}',
            b'{"settings":[]}',
        ):
            with self.subTest(content=content):
                self.write_profile(content)
                self.assertNotEqual(self.update().returncode, 0)
                self.assertEqual(self.profile.read_bytes(), content)
                self.assert_no_temporary_files()

    def test_rejects_invalid_managed_settings(self):
        for settings in ("{broken", "null", "[]"):
            with self.subTest(settings=settings):
                self.write_profile(b'{"saved":"keep-me"}')
                self.assertNotEqual(self.update(settings).returncode, 0)
                self.assertEqual(self.profile.read_bytes(), b'{"saved":"keep-me"}')
                self.assert_no_temporary_files()


if __name__ == "__main__":
    unittest.main()
