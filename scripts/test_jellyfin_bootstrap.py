"""Exercise bootstrap recovery without Docker or a live Jellyfin server."""

import contextlib
import importlib.util
import io
import json
import os
from pathlib import Path
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
MOVIES = {"Name": "Movies", "Locations": ["/media"]}
SCAN = {"Id": "scan-id", "Key": "RefreshLibrary", "State": "Idle"}


def response(value, status=200):
    return status, json.dumps(value).encode()


class BootstrapTests(unittest.TestCase):
    def setUp(self):
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
            bootstrap.add_library(TOKEN)
        self.assertEqual(request.call_count, 3)
        query = request.call_args_list[1].kwargs["query"]
        self.assertEqual(query["paths"], "/media")
        self.assertEqual(query["refreshLibrary"], "false")

    def test_ignored_query_path_is_repaired_without_duplicate_library(self):
        empty = {"Name": "Movies", "Locations": []}
        with patch.object(bootstrap, "request", side_effect=[
            response([]), (204, b""), response([empty]), (204, b""), response([MOVIES]),
        ]) as request:
            bootstrap.add_library(TOKEN)
        posts = [call for call in request.call_args_list if call.args[0] == "POST"]
        self.assertEqual([call.args[1] for call in posts], [
            "/Library/VirtualFolders", "/Library/VirtualFolders/Paths"])
        self.assertEqual(posts[1].kwargs["body"]["PathInfo"], {"Path": "/media"})
        self.assertEqual(posts[1].kwargs["query"]["refreshLibrary"], "false")

    def test_failed_query_creation_falls_back_to_path_infos_body(self):
        with patch.object(bootstrap, "request", side_effect=[
            response([]), (400, b""), response([]), (204, b""), response([MOVIES]),
        ]) as request:
            bootstrap.add_library(TOKEN)
        fallback = request.call_args_list[3]
        self.assertEqual(fallback.kwargs["body"], {"LibraryOptions": {"PathInfos": [{"Path": "/media"}]}})
        self.assertNotIn("paths", fallback.kwargs["query"])
        self.assertEqual(fallback.kwargs["query"]["refreshLibrary"], "false")

    def test_partial_creation_on_server_error_is_not_repeated(self):
        with patch.object(bootstrap, "request", side_effect=[
            response([]), (500, b""), response([MOVIES]),
        ]) as request:
            bootstrap.add_library(TOKEN)
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
                return response({"TotalRecordCount": int(started)})
            if path == "/ScheduledTasks":
                return response([{**SCAN, "State": "Running" if self.now < 45 else "Idle"}])
            self.assertEqual((method, path), ("POST", "/ScheduledTasks/Running/scan-id"))
            started = True
            starts += 1
            return 204, b""

        with patch.object(bootstrap, "request", side_effect=request):
            bootstrap.wait_for_movie(TOKEN)
        self.assertEqual(starts, 1)
        self.assertEqual(self.now, 48)
        self.assertIn("movie is in the library", self.output.getvalue())

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
                bootstrap.wait_for_movie(TOKEN)
        self.assertEqual(error.exception.code, 1)
        self.assertEqual(self.now, 240)
        output = self.output.getvalue()
        for expected in ["GET /Items HTTP 503", "/media", "RefreshLibrary", "Running", "[redacted]"]:
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
                bootstrap.add_library(TOKEN)
        self.assertEqual(error.exception.code, 1)
        self.assertIn("Movies library does not contain /media", self.output.getvalue())


if __name__ == "__main__":
    unittest.main()
