#!/usr/bin/env python3
"""Finish the Jellyfin startup wizard and wait for the seeded search library.

Credentials come from the environment. This script never prints them or the access token.
"""

from __future__ import annotations

import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request


def env(name: str) -> str:
    value = os.environ.get(name, "")
    if not value:
        print(f"bootstrap: {name} is unset", file=sys.stderr)
        raise SystemExit(2)
    return value


BASE = env("GLASSFIN_SERVER_URL").rstrip("/")
USER = env("GLASSFIN_USERNAME")
PASSWORD = env("GLASSFIN_PASSWORD")


def request(method: str, path: str, body: dict | None = None, token: str | None = None, query: dict | None = None):
    url = BASE + path
    if query:
        url += "?" + urllib.parse.urlencode(query, doseq=True)
    data = None if body is None else json.dumps(body).encode()
    # AuthenticateByName rejects a request whose Authorization header has no Client.
    authorization = 'MediaBrowser Client="Glassfin", Device="setup", DeviceId="setup-device", Version="0.1.0"'
    if token:
        authorization += f', Token="{token}"'
    headers = {"Content-Type": "application/json", "Authorization": authorization}
    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=20) as response:
            raw = response.read()
            return response.status, raw
    except urllib.error.HTTPError as error:
        return error.code, error.read()
    except (urllib.error.URLError, TimeoutError, OSError):
        return 0, b""


def public_info() -> dict:
    """Wait until /System/Info/Public answers twice.

    12.2 accepts a connection while it is still migrating, then resets it.
    Two successful reads a couple of seconds apart means the listener stayed up.
    """
    deadline = time.time() + 180
    seen = 0
    while time.time() < deadline:
        status, raw = request("GET", "/System/Info/Public")
        info = None
        if status == 200 and raw:
            try:
                info = json.loads(raw)
            except json.JSONDecodeError:
                info = None
        if isinstance(info, dict):
            seen += 1
            if seen >= 2:
                return info
        else:
            seen = 0
        time.sleep(2)
    print("bootstrap: server did not stay up on /System/Info/Public", file=sys.stderr)
    raise SystemExit(1)


def authenticate(username: str) -> str:
    deadline = time.time() + 30
    status = 0
    while time.time() < deadline:
        status, raw = request("POST", "/Users/AuthenticateByName", {"Username": username, "Pw": PASSWORD})
        if status == 200:
            token = json.loads(raw).get("AccessToken") or ""
            if token:
                return token
        time.sleep(2)
    print(f"bootstrap: authenticate HTTP {status}", file=sys.stderr)
    raise SystemExit(1)


def add_library(token: str) -> None:
    for name, collection, path in [("Movies", "movies", "/media/movies"), ("Series", "tvshows", "/media/series")]:
        options = {
            "PathInfos": [{"Path": path}],
            "EnableRealtimeMonitor": False,
            "EnableChapterImageExtraction": False,
            "EnableInternetProviders": False,
            "TypeOptions": [
                {"Type": kind, "MetadataFetchers": [], "ImageFetchers": []}
                for kind in ["Movie", "Series", "Season", "Episode"]
            ],
        }
        status, _ = request(
            "POST", "/Library/VirtualFolders", body={"LibraryOptions": options}, token=token,
            query={"name": name, "collectionType": collection, "refreshLibrary": "true"},
        )
        if status not in (200, 204):
            print(f"bootstrap: add library HTTP {status}", file=sys.stderr)
            raise SystemExit(1)


def wait_for_movie(token: str) -> None:
    manifest = os.path.join(os.path.dirname(__file__), "..", "Tests", "Fixtures", "search-seed.json")
    with open(manifest, encoding="utf-8") as handle:
        expected = json.load(handle)["expectedSearchableItems"]
    deadline = time.time() + 600
    request("POST", "/Library/Refresh", token=token)
    count = 0
    while time.time() < deadline:
        status, raw = request(
            "GET", "/Items", token=token,
            query={"Recursive": "true", "IncludeItemTypes": "Movie,Series,Episode", "Limit": "1", "EnableTotalRecordCount": "true"},
        )
        if status == 200:
            count = json.loads(raw).get("TotalRecordCount") or 0
            if count >= expected:
                print(f"bootstrap: search library ready ({count} items)")
                return
        time.sleep(3)
    print(f"bootstrap: search library scan incomplete ({count}/{expected})", file=sys.stderr)
    raise SystemExit(1)


def detail(raw: bytes) -> str:
    text = raw.decode("utf-8", "replace")
    return text.replace(PASSWORD, "[redacted]")[:500]


def publish_username(name: str) -> None:
    path = os.environ.get("GLASSFIN_USERNAME_FILE", "")
    if not path:
        print("bootstrap: GLASSFIN_USERNAME_FILE is unset", file=sys.stderr)
        raise SystemExit(2)
    with open(path, "w", encoding="utf-8") as handle:
        handle.write(name + "\n")
    print(f"bootstrap: using username {name}")


def startup_user() -> str:
    """GET /Startup/User first so the server creates its placeholder user.

    10.10.7 returns 500 on POST until that GET runs. 10.11.x then rejects a new
    name because the placeholder username is not empty, so the POST falls back
    to the name the GET returned. The password is never printed.
    """
    deadline = time.time() + 60
    placeholder = ""
    last = b""
    status = 0
    while time.time() < deadline and not placeholder:
        status, raw = request("GET", "/Startup/User")
        last = raw
        if status == 200:
            try:
                placeholder = str(json.loads(raw).get("Name") or "")
            except json.JSONDecodeError:
                placeholder = ""
            if placeholder:
                break
        time.sleep(2)
    names: list[str] = []
    if USER:
        names.append(USER)
    if placeholder and placeholder not in names:
        names.append(placeholder)
    if not names:
        print(f"bootstrap: startup user HTTP {status} {detail(last)}", file=sys.stderr)
        raise SystemExit(1)
    while time.time() < deadline:
        for name in names:
            status, last = request("POST", "/Startup/User", {"Name": name, "Password": PASSWORD})
            if status in (200, 204):
                return name
        time.sleep(2)
    print(f"bootstrap: startup user HTTP {status} {detail(last)}", file=sys.stderr)
    raise SystemExit(1)


def main() -> None:
    info = public_info()
    username = USER
    if not info.get("StartupWizardCompleted"):
        username = startup_user()
        completed, body = request("POST", "/Startup/Complete")
        if completed not in (200, 204):
            print(f"bootstrap: startup complete HTTP {completed} {detail(body)}", file=sys.stderr)
            raise SystemExit(1)
    publish_username(username)
    token = authenticate(username)
    add_library(token)
    wait_for_movie(token)


if __name__ == "__main__":
    main()
