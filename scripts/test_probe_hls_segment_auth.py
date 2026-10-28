"""Exercise the HLS probe without network access or Docker."""

import contextlib
import http.client
import io
import json
import os
import unittest
import urllib.error
from unittest.mock import Mock, patch

from scripts import probe_hls_segment_auth as probe


BASE = "http://localhost:8096"
TOKEN = "test-access-token"
PASSWORD = "test-password"
MASTER = '#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=100000\nmain.m3u8?ApiKey=' + TOKEN + '&x=%2F\n'
VARIANT = ('#EXTM3U\n#EXT-X-MAP:URI="init.mp4?ApiKey=' + TOKEN + '"\n'
           '#EXTINF:6,\n0.mp4?ApiKey=' + TOKEN + '\n')


class HelpersTests(unittest.TestCase):
    def test_redaction_masks_every_credential_name_in_any_case(self):
        for name in ("ApiKey", "APIKEY", "aPiKeY", probe.LEGACY_KEY, probe.LEGACY_KEY.upper(),
                     "Token", "ACCESSTOKEN", "Pw", "sEcReT"):
            with self.subTest(name=name):
                text = f"https://example.test/v?{name}=hidden%20value&keep=1#fragment"
                self.assertEqual(probe.redact(text), f"https://example.test/v?{name}=REDACTED&keep=1#fragment")
        self.assertEqual(probe.redact("ApiKey=hidden"), "ApiKey=REDACTED")

    def test_redaction_masks_quoted_header_token_and_known_secrets(self):
        for spelling in ('Token="hidden"', 'TOKEN = "hidden"', 'token="hidden"'):
            with self.subTest(spelling=spelling):
                output = probe.redact('MediaBrowser Client="Glassfin", ' + spelling)
                self.assertNotIn("hidden", output)
                self.assertIn('"REDACTED"', output)
        self.assertEqual(probe.redact('Token="hidden"'), 'Token="REDACTED"')
        self.assertEqual(probe.redact("pass word pass%20word pass+word", ("pass word",)),
                         "REDACTED REDACTED REDACTED")

    def test_strip_removes_all_names_and_preserves_other_query_bytes(self):
        names = ["ApiKey", "aPiKeY", probe.LEGACY_KEY.upper(), "TOKEN", "secret", "pw", "accesstoken", "%41piKey"]
        url = "https://user:password@example.test/v?x=%2f+%20&" + "&".join(name + "=hidden" for name in names)
        url += "&empty=&flag&x=2#part"
        self.assertTrue(probe.has_credential(url))
        self.assertEqual(probe.strip_credentials(url), "https://example.test/v?x=%2f+%20&empty=&flag&x=2#part")
        self.assertFalse(probe.has_credential(probe.strip_credentials(url)))
        self.assertEqual(probe.strip_credentials("https://example.test/v?ApiKey=hidden"), "https://example.test/v")
        self.assertEqual(probe.strip_credentials("https://example.test/v?keep=1"), "https://example.test/v?keep=1")

    def test_parse_master_uses_stream_inf_and_preserves_uri_query(self):
        text = ('\ufeff#EXTM3U\r\n#EXT-X-MEDIA:TYPE=AUDIO,URI="audio.m3u8"\r\n'
                '#EXT-X-STREAM-INF:BANDWIDTH=100\r\n#comment\r\n  variant?x=1  \r\n'
                '#EXT-X-STREAM-INF:BANDWIDTH=200\r\nsecond.m3u8?ApiKey=hidden\r\n')
        self.assertEqual(probe.parse_playlist(text), {
            "variants": ["variant?x=1", "second.m3u8?ApiKey=hidden"], "segments": [], "maps": [],
        })

    def test_parse_media_segments_and_map_attributes(self):
        text = ('#EXTM3U\n#EXT-X-MAP:BYTERANGE="100@0",URI="../init.mp4?x=1,2"\n'
                '#EXTINF:6,\nfirst.mp4?x=1\n\n#EXTINF:6,\nhttps://example.test/second.mp4\n'
                '#EXT-X-MAP:URI="next-init.mp4",BYTERANGE="100@0"\n#EXT-X-ENDLIST\n')
        self.assertEqual(probe.parse_playlist(text), {
            "variants": [], "segments": ["first.mp4?x=1", "https://example.test/second.mp4"],
            "maps": ["../init.mp4?x=1,2", "next-init.mp4"],
        })
        with self.assertRaises(probe.ProbeError):
            probe.parse_playlist("<html>not a playlist</html>")

    def test_summary_is_stable_machine_readable_and_has_no_uris(self):
        self.assertEqual(probe.summary_line("stripped", {
            "master": 200, "variant": 200, "segment_has_credential": False, "map_has_credential": True,
            "segment_noheader": 401, "segment_header": 200, "map_noheader": 200,
        }), "probe-hls: mode=stripped master=200 variant=200 segment_has_credential=false "
            "map_has_credential=true segment_noheader=401 segment_header=200 map_noheader=200 map_header=na")
        self.assertEqual(probe.path_shape(BASE + "/videos/" + "a" * 32 + "/hls1/main/0.mp4?ApiKey=hidden"),
                         "/videos/{id}/hls1/main/{n}.mp4")


class ProbeTests(unittest.TestCase):
    def setUp(self):
        self.output = io.StringIO()
        self.enterContext(contextlib.redirect_stderr(self.output))
        self.enterContext(contextlib.redirect_stdout(self.output))
        self.client = probe.Client(BASE, PASSWORD)
        self.client.token = TOKEN
        # Block all network unless a test explicitly supplies a mock transport.
        self.open = self.enterContext(patch.object(self.client.opener, "open", side_effect=AssertionError("network forbidden")))

    def test_get_without_authorization_has_no_token_or_cookie(self):
        response = Mock(status=200)
        response.__enter__ = Mock(return_value=response)
        response.__exit__ = Mock(return_value=False)
        self.open.side_effect = None
        self.open.return_value = response
        self.client.request("GET", BASE + "/0.mp4", authorized=False)
        request = self.open.call_args.args[0]
        self.assertEqual(request.header_items(), [])
        self.assertIsNone(request.data)
        self.client.request("GET", BASE + "/main.m3u8")
        header = self.open.call_args.args[0].get_header("Authorization")
        self.assertTrue(header.startswith('MediaBrowser Client="Glassfin", Device="HLS probe", DeviceId="'))
        self.assertIn(f'Token="{TOKEN}"', header)

    def test_cross_origin_userinfo_and_redirects_are_refused(self):
        for uri in ("https://other.test/main.m3u8", "http://user:pw@localhost:8096/a", "file:///tmp/a"):
            with self.subTest(uri=uri), self.assertRaises(probe.ProbeError):
                self.client.resolve(BASE, uri)
        self.assertEqual(self.client.resolve(BASE + "/a/master.m3u8?ApiKey=hidden", "../main.m3u8"),
                         BASE + "/main.m3u8")
        self.assertIsNone(probe.NoRedirect().redirect_request(None, None, 302, "", {}, BASE + "/next"))

    def test_request_discards_error_bodies_and_transport_exception_messages(self):
        url = BASE + "/0.mp4?ApiKey=" + TOKEN
        self.open.side_effect = urllib.error.HTTPError(url, 401, TOKEN, {}, io.BytesIO(TOKEN.encode()))
        self.assertEqual(self.client.request("GET", url, authorized=False), (401, b""))
        self.open.side_effect = urllib.error.URLError(url)
        self.assertEqual(self.client.request("GET", url, authorized=False), (0, b""))
        self.open.side_effect = http.client.BadStatusLine(TOKEN)
        self.assertEqual(self.client.request("GET", url, authorized=False), (0, b""))
        self.assertNotIn(TOKEN, self.output.getvalue())

    def test_retry_transient_statuses_until_ready_but_not_unauthorized(self):
        now = 0

        def sleep(seconds):
            nonlocal now
            now += seconds

        with patch.object(probe.time, "monotonic", side_effect=lambda: now), \
                patch.object(probe.time, "sleep", side_effect=sleep), \
                patch.object(self.client, "request", side_effect=[(404, b""), (503, b""), (200, b"ok")]) as request:
            self.assertEqual(self.client.get(BASE + "/0.mp4", authorized=False), (200, b"ok"))
            self.assertEqual(request.call_count, 3)
            self.assertEqual(now, 4)
        with patch.object(self.client, "request", return_value=(401, b"")) as request:
            self.assertEqual(self.client.get(BASE + "/0.mp4", authorized=False)[0], 401)
            self.assertEqual(request.call_count, 1)
        now = 0
        with patch.object(probe.time, "monotonic", side_effect=lambda: now), \
                patch.object(probe.time, "sleep", side_effect=sleep), \
                patch.object(self.client, "request", return_value=(500, b"")):
            self.assertEqual(self.client.get(BASE + "/0.mp4", authorized=False)[0], 500)
            self.assertEqual(now, 60)

    def test_all_modes_reproduce_playlist_credentials_and_header_only_control(self):
        for mode in probe.MODES:
            calls = []

            def get(url, *, authorized, read_body=False):
                calls.append((url, authorized))
                if "master.m3u8" in url:
                    return 200, MASTER.encode()
                if "main.m3u8" in url:
                    return 200, VARIANT.encode()
                return (200 if authorized or probe.has_credential(url) else 401), b""

            fields = {}
            with patch.object(self.client, "json", return_value={
                "PlaySessionId": "session", "MediaSources": [{"TranscodingUrl": "/videos/master.m3u8?ApiKey=" + TOKEN}],
            }) as info, patch.object(self.client, "get", side_effect=get), \
                    patch.object(self.client, "request", return_value=(204, b"")) as stop:
                probe.probe_mode(self.client, "item", "viewer", mode, fields)
            self.assertEqual(info.call_args.kwargs["body"], probe.playback_info_body("viewer"))
            self.assertFalse(info.call_args.kwargs["body"]["EnableDirectPlay"])
            for url, authorized in calls[:2]:
                self.assertEqual(authorized, mode != "loader")
                self.assertEqual(probe.has_credential(url), mode != "stripped")
            # Server-written segment/map URLs stay untouched, including in stripped mode.
            self.assertTrue(fields["segment_has_credential"])
            self.assertTrue(fields["map_has_credential"])
            self.assertEqual(fields["segment_noheader"], 200)
            self.assertEqual(fields["map_noheader"], 200)
            self.assertTrue(all(not authorized for _, authorized in calls[2:4]))
            self.assertTrue(all(authorized and not probe.has_credential(url) for url, authorized in calls[4:]))
            self.assertEqual(stop.call_args.args[0], "DELETE")
            self.assertIn("DeviceId=" + self.client.device_id, stop.call_args.args[1])
            self.assertIn("PlaySessionId=session", stop.call_args.args[1])
        self.assertNotIn(TOKEN, self.output.getvalue())
        self.assertNotIn(PASSWORD, self.output.getvalue())
        self.assertNotIn("http://", self.output.getvalue())

    def test_loader_restores_raw_query_when_server_variant_omits_it(self):
        for name in ("ApiKey", probe.LEGACY_KEY.upper()):
            calls = []
            credential = name + "=server%2bcanary%2F%3d"

            def get(url, *, authorized, read_body=False):
                calls.append((url, authorized))
                if "master.m3u8" in url:
                    return 200, b"#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=1\nmain.m3u8?x=%2f\n"
                if "main.m3u8" in url:
                    return 200, VARIANT.encode()
                return 200, b"media"

            with patch.object(self.client, "json", return_value={
                "PlaySessionId": "session", "MediaSources": [{"TranscodingUrl": "/master.m3u8?" + credential}],
            }), patch.object(self.client, "get", side_effect=get), \
                    patch.object(self.client, "request", return_value=(204, b"")):
                probe.probe_mode(self.client, "item", "viewer", "loader", {})
            self.assertTrue(calls[0][0].endswith("?" + credential))
            self.assertTrue(calls[1][0].endswith("?x=%2f&" + credential))
            self.assertTrue(all(not authorized for _, authorized in calls[:4]))
            self.assertNotIn("canary", self.output.getvalue())

    def test_server_fields_never_duplicate_or_cross_origin(self):
        for name in ("ApiKey", probe.LEGACY_KEY):
            raw = name + "=server%2bcanary"
            fields = probe.server_credential_fields(BASE + "/master.m3u8?x=1&" + raw + "&Token=ignored")
            self.assertEqual(fields, (raw,))
            duplicate = BASE + "/main.m3u8?" + name.upper() + "=existing%2f"
            self.assertEqual(probe.append_server_credentials(self.client, duplicate, fields), duplicate)
            for url in ("http://foreign.test/main.m3u8", "http://user:pw@localhost:8096/main.m3u8"):
                with self.assertRaises(probe.ProbeError):
                    probe.append_server_credentials(self.client, url, fields)

    def test_cleanup_runs_when_variant_is_unauthorized(self):
        fields = {}
        with patch.object(self.client, "json", return_value={
            "PlaySessionId": "session", "MediaSources": [{"TranscodingUrl": "/master.m3u8"}],
        }), patch.object(self.client, "get", side_effect=[(200, MASTER.encode()), (401, b"")]), \
                patch.object(self.client, "request", return_value=(403, b"")) as stop:
            with self.assertRaises(probe.ProbeError):
                probe.probe_mode(self.client, "item", "viewer", "stripped", fields)
        self.assertEqual(fields, {"master": 200, "variant": 401})
        self.assertEqual(stop.call_count, 1)
        self.assertIn("best effort", self.output.getvalue())

    def test_fixture_discovery_uses_viewer_items_and_prefers_path(self):
        with patch.object(self.client, "json", return_value={"Items": [
            {"Id": "f3", "Name": "Renamed", "Path": "/media/Movies/Glassfin Remux (2024).mkv"},
            {"Id": "other", "Name": "Glassfin Remux"},
        ]}) as items:
            self.assertEqual(probe.find_fixture(self.client, "viewer"), "f3")
        self.assertEqual(items.call_args.args, ("GET", "/Items"))
        self.assertEqual(items.call_args.kwargs["query"]["UserId"], "viewer")
        with patch.object(self.client, "json", return_value={"Items": [
            {"Id": "f3", "Name": "Glassfin Remux", "Path": None},
        ]}):
            self.assertEqual(probe.find_fixture(self.client, "viewer"), "f3")

    def test_full_probe_against_query_propagating_fake_server(self):
        sessions = []
        stopped = []

        def request(method, url, *, body=None, authorized=True, **kwargs):
            parts = probe.urllib.parse.urlsplit(url)
            if parts.path == "/Users/AuthenticateByName":
                self.assertEqual(body, {"Username": "viewer", "Pw": PASSWORD})
                return 200, json.dumps({"AccessToken": TOKEN, "User": {"Id": "viewer",
                    "Policy": {"IsAdministrator": False}}}).encode()
            self.assertEqual(self.client.token, TOKEN)
            if parts.path == "/Items":
                self.assertIn("UserId=viewer", parts.query)
                return 200, b'{"Items":[{"Id":"f3","Name":"Glassfin Remux"}]}'
            if parts.path == "/Items/f3/PlaybackInfo":
                self.assertEqual(body["UserId"], "viewer")
                self.assertFalse(body["EnableDirectPlay"])
                self.assertEqual(body["DeviceProfile"]["TranscodingProfiles"][0]["Container"], "mp4")
                sessions.append("session-" + str(len(sessions)))
                query = probe.urllib.parse.urlencode({"PlaySessionId": sessions[-1], "ApiKey": TOKEN})
                return 200, json.dumps({"PlaySessionId": sessions[-1],
                    "MediaSources": [{"TranscodingUrl": "/videos/master.m3u8?" + query}]}).encode()
            if method == "DELETE":
                stopped.append(probe.urllib.parse.parse_qs(parts.query)["PlaySessionId"][0])
                return 204, b""
            if parts.path.endswith("master.m3u8"):
                self.assertEqual(authorized, len(sessions) != 3)
                return 200, ("#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=100\nmain.m3u8?" + parts.query).encode()
            if parts.path.endswith("main.m3u8"):
                self.assertEqual(authorized, len(sessions) != 3)
                return 200, ('#EXTM3U\n#EXT-X-MAP:URI="init.mp4?' + parts.query + '"\n'
                             '#EXTINF:6,\n0.mp4?' + parts.query).encode()
            self.assertTrue(parts.path.endswith(("0.mp4", "init.mp4")))
            return (200 if authorized or probe.has_credential(url) else 401), b"segment"

        with patch.dict(os.environ, {"GLASSFIN_SERVER_URL": BASE, "GLASSFIN_TEST_USERNAME": "viewer",
                                    "GLASSFIN_TEST_PASSWORD": PASSWORD, "GLASSFIN_USERNAME": "unused-admin"}), \
                patch.object(probe, "Client", return_value=self.client), \
                patch.object(self.client, "request", side_effect=request):
            self.assertEqual(probe.main(["--assert", "stripped:segment_noheader=401",
                                        "--expect-segment-auth", "kept",
                                        "--assert", "loader:segment_noheader=200",
                                        "--assert", "loader:map_noheader=200"]), 0)
        self.assertEqual(sessions, ["session-0", "session-1", "session-2"])
        self.assertEqual(stopped, sessions)
        output = self.output.getvalue()
        summaries = [line for line in output.splitlines() if line.startswith("probe-hls:")]
        self.assertEqual(len(summaries), 3)
        self.assertIn("segment_has_credential=false map_has_credential=false segment_noheader=401 segment_header=200", summaries[0])
        self.assertIn("map_noheader=401 map_header=200", summaries[0])
        self.assertIn("segment_has_credential=true map_has_credential=true segment_noheader=200 segment_header=200", summaries[1])
        self.assertNotIn(TOKEN, output)
        self.assertNotIn(PASSWORD, output)
        self.assertNotIn(BASE, output)

    def run_main(self, args=(), fail_mode=None):
        def run(client, item, user, mode, fields):
            fields.update(master=200, variant=200, segment_noheader=401 if mode == "stripped" else 200,
                          segment_header=200, map_noheader=200 if mode != "stripped" else None)
            if mode == fail_mode:
                raise probe.ProbeError("playlist failure")

        with patch.dict(os.environ, {"GLASSFIN_SERVER_URL": BASE, "GLASSFIN_TEST_USERNAME": "viewer",
                                    "GLASSFIN_TEST_PASSWORD": PASSWORD}), \
                patch.object(probe, "Client", return_value=self.client), \
                patch.object(self.client, "json", return_value={"AccessToken": TOKEN, "User": {"Id": "viewer"}}), \
                patch.object(probe, "find_fixture", return_value="f3"), patch.object(probe, "probe_mode", side_effect=run):
            return probe.main(list(args))

    def test_main_report_only_and_assertion_exit_codes(self):
        self.assertEqual(self.run_main(), 0)  # A measured 401 is an observation, not a failure.
        self.assertEqual(self.run_main(["--assert", "stripped:segment_noheader=401"]), 0)
        self.assertEqual(self.run_main(["--assert", "stripped:segment_noheader=200"]), 1)
        self.assertEqual(self.run_main(["--expect-segment-auth", "kept"]), 0)
        self.assertEqual(self.run_main(["--assert", "loader:map_noheader=200"]), 0)
        self.assertEqual(self.run_main(["--assert", "stripped:map_noheader=200"]), 1)
        self.assertEqual(self.run_main(fail_mode="loader"), 1)
        self.assertEqual(self.run_main(["--expect-segment-auth", "stripped"]), 1)
        self.assertEqual(self.run_main(fail_mode="stripped"), 1)
        for mode in probe.MODES:
            self.assertIn(f"probe-hls: mode={mode}", self.output.getvalue())
        self.assertNotIn(TOKEN, self.output.getvalue())


if __name__ == "__main__":
    unittest.main()
