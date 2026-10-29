"""Playback diagnostics export tests; no simulator or server is used."""

import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location(
    "playback_diagnostics", Path(__file__).with_name("collect-playback-diagnostics.py"))
diagnostics = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(diagnostics)


class PlaybackDiagnosticsTests(unittest.TestCase):
    def test_host_fallback_exports_only_safe_summaries(self):
        with tempfile.TemporaryDirectory() as directory:
            repo = Path(directory)
            root = repo / "glassfin-e2e-123-1"
            root.mkdir()
            (root / "simulator.json").write_text(json.dumps("synthetic-device"))
            summary = "AVPlayer failure: NSURLErrorDomain(-1001)"
            results = [
                subprocess.CompletedProcess([], 1, "", "private simulator error"),
                subprocess.CompletedProcess([], 0, "process: " + summary + "\nApiKey=synthetic-secret", ""),
            ]
            with patch.dict(os.environ, {"CI": "true", "RUNNER_TEMP": directory,
                                         "GITHUB_RUN_ID": "123", "GITHUB_RUN_ATTEMPT": "1"}), \
                 patch.object(diagnostics, "__file__", str(repo / "scripts/ci/collector.py")), \
                 patch.object(diagnostics.subprocess, "run", side_effect=results) as run:
                diagnostics.main()
            self.assertEqual(run.call_args_list[1].args[0][0], "/usr/bin/log")
            output = json.loads((repo / "artifacts/jellyfin-e2e/playback-diagnostics.json").read_text())
            self.assertEqual(output, {"available": True, "lines": [summary]})

    def test_retains_only_domain_code_summary_without_process_metadata(self):
        summary = "AVPlayer failure: AVFoundationErrorDomain(-11800) <- CoreMediaErrorDomain(-12881)"
        self.assertEqual(diagnostics.summaries("timestamp process[123]: " + summary), [summary])

    def test_rejects_unstructured_text_urls_queries_and_unknown_domains(self):
        for text in [
            "https://private.invalid/?ApiKey=synthetic-secret",
            "AVPlayer failure: https://private.invalid(401)",
            "AVPlayer failure: NSURLErrorDomain(-1001)?ApiKey=synthetic-secret",
            "AVPlayer failure: NSURLErrorDomain(-1001) https://private.invalid",
        ]:
            self.assertEqual(diagnostics.summaries(text), [])

    def test_accepts_missing_and_redacted_domains(self):
        for summary in [
            "AVPlayer failure: item error unavailable",
            "AVPlayer failure: <redacted-domain>(1) <- NSURLErrorDomain(-1001)",
        ]:
            self.assertEqual(diagnostics.summaries(summary), [summary])


if __name__ == "__main__":
    unittest.main()
