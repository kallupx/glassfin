"""Regression checks use mocked downloads/APIs and isolated temporary state only."""
import importlib.util
import io
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch
import urllib.error

MODULE_PATH = Path(__file__).with_name("jellyfin-e2e.py")
sys.path.insert(0, str(MODULE_PATH.parents[1]))
SPEC = importlib.util.spec_from_file_location("jellyfin_e2e", MODULE_PATH)
e2e = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(e2e)


class NativeJellyfinTests(unittest.TestCase):
    def test_start_waits_for_wizard_after_public_info_becomes_available(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            listeners = unittest.mock.Mock(stdout="p123\nn127.0.0.1:8096\n")
            udp = unittest.mock.Mock(stdout=b"")
            with patch.object(e2e.socket, "socket"), \
                 patch.object(e2e.subprocess, "Popen") as process, \
                 patch.object(e2e.subprocess, "run", side_effect=[listeners, udp]), \
                 patch.object(e2e.time, "sleep") as sleep, \
                 patch.object(e2e, "request", side_effect=[
                     {"StartupWizardCompleted": False},
                     RuntimeError("local API GET /Startup/Configuration HTTP 503"),
                     {"ServerName": ""},
                 ]) as request:
                process.return_value.pid = 123
                e2e.start(root)
            self.assertEqual(request.call_args_list, [
                unittest.mock.call("GET", "/System/Info/Public"),
                unittest.mock.call("GET", "/Startup/Configuration"),
                unittest.mock.call("GET", "/Startup/Configuration"),
            ])
            sleep.assert_called_once_with(1)

    def test_checksum_mismatch_never_extracts_or_starts_anything(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            with patch.object(e2e.platform, "system", return_value="Darwin"), \
                 patch.object(e2e.platform, "machine", return_value="arm64"), \
                 patch.object(e2e.urllib.request, "urlopen", return_value=io.BytesIO(b"tampered archive")), \
                 patch.object(e2e.subprocess, "run") as run:
                with self.assertRaisesRegex(RuntimeError, "SHA-256 mismatch"):
                    e2e.install(root)
                run.assert_not_called()
                self.assertFalse((root / "server").exists())

    def test_committed_pins_are_exact_official_versions_for_both_architectures(self):
        pins = json.loads((MODULE_PATH.parent / "jellyfin-macos-pins.json").read_text())
        for architecture in ["arm64", "x86_64"]:
            for kind in ["server", "ffmpeg"]:
                pin = pins[architecture][kind]
                self.assertTrue(pin["url"].startswith("https://repo.jellyfin.org/files/"))
                self.assertNotIn("latest", pin["url"])
                version = pins["serverVersion" if kind == "server" else "ffmpegVersion"]
                self.assertIn(version, pin["url"])
                self.assertRegex(pin["sha256"], r"^[0-9a-f]{64}$")

    def test_api_cannot_redirect_to_another_server(self):
        handler = e2e.NoRedirect()
        self.assertIsNone(handler.redirect_request(None, None, 302, "Found", {}, "https://external.invalid"))
        with patch.object(e2e.API, "open") as open_api:
            with self.assertRaisesRegex(RuntimeError, "invalid local API path"):
                e2e.request("GET", "//external.invalid")
            open_api.assert_not_called()

    def test_http_errors_do_not_include_response_or_request_secrets(self):
        error = urllib.error.HTTPError(e2e.BASE, 401, "sensitive response", {}, io.BytesIO(b"private body"))
        with patch.object(e2e.API, "open", side_effect=error):
            with self.assertRaisesRegex(RuntimeError, r"local API POST /Users/AuthenticateByName HTTP 401$"):
                e2e.request("POST", "/Users/AuthenticateByName", {"Pw": "private body"})

    def test_missing_acceptance_suite_is_reported_without_running_xcode(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            with patch.object(e2e, "REPO", root), patch.object(e2e.subprocess, "run") as run:
                e2e.run_tests(root)
                run.assert_not_called()
            result = json.loads((root / "tests.json").read_text())
            self.assertEqual(result["acceptance"], "unavailable")
            self.assertEqual(result["testsRun"], 0)

    def test_acceptance_run_requires_journeys_and_passes_config_only_through_environment(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            acceptance = root / "Apps/Shared/UITests/TPOCPlaybackAcceptanceUITests.swift"
            acceptance.parent.mkdir(parents=True)
            acceptance.write_text("// suite")
            secret = "viewer-password-sentinel"
            runner = {
                "TEST_RUNNER_GLASSFIN_POC_SERVER_URL": e2e.BASE,
                "TEST_RUNNER_GLASSFIN_POC_USERNAME": "viewer",
                "TEST_RUNNER_GLASSFIN_POC_PASSWORD": secret,
                "TEST_RUNNER_GLASSFIN_POC_ADMIN_USERNAME": "admin",
                "TEST_RUNNER_GLASSFIN_POC_ADMIN_PASSWORD": "admin-password-sentinel",
            }
            (root / "runner-env.json").write_text(json.dumps(runner))
            devices = json.dumps({"devices": {"com.apple.CoreSimulator.SimRuntime.tvOS-26-0": [{"udid": "TV-1"}]}})
            with patch.object(e2e, "REPO", root), \
                 patch.object(e2e.shutil, "which", return_value="/usr/local/bin/xcodegen"), \
                 patch.object(e2e.subprocess, "check_output", return_value=devices), \
                 patch.object(e2e.subprocess, "run", return_value=unittest.mock.Mock(returncode=0)) as run:
                e2e.run_tests(root)
            calls = [call for call in run.call_args_list if "test-without-building" in call.args[0]]
            self.assertEqual(len(calls), 1)
            argv, environment = calls[0].args[0], calls[0].kwargs["env"]
            self.assertIn("-only-testing:Glassfin-tvOSUITests/TPOCPlaybackAcceptanceUITests", argv)
            self.assertEqual(environment["TEST_RUNNER_GLASSFIN_POC_REQUIRED"], "1")
            for key, value in runner.items():
                self.assertEqual(environment[key], value)
            for value in runner.values():
                if value != e2e.BASE:
                    self.assertFalse(any(value in argument for argument in argv))
            self.assertEqual(json.loads((root / "tests.json").read_text())["acceptance"], "passed")

    def test_cleanup_deletes_private_results_and_scans_every_uploaded_file(self):
        with tempfile.TemporaryDirectory() as directory:
            repo = Path(directory)
            root = repo / "private"
            root.mkdir()
            sentinel = "generated-credential-value"
            (root / "sensitive.json").write_text(json.dumps([sentinel]))
            (root / "server.log").write_text(f"Started\n{sentinel}\nAuthorization: private-value\n")
            bundle = root / "DerivedData/test.xcresult"
            bundle.mkdir(parents=True)
            (bundle / "private.bin").write_bytes(sentinel.encode())
            output = repo / "github-output"
            with patch.object(e2e, "REPO", repo), patch.dict(os.environ, {"GITHUB_OUTPUT": str(output)}):
                e2e.cleanup(root)
            self.assertFalse(root.exists())
            files = list((repo / "artifacts/jellyfin-e2e").iterdir())
            self.assertGreaterEqual(len(files), 2)
            for path in files:
                self.assertEqual(path.suffix, ".json")
                contents = path.read_text()
                self.assertNotIn(sentinel, contents)
                self.assertNotIn("private-value", contents)
                self.assertNotIn("Authorization", contents)
            self.assertIn("safe=true", output.read_text())

    def test_cleanup_cannot_authorize_upload_after_scan_failure(self):
        with tempfile.TemporaryDirectory() as directory:
            repo = Path(directory)
            root = repo / "private"
            root.mkdir()
            output = repo / "github-output"
            with patch.object(e2e, "REPO", repo), patch.dict(os.environ, {"GITHUB_OUTPUT": str(output)}), \
                 patch("scan_benchmark_artifacts.scan", return_value=1):
                with self.assertRaisesRegex(RuntimeError, "upload blocked"):
                    e2e.cleanup(root)
            self.assertFalse(output.exists())


if __name__ == "__main__":
    unittest.main()
