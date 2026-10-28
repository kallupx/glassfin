# Local Jellyfin E2E in GitHub Actions

The `jellyfin-e2e` job in `.github/workflows/ci.yml` runs on the macOS
`xcode-27` runner when a pull request has `full-ci`, or on `workflow_dispatch`.
It has a 40-minute timeout and `contents: read` permissions. It does not use
`pull_request_target`, repository secrets, Docker, an external server, or real
credentials. Pushes to main do not start it.

## What runs

1. Download the official Jellyfin **10.11.11** macOS headless tarball and
   jellyfin-ffmpeg **7.1.4-3** for the runner architecture. Both archives must
   match the SHA-256 values committed in `scripts/ci/jellyfin-macos-pins.json`
   before either archive is extracted. There are no `latest` URLs. The hashes
   were computed from the exact official repository downloads; upgrades require
   reviewing the URLs and recomputing the committed hashes.
2. Write a fresh network configuration before launching the tarball with
   `--datadir`, `--cachedir`, `--configdir`, `--logdir`, `--nowebclient` and
   `--ffmpeg`. Only `127.0.0.1:8096` is allowed. IPv6, UPnP, remote access and
   auto-discovery are disabled. Inspect the process's sockets with `lsof` and
   reject unexpected TCP or UDP listeners. Refuse an occupied port or a server
   whose startup wizard was already completed.
3. POST `/Startup/Configuration`, initialize and POST `/Startup/User`, disable
   remote access, and POST `/Startup/Complete`. Generate separate runtime admin
   and non-admin viewer credentials, mask passwords and the bootstrap access
   token immediately with `::add-mask::`, and keep them out of command arguments.
4. Generate CC0 testsrc/sine media: F3 MKV/H.264/AAC (60 seconds), F4
   MKV/H.264/DTS (6 seconds), and a series with two episodes. Every item has two
   audio tracks, the second marked default using `-disposition:a:1 default`,
   and an embedded SRT subtitle. Both F4 audio tracks are DTS so the default
   track still needs transcoding. No downloaded media or internet metadata is
   needed. Add Movies and Shows with `/Library/VirtualFolders`, POST
   `/Library/Refresh`, and poll `/Items` until all items and streams are present.
5. If `TPOCPlaybackAcceptanceUITests.swift` from draft PR #47 is present, erase
   the tvOS simulator, build for testing, and run only its two acceptance tests
   through the real network stack. These are the exact environment variables
   consumed by `PoCLiveServerConfiguration`:

   - `TEST_RUNNER_GLASSFIN_POC_SERVER_URL=http://127.0.0.1:8096`
   - `TEST_RUNNER_GLASSFIN_POC_USERNAME`
   - `TEST_RUNNER_GLASSFIN_POC_PASSWORD`
   - `TEST_RUNNER_GLASSFIN_POC_ADMIN_USERNAME`
   - `TEST_RUNNER_GLASSFIN_POC_ADMIN_PASSWORD`

   The values are generated inside this job. Xcode strips `TEST_RUNNER_` when
   forwarding them to XCTest. No credentials are set through `$GITHUB_ENV`,
   workflow outputs, scheme files, command arguments, or step summaries.
6. Always stop the server, erase the used simulator, sanitize allowlisted text
   logs and delete the entire private runner-temp directory, including database,
   credentials, transcodes, DerivedData, diagnostics and any transient xcresults.
   Raw xcresults, screenshots, xctestrun files and server state are never uploaded.
   The existing `redact_artifacts.py` redactor and fail-closed
   `scan_benchmark_artifacts.py` leak check apply to every uploaded file. Logs
   are JSON-wrapped text so this scanner can inspect them. Credential-bearing
   diagnostic lines are omitted; known generated values are redacted first.
   Upload is blocked unless cleanup and scanning succeed.

## DEBUG reset and ATS: Turvallisuus review

`-uitest-reset` now clears app-scoped keychain items, UserDefaults, URLCache and
Glassfin disk caches before assembling services. It does not select mocks.
`-uitest-mock-server` and `-uitest-home` still explicitly select the existing mock
services. The reset implementation, argument parsing and all calls live entirely
inside `#if DEBUG`; Release cannot select this path or bypass certificate
pinning. A reset failure stops the DEBUG launch instead of silently reusing state.
The reset deletes only generic-password items for the Glassfin service and its
configured access group, not arbitrary keychain entries.

The first connection attempt uses the numeric loopback address `127.0.0.1`,
without adding an ATS exception. No app or runner ATS configuration is changed
by this PR. The existing app plists already contain `NSAllowsLocalNetworking`;
this PR leaves those baseline settings unchanged. If runner-side URLSession
requires additional ATS permission once #47 lands, it must be restricted to the
**UI test runner Info.plist**, trying a numeric loopback exception first. Never
add or broaden an exception in the Release app plist. The in-app cleartext
warning and pin validation remain in use; #47 accepts the warning through UI.

## How to test and current limits

Add `full-ci` to the pull request and watch `gh pr checks`, or dispatch `ci`
on the branch. The install/start/bootstrap steps must pass even before #47
lands. `setup.json` records the validated fixture counts; `tests.json` explicitly
reports unavailable acceptance tests with zero tests run until that source lands.
An unavailable suite is not a playback acceptance pass. Once present, failures
are fatal, including missing M07 identifiers or M08 player wiring.

PR #47 is stacked on #44. This branch intentionally does not merge those app
changes. Its tests currently launch with `-AppleLanguages (en)` only and rely on
a clean simulator; this job erases the simulator first. Future tests can add
`-uitest-reset` without enabling mocks. iOS acceptance is omitted because #47's
journeys are compiled only for tvOS. Normal iOS and tvOS CI continues to check
the app, including the new reset regression tests and Release binary scan.

Setup targets about one to two minutes; downloads depend on repository and
runner performance. Installation, startup, bootstrap and XCTest have separate
bounded steps. Cleanup has a reserved two-minute step within the job timeout.
A forcibly terminated runner cannot upload artifacts; its disposable workspace
must be discarded by the runner service.

Local Linux validation uses only generated media, mocks and package tests:

```sh
python3 -m unittest discover -s scripts/ci -p 'test_*.py'
bash -n scripts/ci/generate-jellyfin-e2e-media.sh
swift test --package-path Packages/GlassfinCore
```

Official upstream references: [macOS server installation](https://jellyfin.org/docs/general/installation/macos/),
[headless macOS server and FFmpeg guidance](https://jellyfin.org/docs/general/testing/server/macos/),
[10.11.11 server archives](https://repo.jellyfin.org/files/server/macos/stable/v10.11.11/),
and [7.1.4-3 FFmpeg archives](https://repo.jellyfin.org/files/ffmpeg/macos/7.x/7.1.4-3/).
