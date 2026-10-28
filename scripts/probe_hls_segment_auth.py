#!/usr/bin/env python3
"""Probe F3 HLS authentication as the seeded viewer (Python 3.11, stdlib only).

Requires GLASSFIN_SERVER_URL, GLASSFIN_TEST_USERNAME, GLASSFIN_TEST_PASSWORD.
HTTP outcomes are report-only by default; setup/playlist/transport failures fail.
Examples of regression checks (repeatable):
  --assert stripped:segment_noheader=401 --assert kept:segment_noheader=200
  --expect-segment-auth kept  # require unauthenticated segment/map GETs to return 200
Each mode negotiates a separate play session and stops it in a finally block.
"""

from __future__ import annotations

import argparse
import http.client
import json
import os
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid


LEGACY_KEY = "api" + "_key"
CREDENTIAL_NAMES = {"apikey", LEGACY_KEY, "token", "accesstoken", "pw", "secret"}
MODES = ("stripped", "kept")
SUMMARY_FIELDS = (
    "master", "variant", "segment_has_credential", "map_has_credential",
    "segment_noheader", "segment_header", "map_noheader", "map_header",
)


class ProbeError(Exception):
    """A controlled diagnostic containing no response bodies, headers, or URLs."""


def redact(text: str, secrets: tuple[str, ...] = ()) -> str:
    names = "(?:" + "|".join(sorted(CREDENTIAL_NAMES, key=len, reverse=True)) + ")"
    text = re.sub(r'(\bToken\s*=\s*")[^"]*"', r'\1REDACTED"', text, flags=re.I)
    text = re.sub(rf'((?:^|[?&\s]){names}=)(?![\"\'])[^&#\s\"\']*', r"\1REDACTED", text, flags=re.I)
    for secret in secrets:
        if secret:
            for value in (secret, urllib.parse.quote(secret, safe=""), urllib.parse.quote_plus(secret)):
                text = text.replace(value, "REDACTED")
    return text


def credential_name(name: str) -> bool:
    return urllib.parse.unquote_plus(name).lower() in CREDENTIAL_NAMES


def has_credential(url: str) -> bool:
    return any(credential_name(part.partition("=")[0])
               for part in urllib.parse.urlsplit(url).query.split("&"))


def strip_credentials(url: str) -> str:
    """Match MediaCredentialQuery without re-encoding unrelated query values."""
    parts = urllib.parse.urlsplit(url)
    query = "&".join(part for part in parts.query.split("&")
                     if part and not credential_name(part.partition("=")[0]))
    return urllib.parse.urlunsplit(parts._replace(netloc=parts.netloc.rsplit("@", 1)[-1], query=query))


def path_shape(url: str) -> str:
    """Log only a path shape: omit origin, query, fragment, and generated IDs."""
    path = urllib.parse.urlsplit(url).path
    path = re.sub(r"[a-fA-F0-9-]{16,}", "{id}", path)
    return re.sub(r"(?<![A-Za-z0-9])\d+", "{n}", path)


def parse_playlist(text: str) -> dict[str, list[str]]:
    """Collect variants, media segments, and initialization maps in source order."""
    result: dict[str, list[str]] = {"variants": [], "segments": [], "maps": []}
    lines = text.lstrip("\ufeff").splitlines()
    if not lines or lines[0].strip() != "#EXTM3U":
        raise ProbeError("invalid HLS playlist")
    next_variant = False
    for line in lines[1:]:
        line = line.strip()
        if line.startswith("#EXT-X-STREAM-INF:"):
            next_variant = True
        elif line.startswith("#EXT-X-MAP:"):
            uri = re.search(r'(?:^|,)\s*URI="([^\"]*)"', line.partition(":")[2])
            if uri:
                result["maps"].append(uri.group(1))
        elif line and not line.startswith("#"):
            # The app also identifies playlist URIs by their path extension.
            kind = "variants" if next_variant or ".m3u8" in line.split("?", 1)[0].lower() else "segments"
            result[kind].append(line)
            next_variant = False
    return result


def summary_value(item) -> str:
    if item is None:
        return "na"
    if isinstance(item, bool):
        return str(item).lower()
    return str(item)


def summary_line(mode: str, fields: dict) -> str:
    return "probe-hls: mode=" + mode + "".join(
        f" {name}={summary_value(fields.get(name))}" for name in SUMMARY_FIELDS)


def playback_info_body(user_id: str) -> dict:
    # Keep in sync with PlaybackAPI.PlaybackInfoBody and PlaybackDeviceProfile.
    return {
        "UserId": user_id, "StartTimeTicks": 0, "MaxStreamingBitrate": 120_000_000,
        "EnableDirectPlay": False, "EnableDirectStream": True, "EnableTranscoding": True,
        "AllowVideoStreamCopy": True, "AllowAudioStreamCopy": True, "SubtitleStreamIndex": -1,
        "DeviceProfile": {
            "Name": "Glassfin M08a-PoC",
            "DirectPlayProfiles": [{
                "Container": "mp4,mov,m4v,hls", "Type": "Video",
                "VideoCodec": "h264,hevc", "AudioCodec": "aac,ac3,eac3",
            }],
            "TranscodingProfiles": [{
                "Container": "mp4", "Protocol": "hls", "Type": "Video",
                "VideoCodec": "h264,hevc", "AudioCodec": "aac,eac3", "Context": "Streaming",
                "EnableSubtitlesInManifest": False, "BreakOnNonKeyFrames": True,
            }],
            "SubtitleProfiles": [],
        },
    }


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


class Client:
    def __init__(self, base: str, password: str):
        self.base = base.rstrip("/")
        self.password = password
        self.token = ""
        self.device_id = "glassfin-hls-probe-" + uuid.uuid4().hex
        self.opener = urllib.request.build_opener(NoRedirect())
        self.resolve(self.base, "")
        if urllib.parse.urlsplit(self.base).query or urllib.parse.urlsplit(self.base).fragment:
            raise ProbeError("server URL must have no query or fragment")

    def detail(self, message: str) -> None:
        print("probe-hls-detail: " + redact(message, (self.password, self.token)), file=sys.stderr, flush=True)

    def authorization(self) -> str:
        header = ('MediaBrowser Client="Glassfin", Device="HLS probe", '
                  f'DeviceId="{self.device_id}", Version="0.1.0"')
        return header + (f', Token="{self.token}"' if self.token else "")

    def resolve(self, base: str, uri: str) -> str:
        url = urllib.parse.urljoin(base, uri)
        origin, target = urllib.parse.urlsplit(self.base), urllib.parse.urlsplit(url)
        def authority(parts):
            return parts.scheme.lower(), parts.hostname, parts.port or (443 if parts.scheme == "https" else 80)
        if (target.scheme not in ("http", "https") or target.username is not None
                or authority(origin) != authority(target)):
            raise ProbeError("refused media URL outside the server origin or containing user info")
        return url

    def api_url(self, path: str, query: dict | None = None) -> str:
        url = self.base + path
        return url + ("?" + urllib.parse.urlencode(query) if query else "")

    def request(self, method: str, url: str, *, body: dict | None = None,
                authorized: bool = True, read_body: bool = True, timeout: float = 15) -> tuple[int, bytes]:
        self.resolve(url, "")
        headers = {"Authorization": self.authorization()} if authorized else {}
        data = None if body is None else json.dumps(body).encode()
        if data is not None:
            headers["Content-Type"] = "application/json"
        req = urllib.request.Request(url, data=data, headers=headers, method=method)
        try:
            with self.opener.open(req, timeout=timeout) as response:
                return response.status, response.read() if read_body else response.read(1)
        except urllib.error.HTTPError as error:
            # Status is the evidence. Error bodies can contain credentials or raw server logs.
            with error:
                return error.code, b""
        except (urllib.error.URLError, TimeoutError, OSError, http.client.HTTPException):
            return 0, b""

    def json(self, method: str, path: str, *, body: dict | None = None, query: dict | None = None) -> dict:
        status, raw = self.request(method, self.api_url(path, query), body=body)
        if status != 200:
            raise ProbeError(f"{method} {path} HTTP {status}")
        try:
            value = json.loads(raw)
        except (ValueError, UnicodeDecodeError):
            raise ProbeError("invalid API JSON") from None
        if not isinstance(value, dict):
            raise ProbeError("expected API JSON object")
        return value

    def get(self, url: str, *, authorized: bool, read_body: bool = False) -> tuple[int, bytes]:
        deadline = time.monotonic() + 60
        while True:
            remaining = deadline - time.monotonic()
            status, raw = self.request("GET", url, authorized=authorized, read_body=read_body,
                                       timeout=max(0.1, min(15, remaining)))
            if status not in (0, 404) and not 500 <= status <= 599:
                return status, raw
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                return status, raw
            time.sleep(min(2, remaining))


def find_fixture(client: Client, user_id: str) -> str:
    items = client.json("GET", "/Items", query={
        "UserId": user_id, "Recursive": "true", "IncludeItemTypes": "Movie", "Fields": "Path", "Limit": "1000",
    }).get("Items", [])
    # Prefer the path: metadata providers can rename a synthetic movie.
    matches = [item for item in items if (item.get("Path") or "").endswith("/Glassfin Remux (2024).mkv")]
    if not matches:
        matches = [item for item in items if item.get("Name") in ("Glassfin Remux", "Glassfin Remux (2024)")]
    if len(matches) != 1 or not matches[0].get("Id"):
        raise ProbeError("expected exactly one F3 Glassfin Remux movie in the viewer's items")
    return matches[0]["Id"]


def probe_mode(client: Client, item_id: str, user_id: str, mode: str, fields: dict) -> None:
    info = client.json("POST", f"/Items/{urllib.parse.quote(item_id, safe='')}/PlaybackInfo",
                       body=playback_info_body(user_id))
    session = info.get("PlaySessionId")
    try:
        sources = info.get("MediaSources") or []
        transcoding = sources[0].get("TranscodingUrl") if sources else None
        if not session or not transcoding:
            raise ProbeError("PlaybackInfo did not return a play session and MediaSources[0].TranscodingUrl")
        master = client.resolve(client.base + "/", transcoding)
        if mode == "stripped":
            master = strip_credentials(master)
        fields["master"], raw = client.get(master, authorized=True, read_body=True)
        if fields["master"] != 200:
            raise ProbeError(f"mode={mode} master HTTP {fields['master']}")
        playlist = parse_playlist(raw.decode("utf-8-sig"))
        if not playlist["variants"]:
            raise ProbeError(f"mode={mode} master has no variant URI")
        variant = client.resolve(master, playlist["variants"][0])
        if mode == "stripped":
            variant = strip_credentials(variant)
        fields["variant"], raw = client.get(variant, authorized=True, read_body=True)
        if fields["variant"] != 200:
            raise ProbeError(f"mode={mode} variant HTTP {fields['variant']}")
        playlist = parse_playlist(raw.decode("utf-8-sig"))
        segments = [client.resolve(variant, uri) for uri in playlist["segments"]]
        maps = [client.resolve(variant, uri) for uri in playlist["maps"]]
        if not segments:
            raise ProbeError(f"mode={mode} variant has no media segments")
        fields["segment_has_credential"] = any(map(has_credential, segments))
        fields["map_has_credential"] = any(map(has_credential, maps)) if maps else None
        targets = {"segment": segments[0]}
        if maps:
            targets["map"] = maps[0]
        for kind, url in targets.items():
            client.detail(f"mode={mode} {kind}_path={path_shape(url)}")
            fields[kind + "_noheader"], _ = client.get(url, authorized=False)
        for kind, url in targets.items():
            # Header-only control: remove query credentials even in kept mode.
            fields[kind + "_header"], _ = client.get(strip_credentials(url), authorized=True)
        if any(fields[kind + suffix] == 0 for kind in targets for suffix in ("_noheader", "_header")):
            raise ProbeError(f"mode={mode} segment transport failure (status 0)")
    finally:
        # Even a playlist/authentication failure may have started ffmpeg.
        status, _ = client.request("DELETE", client.api_url("/Videos/ActiveEncodings", {
            "DeviceId": client.device_id, **({"PlaySessionId": session} if session else {}),
        }), read_body=False)
        if not 200 <= status < 300:
            client.detail(f"mode={mode} stop_transcode HTTP {status} (best effort)")


def assertion(value: str) -> tuple[str, str, str]:
    match = re.fullmatch(r"(stripped|kept):([a-z_]+)=(true|false|na|[0-9]{1,3})", value)
    if not match or match[2] not in SUMMARY_FIELDS:
        raise argparse.ArgumentTypeError("expected MODE:FIELD=VALUE using a probe summary field")
    return match[1], match[2], match[3]


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--assert", dest="assertions", type=assertion, action="append", default=[],
                        metavar="MODE:FIELD=VALUE", help="require an exact summary value (repeatable)")
    parser.add_argument("--expect-segment-auth", choices=MODES, action="append", default=[],
                        metavar="MODE", help="require segment and any map without headers to return 200")
    args = parser.parse_args(argv)
    values = [os.environ.get(key, "") for key in (
        "GLASSFIN_SERVER_URL", "GLASSFIN_TEST_USERNAME", "GLASSFIN_TEST_PASSWORD")]
    if not all(values):
        print("probe-hls: required server URL or test-user credentials are unset", file=sys.stderr)
        return 2
    client = None
    try:
        client = Client(values[0], values[2])
        auth = client.json("POST", "/Users/AuthenticateByName", body={"Username": values[1], "Pw": values[2]})
        client.token = auth.get("AccessToken") or ""
        user = auth.get("User") or {}
        if not client.token or not user.get("Id"):
            raise ProbeError("authentication returned no access token or user ID")
        if (user.get("Policy") or {}).get("IsAdministrator"):
            raise ProbeError("the probe requires the seeded non-admin viewer")
        item_id = find_fixture(client, user["Id"])
        failed = False
        results = {}
        for mode in MODES:
            fields: dict = {}
            try:
                probe_mode(client, item_id, user["Id"], mode, fields)
            except (ProbeError, ValueError) as error:
                client.detail(str(error) if isinstance(error, ProbeError) else f"mode={mode} invalid playlist or URL")
                failed = True
            print(summary_line(mode, fields), flush=True)
            results[mode] = fields
        checks = list(args.assertions)
        for mode in args.expect_segment_auth:
            checks.append((mode, "segment_noheader", "200"))
            if results[mode].get("map_noheader") is not None:
                checks.append((mode, "map_noheader", "200"))
        for mode, field, expected in checks:
            actual = summary_value(results[mode].get(field))
            if actual != expected:
                client.detail(f"assertion_failed mode={mode} field={field} expected={expected} actual={actual}")
                failed = True
        return int(failed)
    except (ProbeError, ValueError, OSError) as error:
        # Exception messages and server bodies can contain full URLs or secrets.
        if client:
            client.detail(str(error) if isinstance(error, ProbeError) else "invalid server URL or transport failure")
        else:
            print("probe-hls: invalid server URL", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
