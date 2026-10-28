#!/usr/bin/env python3
"""Disposable native Jellyfin for CI only; never accepts an external server URL.

Raw state, credentials, build products and xcresults stay in a private runner-temp
folder. Only allowlisted, sanitized JSON text leaves it during cleanup.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import secrets
import shutil
import signal
import socket
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

SCRIPTS = Path(__file__).resolve().parents[1]
REPO = SCRIPTS.parent
BASE = "http://127.0.0.1:8096"
CLIENT = 'MediaBrowser Client="Glassfin CI setup", Device="CI", DeviceId="glassfin-ci-setup", Version="0.1.0"'
# Never follow an API redirect out of the disposable server.
class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None

API = urllib.request.build_opener(urllib.request.ProxyHandler({}), NoRedirect())


def private_json(path: Path, value) -> None:
    with path.open("w", encoding="utf-8") as handle:
        os.chmod(path, 0o600)
        json.dump(value, handle)


def request(method: str, path: str, body=None, token: str = "", query=None):
    if not path.startswith("/") or path.startswith("//"):
        raise RuntimeError("invalid local API path")
    url = BASE + path
    if query:
        url += "?" + urllib.parse.urlencode(query)
    headers = {"Authorization": CLIENT + (f', Token="{token}"' if token else ""),
               "Content-Type": "application/json"}
    data = json.dumps(body).encode() if body is not None else None
    try:
        with API.open(urllib.request.Request(url, data=data, headers=headers, method=method), timeout=5) as reply:
            raw = reply.read()
            return json.loads(raw) if raw else None
    except urllib.error.HTTPError as error:
        # Response bodies can contain request data. Never include them in errors.
        raise RuntimeError(f"local API {method} {path.split('?')[0]} HTTP {error.code}") from None


def wait_for(action, seconds: int, description: str):
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        try:
            result = action()
            if result:
                return result
        except (OSError, ValueError, RuntimeError):
            pass
        time.sleep(1)
    raise RuntimeError(f"timed out waiting for {description}")


def install(root: Path) -> None:
    if platform.system() != "Darwin":
        raise RuntimeError("native installation requires a macOS CI runner")
    pins = json.loads((SCRIPTS / "ci/jellyfin-macos-pins.json").read_text())
    archives = []
    for name, pin in pins[platform.machine()].items():
        archive = root / (name + ".tar.xz")
        with urllib.request.urlopen(pin["url"], timeout=60) as reply, archive.open("wb") as output:
            shutil.copyfileobj(reply, output)
        if hashlib.sha256(archive.read_bytes()).hexdigest() != pin["sha256"]:
            raise RuntimeError(f"{name} SHA-256 mismatch; extraction refused")
        archives.append((name, archive))
    # Verify BOTH downloads before extracting either one.
    for name, archive in archives:
        destination = root / name
        destination.mkdir()
        subprocess.run(["tar", "-xJf", str(archive), "-C", str(destination)], check=True)
        archive.unlink()
    subprocess.run(["xattr", "-rd", "com.apple.quarantine", str(root)], check=True)
    print(f"Verified Jellyfin {pins['serverVersion']} and jellyfin-ffmpeg {pins['ffmpegVersion']}.")


def start(root: Path) -> None:
    # Fail if the fixed port is already in use; never bootstrap an existing server.
    with socket.socket() as probe:
        probe.bind(("127.0.0.1", 8096))
    config = root / "config"
    config.mkdir()
    (config / "network.xml").write_text('''<?xml version="1.0" encoding="utf-8"?>
<NetworkConfiguration>
  <InternalHttpPort>8096</InternalHttpPort><PublicHttpPort>8096</PublicHttpPort>
  <EnableHttps>false</EnableHttps><RequireHttps>false</RequireHttps>
  <EnableIPv4>true</EnableIPv4><EnableIPv6>false</EnableIPv6>
  <LocalNetworkAddresses><string>127.0.0.1</string></LocalNetworkAddresses>
  <LocalNetworkSubnets><string>127.0.0.0/8</string></LocalNetworkSubnets>
  <EnableRemoteAccess>false</EnableRemoteAccess><EnableUPnP>false</EnableUPnP>
  <AutoDiscovery>false</AutoDiscovery>
</NetworkConfiguration>
''')
    # No external metadata, plugin repository updates or telemetry needed by these fixtures.
    (config / "system.xml").write_text('''<?xml version="1.0" encoding="utf-8"?>
<ServerConfiguration>
  <IsStartupWizardCompleted>false</IsStartupWizardCompleted>
  <EnableMetrics>false</EnableMetrics><EnableAutoUpdate>false</EnableAutoUpdate>
  <PluginRepositories />
</ServerConfiguration>
''')
    with (root / "server.log").open("w") as output:
        process = subprocess.Popen([
            str(root / "server/jellyfin/jellyfin"), "--datadir", str(root / "data"),
            "--cachedir", str(root / "cache"), "--configdir", str(config),
            "--logdir", str(root / "logs"), "--nowebclient", "--ffmpeg", str(root / "ffmpeg/ffmpeg"),
        ], stdout=output, stderr=subprocess.STDOUT, start_new_session=True)
    private_json(root / "pid.json", process.pid)
    info = wait_for(lambda: request("GET", "/System/Info/Public"), 60, "fresh local Jellyfin")
    if info.get("StartupWizardCompleted"):
        raise RuntimeError("refusing an already configured server")
    listeners = subprocess.run(["lsof", "-nP", "-a", "-p", str(process.pid), "-iTCP", "-sTCP:LISTEN", "-Fn"],
                               capture_output=True, text=True, check=True)
    addresses = [line[1:] for line in listeners.stdout.splitlines() if line.startswith("n")]
    udp = subprocess.run(["lsof", "-nP", "-a", "-p", str(process.pid), "-iUDP", "-Fn"], capture_output=True)
    if addresses != ["127.0.0.1:8096"] or udp.stdout:
        raise RuntimeError("server is not restricted to the loopback TCP listener")
    print("Fresh Jellyfin listening only on 127.0.0.1:8096; no UDP discovery listener.")


def remember(root: Path, value: str) -> str:
    print(f"::add-mask::{value}", flush=True)
    path = root / "sensitive.json"
    values = json.loads(path.read_text()) if path.exists() else []
    private_json(path, values + [value])
    return value


def bootstrap(root: Path) -> None:
    admin = remember(root, "glassfin-ci-" + secrets.token_hex(4))
    viewer = remember(root, "glassfin-viewer-" + secrets.token_hex(4))
    admin_pw = remember(root, secrets.token_hex(24))
    viewer_pw = remember(root, secrets.token_hex(24))
    request("POST", "/Startup/Configuration", {"ServerName": "Glassfin CI", "UICulture": "en-US",
            "MetadataCountryCode": "US", "PreferredMetadataLanguage": "en"})
    # Initialize the placeholder user before renaming it (required by Jellyfin).
    request("GET", "/Startup/User")
    request("POST", "/Startup/User", {"Name": admin, "Password": admin_pw})
    request("POST", "/Startup/RemoteAccess", {"EnableRemoteAccess": False, "EnableAutomaticPortMapping": False})
    request("POST", "/Startup/Complete")
    auth = request("POST", "/Users/AuthenticateByName", {"Username": admin, "Pw": admin_pw})
    token = remember(root, auth["AccessToken"])
    user = request("POST", "/Users/New", {"Name": viewer, "Password": viewer_pw}, token)
    policy = user["Policy"]
    policy.update(IsAdministrator=False, EnableAllFolders=True, EnableMediaPlayback=True,
                  EnableAudioPlaybackTranscoding=True, EnableVideoPlaybackTranscoding=True,
                  EnablePlaybackRemuxing=True)
    request("POST", f"/Users/{user['Id']}/Policy", policy, token)
    subprocess.run(["bash", str(SCRIPTS / "ci/generate-jellyfin-e2e-media.sh"),
                    str(root / "media"), str(root / "ffmpeg/ffmpeg")], check=True)
    for name, kind in [("Movies", "movies"), ("Shows", "tvshows")]:
        path = str(root / "media" / name)
        options = {"PathInfos": [{"Path": path}], "EnableRealtimeMonitor": False,
                   "EnableInternetProviders": False, "SaveLocalMetadata": False,
                   "EnableAutomaticSeriesGrouping": False, "MetadataSavers": [],
                   "TypeOptions": [{"Type": item, "MetadataFetchers": [], "ImageFetchers": []}
                                   for item in ["Movie", "Series", "Season", "Episode"]]}
        request("POST", "/Library/VirtualFolders", {"LibraryOptions": options}, token,
                {"name": name, "collectionType": kind, "paths": path, "refreshLibrary": "false"})
    request("POST", "/Library/Refresh", token=token)

    def scanned():
        page = request("GET", "/Items", token=token, query={"Recursive": "true",
                       "IncludeItemTypes": "Movie,Series,Episode", "Fields": "MediaStreams,MediaSources"})
        items = page.get("Items", [])
        movies = [item for item in items if item.get("Type") == "Movie"]
        episodes = [item for item in items if item.get("Type") == "Episode"]
        if len(movies) != 2 or len(episodes) != 2 or not any(i.get("Type") == "Series" for i in items):
            return False
        for item in movies + episodes:
            streams = item.get("MediaStreams", [])
            audio = [s for s in streams if s.get("Type") == "Audio"]
            if len(audio) != 2 or not audio[1].get("IsDefault") or not any(s.get("Type") == "Subtitle" for s in streams):
                return False
        codecs = {s.get("Codec") for i in movies for s in i.get("MediaStreams", []) if s.get("Type") == "Audio"}
        return {"aac", "dts"} <= codecs

    wait_for(scanned, 60, "F3/F4 media streams and the two-episode series scan")
    private_json(root / "runner-env.json", {
        "TEST_RUNNER_GLASSFIN_POC_SERVER_URL": BASE,
        "TEST_RUNNER_GLASSFIN_POC_USERNAME": viewer,
        "TEST_RUNNER_GLASSFIN_POC_PASSWORD": viewer_pw,
        "TEST_RUNNER_GLASSFIN_POC_ADMIN_USERNAME": admin,
        "TEST_RUNNER_GLASSFIN_POC_ADMIN_PASSWORD": admin_pw,
    })
    private_json(root / "setup.json", {"serverSetup": "passed", "movies": 2, "series": 1, "episodes": 2,
                                      "audioTracksPerItem": 2, "secondAudioDefault": True, "subtitlesPerItem": 1})
    print("Startup wizard, generated users, libraries and scan passed (F3/F4 + two episodes).")


def run_tests(root: Path) -> None:
    acceptance = REPO / "Apps/Shared/UITests/TPOCPlaybackAcceptanceUITests.swift"
    if not acceptance.is_file():
        private_json(root / "tests.json", {"acceptance": "unavailable", "reason": "PR #47 has not landed",
                                          "testsRun": 0})
        print("F3/F4 acceptance tests unavailable: PR #47 has not landed; server setup passed.")
        return
    if not shutil.which("xcodegen"):
        subprocess.run(["brew", "install", "xcodegen"], check=True)
    subprocess.run(["xcodegen", "generate"], cwd=REPO, check=True)
    devices = json.loads(subprocess.check_output(["xcrun", "simctl", "list", "devices", "available", "--json"]))
    tvs = [d for runtime, group in devices["devices"].items() if ".tvOS-" in runtime for d in group]
    if not tvs:
        raise RuntimeError("no tvOS simulator installed")
    device = tvs[0]["udid"]
    # Dedicated simulator: reset between jobs, and never mix mock suites into this run.
    subprocess.run(["xcrun", "simctl", "shutdown", device], capture_output=True)
    subprocess.run(["xcrun", "simctl", "erase", device], check=True)
    private_json(root / "simulator.json", device)
    command = ["xcodebuild", "-scheme", "Glassfin-tvOS", "-destination", f"platform=tvOS Simulator,id={device}",
               "-derivedDataPath", str(root / "DerivedData"), "-clonedSourcePackagesDirPath", str(root / "SourcePackages"),
               "CODE_SIGNING_ALLOWED=NO", "-parallel-testing-enabled", "NO"]
    with (root / "xcodebuild.log").open("w") as log:
        subprocess.run(command + ["build-for-testing"], cwd=REPO, stdout=log, stderr=subprocess.STDOUT, check=True)
        environment = os.environ.copy()
        environment.update(json.loads((root / "runner-env.json").read_text()))
        # No result bundle is published. Disable screenshots/diagnostics that could capture sign-in fields.
        result = subprocess.run(command + ["test-without-building", "-only-testing:Glassfin-tvOSUITests/TPOCPlaybackAcceptanceUITests",
                                 "-disable-concurrent-destination-testing", "-collect-test-diagnostics", "never"],
                                cwd=REPO, env=environment, stdout=log, stderr=subprocess.STDOUT)
    private_json(root / "tests.json", {"acceptance": "passed" if result.returncode == 0 else "failed"})
    if result.returncode:
        raise RuntimeError("F3/F4 acceptance failed; see sanitized xcodebuild log")


def cleanup(root: Path) -> None:
    if (root / "pid.json").exists():
        pid = json.loads((root / "pid.json").read_text())
        try:
            os.killpg(pid, signal.SIGTERM)
            for _ in range(20):
                time.sleep(0.25)
                try:
                    os.kill(pid, 0)
                except ProcessLookupError:
                    break
            else:
                os.killpg(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    if (root / "simulator.json").exists():
        device = json.loads((root / "simulator.json").read_text())
        subprocess.run(["xcrun", "simctl", "shutdown", device], capture_output=True)
        subprocess.run(["xcrun", "simctl", "erase", device], check=True, capture_output=True)
    # Only JSON text is uploaded, so the existing fail-closed artifact scanner can inspect every file.
    sys.path.insert(0, str(SCRIPTS))
    from redact_artifacts import redact
    from scan_benchmark_artifacts import CREDENTIAL, scan
    sensitive_path = root / "sensitive.json"
    sensitive = json.loads(sensitive_path.read_text()) if sensitive_path.exists() else []
    candidates = [root / "server.log", root / "xcodebuild.log", root / "setup.json", root / "tests.json"]
    candidates += sorted((root / "logs").glob("*.log"))
    output = REPO / "artifacts/jellyfin-e2e"
    output.mkdir(parents=True, exist_ok=True)
    for index, path in enumerate(candidates):
        if not path.is_file():
            continue
        lines = []
        for line in path.read_text(errors="replace").splitlines():
            for value in sensitive:
                line = line.replace(value, "[redacted]")
            line = redact(line)
            # Fail-closed existing scanner rejects credential markers even after value redaction.
            if CREDENTIAL.search(line):
                line = "[sensitive diagnostic line omitted]"
            lines.append(line)
        private_json(output / f"{index}-{path.stem}.json", {"lines": lines})
    private_json(output / "cleanup.json", {"serverStopped": True, "privateStateRemoved": True})
    shutil.rmtree(root)  # Includes credentials, database, caches, transcodes, xcresults and diagnostics.
    if scan(sorted(output.glob("*.json"))) != 0:
        raise RuntimeError("artifact leak check failed; upload blocked")
    with open(os.environ["GITHUB_OUTPUT"], "a") as handle:
        handle.write("safe=true\n")
    print("Stopped server, removed private state, sanitized logs and passed artifact leak check.")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=["install", "start", "bootstrap", "test", "cleanup"])
    args = parser.parse_args()
    if os.environ.get("CI") != "true" or not os.environ.get("RUNNER_TEMP"):
        raise RuntimeError("this script runs only inside CI")
    root = Path(os.environ["RUNNER_TEMP"]) / (
        f"glassfin-e2e-{os.environ['GITHUB_RUN_ID']}-{os.environ['GITHUB_RUN_ATTEMPT']}")
    if root.parent.resolve() != Path(os.environ["RUNNER_TEMP"]).resolve() or not root.name.startswith("glassfin-e2e-"):
        raise RuntimeError("private root must be a dedicated runner-temp child")
    os.umask(0o077)
    root.mkdir(mode=0o700, exist_ok=True)
    globals()[{"test": "run_tests"}.get(args.action, args.action)](root)


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        # Exceptions from subprocesses/HTTP may contain secrets; print only our controlled messages.
        print(str(error) if type(error) is RuntimeError else f"local Jellyfin action failed ({type(error).__name__})",
              file=sys.stderr)
        raise SystemExit(1)
