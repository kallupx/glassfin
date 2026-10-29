"""Playback diagnostics export tests; no simulator or server is used."""

import importlib.util
from pathlib import Path
import unittest

SPEC = importlib.util.spec_from_file_location(
    "playback_diagnostics", Path(__file__).with_name("collect-playback-diagnostics.py"))
diagnostics = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(diagnostics)


class PlaybackDiagnosticsTests(unittest.TestCase):
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
