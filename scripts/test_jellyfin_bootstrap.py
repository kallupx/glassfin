"""Exercise bootstrap recovery without Docker or a live Jellyfin server."""

import contextlib
import importlib.util
import io
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch


with patch.dict(os.environ, {
    "GLASSFIN_SERVER_URL": "http://localhost:8096",
    "GLASSFIN_USERNAME": "test-user",
    "GLASSFIN_PASSWORD": "test-password",
}):
    spec = importlib.util.spec_from_file_location(
        "jellyfin_bootstrap", Path(__file__).with_name("jellyfin_bootstrap.py"))
    bootstrap = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(bootstrap)

TOKEN = "test-access-token"
MOVIES = {"Name": "Movies", "Locations": ["/media/Movies"]}
SCAN = {"Id": "scan-id", "Key": "RefreshLibrary", "State": "Idle"}


def response(value, status=200):
    return status, json.dumps(value).encode()


class BootstrapTests(unittest.TestCase):
    def setUp(self):
        self.enterContext(patch.object(bootstrap, "MEDIA_DIR", "/media"))
        self.enterContext(patch.object(bootstrap, "PASSWORD", "test-password"))
        self.now = 0
        self.output = io.StringIO()
        self.enterContext(contextlib.redirect_stderr(self.output))
        self.enterContext(contextlib.redirect_stdout(self.output))
        self.enterContext(patch.object(bootstrap.time, "monotonic", side_effect=lambda: self.now))
        self.enterContext(patch.object(bootstrap.time, "sleep", side_effect=self.advance))

    def advance(self, seconds):
        self.now += seconds

    def test_scan_readiness_waits_for_worker_and_two_idle_reads(self):
        with patch.object(bootstrap, "request", side_effect=[
            response(None, 503), response([]), response([{**SCAN, "State": "Running"}]),
            response([SCAN]), response([{**SCAN, "State": "Cancelling"}]),
            response([SCAN]), response([SCAN]),
        ]) as request:
            bootstrap.wait_for_scan_ready(TOKEN)
        self.assertEqual(request.call_count, 7)
        self.assertEqual(self.now, 12)
        self.assertTrue(all(call.args == ("GET", "/ScheduledTasks") for call in request.call_args_list))

    def test_query_creation_verifies_path_without_triggering_scan(self):
        with patch.object(bootstrap, "request", side_effect=[
            response([]), (204, b""), response([MOVIES]),
        ]) as request:
            bootstrap.add_library(TOKEN, "Movies", "movies")
        self.assertEqual(request.call_count, 3)
        query = request.call_args_list[1].kwargs["query"]
        self.assertEqual(query["paths"], "/media/Movies")
        self.assertEqual(query["refreshLibrary"], "false")

    def test_ignored_query_path_is_repaired_without_duplicate_library(self):
        empty = {"Name": "Movies", "Locations": []}
        with patch.object(bootstrap, "request", side_effect=[
            response([]), (204, b""), response([empty]), (204, b""), response([MOVIES]),
        ]) as request:
            bootstrap.add_library(TOKEN, "Movies", "movies")
        posts = [call for call in request.call_args_list if call.args[0] == "POST"]
        self.assertEqual([call.args[1] for call in posts], [
            "/Library/VirtualFolders", "/Library/VirtualFolders/Paths"])
        self.assertEqual(posts[1].kwargs["body"]["PathInfo"], {"Path": "/media/Movies"})
        self.assertEqual(posts[1].kwargs["query"]["refreshLibrary"], "false")

    def test_failed_query_creation_falls_back_to_path_infos_body(self):
        with patch.object(bootstrap, "request", side_effect=[
            response([]), (400, b""), response([]), (204, b""), response([MOVIES]),
        ]) as request:
            bootstrap.add_library(TOKEN, "Movies", "movies")
        fallback = request.call_args_list[3]
        self.assertEqual(fallback.kwargs["body"]["LibraryOptions"]["PathInfos"], [{"Path": "/media/Movies"}])
        self.assertNotIn("paths", fallback.kwargs["query"])
        self.assertEqual(fallback.kwargs["query"]["refreshLibrary"], "false")

    def test_partial_creation_on_server_error_is_not_repeated(self):
        with patch.object(bootstrap, "request", side_effect=[
            response([]), (500, b""), response([MOVIES]),
        ]) as request:
            bootstrap.add_library(TOKEN, "Movies", "movies")
        self.assertEqual(request.call_count, 3)

    def test_refresh_retries_server_and_transport_errors_with_backoff(self):
        with patch.object(bootstrap, "request", side_effect=[
            (500, b""), (503, b""), (0, b""), (204, b""),
        ]) as request:
            self.assertTrue(bootstrap.refresh_library(TOKEN))
        self.assertEqual(request.call_count, 4)
        self.assertEqual(self.now, 7)
        self.assertIn("HTTP 500", self.output.getvalue())

    def test_refresh_does_not_retry_unauthorized(self):
        with patch.object(bootstrap, "request", return_value=(401, b"")) as request:
            self.assertFalse(bootstrap.refresh_library(TOKEN))
        self.assertEqual(request.call_count, 1)
        self.assertEqual(self.now, 0)

    def test_movie_wait_starts_idle_task_after_silent_refresh_failure(self):
        started = False
        starts = 0

        def request(method, path, **kwargs):
            nonlocal started, starts
            if path == "/Library/Refresh":
                return 204, b""
            if path == "/Items":
                kind = kwargs["query"]["IncludeItemTypes"]
                count = {"Movie": 6, "Series": 1, "Season": 2, "Episode": 4}[kind] if started else 0
                return response({"TotalRecordCount": count, "Items": [
                    {"RunTimeTicks": 60_000_000, "MediaStreams": [{"Type": "Video", "Codec": "h264"}]}
                ] * count})
            if path == "/ScheduledTasks":
                return response([{**SCAN, "State": "Running" if self.now < 45 else "Idle"}])
            self.assertEqual((method, path), ("POST", "/ScheduledTasks/Running/scan-id"))
            started = True
            starts += 1
            return 204, b""

        with patch.object(bootstrap, "request", side_effect=request):
            bootstrap.wait_for_scan(TOKEN)
        self.assertEqual(starts, 1)
        self.assertEqual(self.now, 48)
        self.assertIn("scan complete", self.output.getvalue())

    def test_movie_timeout_reports_status_paths_and_states_without_secrets(self):
        def request(method, path, **kwargs):
            if path == "/Library/Refresh":
                return 204, b""
            if path == "/Items":
                return 503, f"{bootstrap.PASSWORD} {TOKEN}".encode()
            if path == "/Library/VirtualFolders":
                return response([{**MOVIES, "Name": bootstrap.PASSWORD, "AccessToken": TOKEN}])
            self.assertEqual(path, "/ScheduledTasks")
            return response([{**SCAN, "State": "Running", "AccessToken": TOKEN}])

        with patch.object(bootstrap, "request", side_effect=request):
            with self.assertRaises(SystemExit) as error:
                bootstrap.wait_for_scan(TOKEN)
        self.assertEqual(error.exception.code, 1)
        self.assertEqual(self.now, 240)
        output = self.output.getvalue()
        for expected in ["GET /Items HTTP 503", "/media/Movies", "RefreshLibrary", "Running", "[redacted]"]:
            self.assertIn(expected, output)
        for secret in [bootstrap.PASSWORD, TOKEN, "AccessToken"]:
            self.assertNotIn(secret, output)

    def test_missing_library_path_fails_after_repair_is_verified(self):
        with patch.object(bootstrap, "request", side_effect=[
            response([{"Name": "Movies", "Locations": []}]),
            (204, b""), response([{"Name": "Movies", "Locations": []}]),
            response([{"Name": "Movies", "Locations": []}]), response([SCAN]),
        ]):
            with self.assertRaises(SystemExit) as error:
                bootstrap.add_library(TOKEN, "Movies", "movies")
        self.assertEqual(error.exception.code, 1)
        self.assertIn("Movies library does not contain /media", self.output.getvalue())


class PoCBootstrapTests(unittest.TestCase):
    def test_TPOC_02_resume_threshold_and_quick_connect_preserve_configuration(self):
        config = {"MinResumeDurationSeconds": 300, "MinResumePct": 5, "MaxResumePct": 90,
                  "QuickConnectAvailable": False, "OtherSetting": "keep"}
        with patch.object(bootstrap, "request", side_effect=[(200, json.dumps(config).encode()), (204, b"")]) as api:
            bootstrap.configure_server("test-token")
        posted = api.call_args_list[1].args[2]
        self.assertEqual(posted, dict(config, MinResumeDurationSeconds=0, QuickConnectAvailable=True))

    def test_TPOC_02_library_paths_and_offline_metadata(self):
        with patch.object(bootstrap, "MEDIA_DIR", "/native/fixtures"), patch.object(
                bootstrap, "request", side_effect=[(200, b"[]"), (204, b""),
                    (200, b'[ {"Name":"Shows","Locations":["/native/fixtures/Shows"]} ]')]) as api:
            bootstrap.add_library("test-token", "Shows", "tvshows")
        options = api.call_args_list[1].kwargs["body"]["LibraryOptions"]
        self.assertEqual(options["PathInfos"], [{"Path": "/native/fixtures/Shows"}])
        self.assertFalse(options["EnableInternetProviders"])
        self.assertTrue(all(not row["MetadataFetchers"] for row in options["TypeOptions"]))
        self.assertEqual(api.call_args_list[1].kwargs["query"]["collectionType"], "tvshows")

    def test_TPOC_02_non_admin_random_password_is_private(self):
        with tempfile.TemporaryDirectory() as directory:
            destination = Path(directory) / "credentials.json"
            output = io.StringIO()
            with patch.dict(os.environ, {"GLASSFIN_TEST_CREDENTIALS_FILE": str(destination)}, clear=True), patch.object(
                    bootstrap, "request", side_effect=[(200, b'{"Id":"viewer","Policy":{"IsAdministrator":true}}'),
                                                       (204, b"")]) as api, contextlib.redirect_stdout(output):
                bootstrap.create_test_user("test-token")
            credentials = json.loads(destination.read_text())
            self.assertGreaterEqual(len(credentials["password"]), 48)
            self.assertEqual(destination.stat().st_mode & 0o777, 0o600)
            self.assertNotIn(credentials["password"], output.getvalue())
            self.assertNotIn("test-token", output.getvalue())
            self.assertFalse(api.call_args_list[1].args[2]["IsAdministrator"])
            self.assertEqual(api.call_args_list[0].args[2]["Password"], credentials["password"])

    def test_TPOC_02_scan_waits_for_probing_episodes_and_idle_task(self):
        rounds = [0]

        def request(method, path, body=None, token=None, query=None):
            if path == "/Library/Refresh":
                return 204, b""
            if path == "/ScheduledTasks":
                state = "Running" if rounds[0] < 2 else "Idle"
                rounds[0] += 1
                return 200, json.dumps([{"Key": "RefreshLibrary", "State": state}]).encode()
            kind = query["IncludeItemTypes"]
            count = {"Movie": 6, "Series": 1, "Season": 2, "Episode": 4}[kind]
            runtime = 0 if rounds[0] == 0 else 60_000_000
            items = [{"RunTimeTicks": runtime, "MediaStreams": [{"Type": "Video", "Codec": "h264"}]}] * count
            return 200, json.dumps({"TotalRecordCount": count, "Items": items}).encode()

        with patch.dict(os.environ, {}, clear=True), patch.object(bootstrap, "request", side_effect=request), patch.object(
                bootstrap.time, "sleep") as sleep, contextlib.redirect_stdout(io.StringIO()):
            bootstrap.wait_for_scan("test-token")
        self.assertEqual(rounds[0], 3)
        self.assertEqual(sleep.call_count, 2)

    def test_TPOC_02_scan_requires_both_seasons_and_all_four_episodes(self):
        rounds = [0]

        def request(method, path, body=None, token=None, query=None):
            if path == "/Library/Refresh":
                return 204, b""
            if path == "/ScheduledTasks":
                rounds[0] += 1
                return 200, b'[{"Key":"RefreshLibrary","State":"Idle"}]'
            kind = query["IncludeItemTypes"]
            count = {"Movie": 6, "Series": 1, "Season": 1 if rounds[0] == 0 else 2,
                     "Episode": 3 if rounds[0] == 0 else 4}[kind]
            items = [{"RunTimeTicks": 600_000_000, "MediaStreams": [{"Type": "Video", "Codec": "h264"}]}] * count
            return 200, json.dumps({"TotalRecordCount": count, "Items": items}).encode()

        with patch.dict(os.environ, {}, clear=True), patch.object(bootstrap, "request", side_effect=request), patch.object(
                bootstrap.time, "sleep") as sleep, contextlib.redirect_stdout(io.StringIO()):
            bootstrap.wait_for_scan("test-token")
        self.assertEqual(rounds[0], 2)
        self.assertEqual(sleep.call_count, 1)

    def test_TPOC_02_configuration_failures_are_not_ignored(self):
        with patch.object(bootstrap, "request", return_value=(403, b"")), contextlib.redirect_stderr(io.StringIO()):
            with self.assertRaises(SystemExit):
                bootstrap.configure_server("test-token")


if __name__ == "__main__":
    unittest.main()
