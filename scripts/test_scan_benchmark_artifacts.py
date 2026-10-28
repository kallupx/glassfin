"""Security regressions for the benchmark upload gate (S5.5 / T09-67)."""

import contextlib
import io
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from scan_benchmark_artifacts import scan

SCRIPT = Path(__file__).with_name("scan_benchmark_artifacts.py")


class BenchmarkArtifactScanTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.result = self.root / "search-10.10.7.json"
        self.output = io.StringIO()

    def check(self, *paths):
        with contextlib.redirect_stdout(self.output), contextlib.redirect_stderr(self.output):
            return scan(list(paths))

    def test_clean_results_pass_without_changes(self):
        contents = json.dumps({
            "serverVersion": "10.10.7", "termCount": 2,
            "items": [{"termIndex": 0, "milliseconds": 1.25, "counts": [24, 24, 24]}],
            "hints": [{"termIndex": 1, "milliseconds": 2.5, "counts": [1, 0, 0]}],
            "itemsMedianMs": 1.25, "itemsP95Ms": 1.25,
            "hintsMedianMs": 2.5, "hintsP95Ms": 2.5,
        })
        self.result.write_text(contents, encoding="utf-8")
        csv = self.root / "search-10.10.7.csv"
        csv.write_text("serverVersion,backend,termCount,milliseconds\n10.10.7,items,2,1.25\n")
        before = [path.read_bytes() for path in (self.result, csv)]
        self.assertEqual(self.check(self.result, csv), 0)
        self.assertEqual([path.read_bytes() for path in (self.result, csv)], before)

    def test_every_credential_marker_fails_case_insensitively_without_rewriting(self):
        secret = "planted-credential-value"
        examples = (
            f"https://example.invalid/video?ApiKey={secret}",
            f"https://example.invalid/video?api_key={secret}",
            f'Token="{secret}"',
            f'{{"ApiKey": "{secret}"}}',
            f'{{"api_key": "{secret}"}}',
            f'{{"Token": "{secret}"}}',
            f'{{"access_token": "{secret}"}}',
            f"access_token,{secret}",
            f"accessToken={secret}",
            f"Authorization: Bearer {secret}",
            f"X-Emby-Token: {secret}",
            f"password={secret}",
            f'{{"Password": "{secret}"}}',
            f"password,{secret}",
            f"Pw = {secret}",
            f'{{"Pw": "{secret}"}}',
            f"secret={secret}",
        )
        for example in examples:
            for contents in (example, example.lower(), example.upper(), example.swapcase()):
                with self.subTest(contents=contents):
                    self.result.write_text(contents, encoding="utf-8")
                    self.assertEqual(self.check(self.result), 1)
                    self.assertEqual(self.result.read_text(encoding="utf-8"), contents)
        self.assertNotIn(secret.lower(), self.output.getvalue().lower())

    def test_one_dirty_file_blocks_the_whole_upload(self):
        self.result.write_text("{}")
        dirty = self.root / "search-12.2.json"
        dirty.write_text('"Token=planted-credential-value"')
        self.assertEqual(self.check(self.result, dirty), 1)

    def test_unlisted_files_are_not_scanned(self):
        self.result.write_text("{}")
        (self.root / "unlisted.json").write_text('"Token=planted-credential-value"')
        self.assertEqual(self.check(self.result), 0)

    def test_missing_files_directories_globs_and_xcresults_fail(self):
        self.assertEqual(self.check(), 1)
        directory = self.root / "directory.json"
        directory.mkdir()
        bundle = self.root / "run.xcresult"
        bundle.mkdir()
        nested = bundle / "search-10.10.7.json"
        nested.write_text("{}")
        for path in (self.result, directory, self.root, self.root / "*.json", bundle, nested):
            with self.subTest(path=path):
                self.assertEqual(self.check(path), 1)

    def test_cli_accepts_clean_results(self):
        self.result.write_text("{}")
        result = subprocess.run(
            [sys.executable, str(SCRIPT), str(self.result)], capture_output=True, text=True, check=False
        )
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_symlink_files_and_parent_directories_fail(self):
        self.result.write_text("{}")
        alias = self.root / "alias.json"
        alias.symlink_to(self.result)
        parent_alias = self.root / "alias"
        parent_alias.symlink_to(self.root, target_is_directory=True)
        self.assertEqual(self.check(alias), 1)
        self.assertEqual(self.check(parent_alias / self.result.name), 1)

    def test_unreadable_and_invalid_utf8_files_fail(self):
        self.result.write_bytes(b"\xff")
        self.assertEqual(self.check(self.result), 1)
        with patch.object(Path, "read_text", side_effect=PermissionError):
            self.assertEqual(self.check(self.result), 1)

    def test_cli_returns_nonzero_for_credentials_and_missing_inputs(self):
        self.result.write_text('"Token=planted-credential-value"')
        for arguments in ([], [str(self.result)], [str(self.root / "missing.json")]):
            with self.subTest(arguments=arguments):
                result = subprocess.run(
                    [sys.executable, str(SCRIPT), *arguments], capture_output=True, text=True, check=False
                )
                self.assertNotEqual(result.returncode, 0)
                self.assertNotIn("planted-credential-value", result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
