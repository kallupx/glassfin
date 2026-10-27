#!/usr/bin/env python3
"""Finish the Jellyfin startup wizard and wait for the scanned fixture movies.

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


def decoded(raw: bytes):
    try:
        return json.loads(raw)
    except (ValueError, UnicodeDecodeError):
        return None


def report(message: str, token: str = "") -> None:
    # Log only selected fields, never response bodies or request headers.
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


def add_library(token: str) -> None:
    def movies() -> dict | None:
        status, folders = virtual_folders(token)
        if status != 200:
            fail(f"GET /Library/VirtualFolders HTTP {status}", token)
        return next((folder for folder in folders if folder.get("Name") == "Movies"), None)

    folder = movies()
    # Both creation forms exist in 10.10, 10.11 and 12. Verify persisted paths
    # after each attempt, even on 2xx or an error after a partial creation.
    for body, paths in [(None, {"paths": "/media"}),
                        ({"LibraryOptions": {"PathInfos": [{"Path": "/media"}]}}, {})]:
        if folder is not None:
            break
        status, _ = request(
            "POST", "/Library/VirtualFolders", body=body, token=token,
            query={"name": "Movies", "collectionType": "movies", "refreshLibrary": "false", **paths},
        )
        report(f"POST /Library/VirtualFolders HTTP {status}", token)
        folder = movies()
    if folder is not None and "/media" not in (folder.get("Locations") or []):
        status, _ = request(
            "POST", "/Library/VirtualFolders/Paths", token=token,
            body={"Name": "Movies", "Path": "/media", "PathInfo": {"Path": "/media"}},
            query={"refreshLibrary": "false"},
        )
        report(f"POST /Library/VirtualFolders/Paths HTTP {status}", token)
        folder = movies()
    if folder is None or "/media" not in (folder.get("Locations") or []):
        fail("Movies library does not contain /media", token)
    report("verified Movies library path /media", token)


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


def wait_for_movie(token: str) -> None:
    expected = int(os.environ.get("GLASSFIN_SEED_ITEM_COUNT", "1"))
    refresh_library(token)
    deadline = time.monotonic() + 240
    next_scan = time.monotonic() + 15
    status = 0
    while time.monotonic() < deadline:
        status, raw = request(
            "GET",
            "/Items",
            token=token,
            query={"Recursive": "true", "IncludeItemTypes": "Movie", "Limit": "5"},
        )
        if status == 200:
            items = decoded(raw)
            count = (items.get("TotalRecordCount") or 0) if isinstance(items, dict) else 0
            if count >= expected:
                print(f"bootstrap: {count} fixture movies are in the library")
                return
        if time.monotonic() >= next_scan:
            task_status, tasks = scheduled_tasks(token)
            task = scan_task(tasks) if task_status == 200 else None
            # 12.2's refresh controller logs exceptions but still returns 204.
            # Start an idle worker directly if refresh did not discover the movie.
            if task and task.get("State") == "Idle":
                task_id = urllib.parse.quote(str(task["Id"]), safe="")
                started, _ = request("POST", f"/ScheduledTasks/Running/{task_id}", token=token)
                report(f"start RefreshLibrary task HTTP {started}", token)
            next_scan = time.monotonic() + 30
        time.sleep(3)
    fail(f"library scan did not find all {expected} fixture movies within 240s; GET /Items HTTP {status}", token)


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
    add_library(token)
    wait_for_movie(token)


if __name__ == "__main__":
    main()
