#!/usr/bin/env python3
"""Finish the Jellyfin startup wizard and wait for the scanned fixture movies.

Credentials come from the environment. This script never prints them or the access token.
"""

from __future__ import annotations

import argparse
import json
import os
import secrets
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


# Initialized by main, so helpers can be tested without credentials.
BASE = ""
USER = ""
PASSWORD = ""
MEDIA_DIR = ""


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


def decoded(raw: bytes):
    try:
        return json.loads(raw)
    except (ValueError, UnicodeDecodeError):
        return None


def report(message: str, token: str = "") -> None:
    # Log only selected fields, never response bodies or request headers.
    if PASSWORD:
        message = message.replace(PASSWORD, "[redacted]")
    if token:
        message = message.replace(token, "[redacted]")
    print(f"bootstrap: {message}", file=sys.stderr, flush=True)


def virtual_folders(token: str):
    status, raw = request("GET", "/Library/VirtualFolders", token=token)
    folders = decoded(raw)
    return status, folders if isinstance(folders, list) else []


def scheduled_tasks(token: str):
    status, raw = request("GET", "/ScheduledTasks", token=token)
    tasks = decoded(raw)
    return status, tasks if isinstance(tasks, list) else []


def scan_task(tasks: list) -> dict | None:
    return next((task for task in tasks if task.get("Key") == "RefreshLibrary" and task.get("Id")), None)


def diagnostics(token: str) -> None:
    status, folders = virtual_folders(token)
    paths = [
        {"Name": folder.get("Name"), "Locations": folder.get("Locations"),
         "PathInfos": (folder.get("LibraryOptions") or {}).get("PathInfos")}
        for folder in folders
    ]
    report(f"GET /Library/VirtualFolders HTTP {status}: {json.dumps(paths)}", token)
    status, tasks = scheduled_tasks(token)
    states = [
        {"Key": task.get("Key"), "State": task.get("State"),
         "LastStatus": (task.get("LastExecutionResult") or {}).get("Status")}
        for task in tasks
    ]
    report(f"GET /ScheduledTasks HTTP {status}: {json.dumps(states)}", token)


def fail(message: str, token: str) -> None:
    report(message, token)
    diagnostics(token)
    raise SystemExit(1)


def wait_for_scan_ready(token: str) -> None:
    """Wait for the worker and let any startup scan finish before changing libraries.

    In 12.2 CancelIfRunning can race with a finishing worker clearing its token
    source. Two idle reads avoid cancelling the initial scan during that window.
    """
    deadline = time.monotonic() + 180
    idle_reads = 0
    while time.monotonic() < deadline:
        status, tasks = scheduled_tasks(token)
        task = scan_task(tasks) if status == 200 else None
        if task and task.get("State") == "Idle":
            idle_reads += 1
            if idle_reads >= 2:
                return
        else:
            idle_reads = 0
        time.sleep(2)
    fail("scan worker did not become ready within 180s", token)


def add_library(token: str, name: str, collection: str) -> None:
    path = os.path.join(MEDIA_DIR, name)
    options = {
        "PathInfos": [{"Path": path}], "EnableRealtimeMonitor": False,
        "EnableInternetProviders": False, "EnableAutomaticSeriesGrouping": False,
        "MetadataSavers": [], "DisabledSubtitleFetchers": [],
        "TypeOptions": [{"Type": kind, "MetadataFetchers": [], "ImageFetchers": []}
                        for kind in ("Movie", "Series", "Season", "Episode")],
    }

    def library() -> dict | None:
        status, folders = virtual_folders(token)
        if status != 200:
            fail(f"GET /Library/VirtualFolders HTTP {status}", token)
        return next((folder for folder in folders if folder.get("Name") == name), None)

    folder = library()
    # Both creation forms exist in 10.10, 10.11 and 12. Verify persisted paths
    # after each attempt, even on 2xx or an error after a partial creation.
    for body, paths in [({"LibraryOptions": options}, {"paths": path}),
                        ({"LibraryOptions": options}, {})]:
        if folder is not None:
            break
        status, _ = request(
            "POST", "/Library/VirtualFolders", body=body, token=token,
            query={"name": name, "collectionType": collection, "refreshLibrary": "false", **paths},
        )
        report(f"POST /Library/VirtualFolders HTTP {status}", token)
        folder = library()
    if folder is not None and path not in (folder.get("Locations") or []):
        status, _ = request(
            "POST", "/Library/VirtualFolders/Paths", token=token,
            body={"Name": name, "Path": path, "PathInfo": {"Path": path}},
            query={"refreshLibrary": "false"},
        )
        report(f"POST /Library/VirtualFolders/Paths HTTP {status}", token)
        folder = library()
    if folder is None or path not in (folder.get("Locations") or []):
        fail(f"{name} library does not contain {path}", token)
    report(f"verified {name} library path {path}", token)


def refresh_library(token: str) -> bool:
    for attempt in range(6):
        status, _ = request("POST", "/Library/Refresh", token=token)
        report(f"POST /Library/Refresh HTTP {status} (attempt {attempt + 1})", token)
        if status in (200, 204):
            return True
        if status != 0 and not 500 <= status < 600:
            break
        if attempt < 5:
            time.sleep(2 ** attempt)
    return False


def require_success(status: int, action: str) -> None:
    if status not in (200, 204):
        print(f"bootstrap: {action} HTTP {status}", file=sys.stderr)
        raise SystemExit(1)


def configure_server(token: str) -> None:
    status, raw = request("GET", "/System/Configuration", token=token)
    require_success(status, "get configuration")
    config = json.loads(raw)
    # Preserve all other settings, including MinResumePct=5 and MaxResumePct=90.
    config["MinResumeDurationSeconds"] = 0
    config["QuickConnectAvailable"] = True
    status, _ = request("POST", "/System/Configuration", config, token=token)
    require_success(status, "save configuration")


def create_test_user(token: str) -> None:
    username = os.environ.get("GLASSFIN_TEST_USERNAME", "glassfin-viewer")
    password = os.environ.get("GLASSFIN_TEST_PASSWORD") or secrets.token_hex(24)
    status, raw = request("POST", "/Users/New", {"Name": username, "Password": password}, token=token)
    require_success(status, "create test user")
    user = json.loads(raw)
    user_id = user["Id"]
    policy = user.get("Policy") or {}
    policy.update({"IsAdministrator": False, "EnableAllFolders": True, "EnableMediaPlayback": True})
    status, _ = request("POST", f"/Users/{user_id}/Policy", policy, token=token)
    require_success(status, "set test user policy")
    # Callers can supply the credentials in env, or receive generated credentials in a private file.
    credentials_file = os.environ.get("GLASSFIN_TEST_CREDENTIALS_FILE")
    if credentials_file:
        fd = os.open(credentials_file, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
        os.fchmod(fd, 0o600)
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            json.dump({"username": username, "password": password}, handle)


def wait_for_scan(token: str) -> None:
    expected_movies = int(os.environ.get("GLASSFIN_SEED_ITEM_COUNT", "6"))
    expected_episodes = int(os.environ.get("GLASSFIN_SEED_EPISODE_COUNT", "3"))
    refresh_library(token)
    deadline = time.monotonic() + 240
    next_scan = time.monotonic() + 15
    status = 0
    item_status = 0
    while time.monotonic() < deadline:
        ready = True
        counts = []
        for kind, expected in [("Movie", expected_movies), ("Series", 1), ("Season", 1), ("Episode", expected_episodes)]:
            status, raw = request("GET", "/Items", token=token, query={
                "Recursive": "true", "IncludeItemTypes": kind, "Limit": "100",
                "Fields": "MediaStreams,Path",
            })
            item_status = status
            result = decoded(raw) if status == 200 else None
            result = result if isinstance(result, dict) else {}
            items = result.get("Items") or []
            count = result.get("TotalRecordCount") or 0
            counts.append(count)
            ready = ready and count >= expected
            if kind in ("Movie", "Episode"):
                # Counts appear before ffprobe finishes on some server versions.
                ready = ready and len(items) >= expected and all(
                    item.get("RunTimeTicks", 0) > 0 and any(
                        stream.get("Type") == "Video" and stream.get("Codec")
                        for stream in item.get("MediaStreams", [])
                    ) for item in items
                )
        status, tasks = scheduled_tasks(token)
        if status == 200:
            ready = ready and not any(task.get("Key") == "RefreshLibrary" and
                                     task.get("State") in ("Running", "Cancelling") for task in tasks)
        else:
            ready = False
        if ready:
            print(f"bootstrap: scan complete ({counts[0]} movies, {counts[1]} series, {counts[2]} season, {counts[3]} episodes)")
            return
        if time.monotonic() >= next_scan:
            task = scan_task(tasks) if status == 200 else None
            # 12.2 can silently ignore refresh; start the idle worker directly.
            if task and task.get("State") == "Idle":
                task_id = urllib.parse.quote(str(task["Id"]), safe="")
                started, _ = request("POST", f"/ScheduledTasks/Running/{task_id}", token=token)
                report(f"start RefreshLibrary task HTTP {started}", token)
            next_scan = time.monotonic() + 30
        time.sleep(2)
    fail(f"library scan did not finish with all probed movies and episodes within 240s; GET /Items HTTP {item_status}; GET /ScheduledTasks HTTP {status}", token)


def publish_username(name: str) -> None:
    path = os.environ.get("GLASSFIN_USERNAME_FILE", "")
    if not path:
        return
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
    status = 0
    while time.time() < deadline and not placeholder:
        status, raw = request("GET", "/Startup/User")
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
        report(f"startup user HTTP {status}")
        raise SystemExit(1)
    while time.time() < deadline:
        for name in names:
            status, _ = request("POST", "/Startup/User", {"Name": name, "Password": PASSWORD})
            if status in (200, 204):
                return name
        time.sleep(2)
    report(f"startup user HTTP {status}")
    raise SystemExit(1)


def main() -> None:
    global BASE, USER, PASSWORD, MEDIA_DIR
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--server-url", default=os.environ.get("GLASSFIN_SERVER_URL"))
    parser.add_argument("--media-dir", default=os.environ.get("GLASSFIN_SERVER_MEDIA_DIR", "/media"),
                        help="media directory as seen by the server (not the caller)")
    args = parser.parse_args()
    BASE = (args.server_url or env("GLASSFIN_SERVER_URL")).rstrip("/")
    MEDIA_DIR = args.media_dir
    USER = env("GLASSFIN_USERNAME")
    PASSWORD = env("GLASSFIN_PASSWORD")
    info = public_info()
    username = USER
    if not info.get("StartupWizardCompleted"):
        username = startup_user()
        completed, _ = request("POST", "/Startup/Complete")
        if completed not in (200, 204):
            report(f"startup complete HTTP {completed}")
            raise SystemExit(1)
    publish_username(username)
    token = authenticate(username)
    wait_for_scan_ready(token)
    configure_server(token)
    create_test_user(token)
    add_library(token, "Movies", "movies")
    add_library(token, "Shows", "tvshows")
    wait_for_scan(token)


if __name__ == "__main__":
    main()
