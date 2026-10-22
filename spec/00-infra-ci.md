# M00 – Infra, repo, and macOS CI (P0)

**Spec version:** v1.3.3 (22.10.2026). Changes are shown in SPEC.md's change history.

**Dependencies:** none (done first). **Owner:** Coder. **Reviewers:** Tester, Security.

## Why
The Tester has only a Linux machine. Xcode, the tvOS simulator, and XCUITest work only on macOS, so **all testing runs in CI on a macOS runner**. The Tester reads the results from artifacts (JUnit, xcresult, screenshots).

## Repo
- ✅ **RESOLVED: GitHub repo `kallupx/glassfin`, public from 22.10.2026** (private 21.–22.10.). It can later be moved to an organization. M00 has no blockers.
  - Moving to an organization: GitHub redirects old URLs to the new one, but Actions secrets, branch-protection rules, and any GitHub Apps installations are checked after the move. Workflows do not use a hardcoded owner (`${{ github.repository }}`).
  - Once the repo becomes public, minutes on standard GitHub-hosted runners are free (see costs below), and CI limits can be relaxed.
- The application's name is **Glassfin** (tvOS and iOS). The proposed bundle ID is `org.glassfin.app` (placeholder, SPEC.md §6.13).
- **An Apple Developer account is not a prerequisite for M00:** CI builds and tests on the simulator without signing (`CODE_SIGNING_ALLOWED=NO`, no Apple account). Installation on one's own device works with a free Apple ID (Personal Team, 7-day provisioning). Paid membership is needed only before TestFlight (SPEC.md §7).
- Layout:
  ```
  /Packages/GlassfinCore   # Swift package, shared tvOS + iOS (M01–M02)
  /Apps/tvOS               # Glassfin tvOS app target, UI (primary)
  /Apps/iOS                # Glassfin iOS app target, builds from day one (UI is a stub at first, M11)
  /Tests/Fixtures          # JSON fixtures from real Jellyfin responses (12.x and 10.10/10.11)
  /Tests/Media             # test-media matrix (see 08-playback.md), not in the repo but downloadable
  /spec                    # this spec
  ```
- Xcode project generation: XcodeGen or Tuist (the Coder chooses, so that the project file does not cause merge conflicts). This is a recommendation, not a requirement.
- Swift 6 language mode and strict concurrency `complete`.
- **Open source:** the user's decision on 21.10.2026 is that the app is free and open source. The repo is public from 22.10.2026. License files are included from the start, so that publishing does not require follow-up work.
  - At the root there is `LICENSE` (**MPL-2.0 – PROPOSAL – requires user confirmation**, see SPEC.md §7 R9) and `THIRD_PARTY_LICENSES` (L4): every dependency, its version, license, and source-code link. For binary libraries (FFmpeg, VLCKit, MPV), add a link or tarball of the exactly corresponding source, plus the build configuration (the configure line and a possible `changes.diff`).
  - Files copied from Swiftfin keep their MPL-2.0 headers and copyright notices.

## CI requirements (GitHub Actions)
- Verified 21.10.2026:
  - GitHub's `xcode-27` runner label has been generally available since 15.10.2026 (Apple Silicon). It has the tvOS 27.0/27.2 and iOS 27 SDKs, and the simulators "Apple TV 4K (3rd generation)" and "(at 1080p)".
  - The `macos-26` image has Xcode 26.6 and tvOS 26.x simulators.
  - **Use only standard labels** (`xcode-27`, `macos-26`), **not the `xcode-27-xlarge` label**. Larger runners are not included in free minutes even in public repos.

### Public repo (v1.3.3, in effect from 22.10.2026)
- **Price:** standard runners (`ubuntu-latest`, `xcode-27`, `macos-26`) are free and unlimited. Larger runners (`*-xlarge`, `*-large`) still cost money and are forbidden.
- **A self-hosted runner is forbidden.** Fork-PR code would be able to run on it.
- **Concurrency:** on the Free plan, at most 20 jobs, of which 5 are macOS jobs. While several agents are running, the macOS queue is the bottleneck, so:
  - every workflow has `concurrency: group: ${{ github.workflow }}-${{ github.ref }}`, `cancel-in-progress: true` (an outdated run is cancelled when a new push arrives);
  - **draft PR:** `lint` + `test-tvos` + `test-ios` (the iOS path filter is removed);
  - **ready for review and a main push:** additionally `full-ui` (every XCUITest, snapshots, and `XCTMetric`). The `full-ci` label is no longer required, but it can force full-ui on a draft;
  - `integration.yml` (Linux, Docker) runs on every PR that touches the `Packages/**` path.
- **Security (Security's checklist):** "Require approval for all outside collaborators" is on; no `pull_request_target` and no `workflow_run`; `permissions: contents: read` by default; signing secrets only in an `environment: release` environment whose required reviewer is the user. Also Settings → Code security: secret scanning + push protection, and private vulnerability reporting on (the user sets these).
- **Public logs and artifacts:** everything is visible to everyone. S5.5 redaction is mandatory, `.xcresult` bundles are not uploaded as artifacts, and artifacts have `retention-days: 14`.
- **Image risk:** `xcode-27` is still in preview on GitHub's list. If it is disrupted, the fallback is `macos-26` + Xcode 26 (the tvOS 26 SDK is enough for the minimum version).
- The private-repo section below is history and no longer governs CI.

### ~~Cost limits (private repo)~~ (history, not in effect from 22.10.2026)
- Verified from GitHub Docs on 21.10.2026:
  - A GitHub Free account includes **2,000 Actions minutes per month** for private repos.
  - A macOS standard runner costs $0.062/min and a Linux 2-core costs $0.006/min, so **macOS consumes minutes about 10 times over**. In practice the budget is **about 200 macOS minutes per month**.
  - Minutes are rounded up per job.
  - Without a payment method, usage stops when the quota is full.
  - In public repos, standard runners are free.
- **Mandatory savings measures:**
  1. **Triggers:** `pull_request` (targeting `main`) and `push` to the `main` branch. **No** pushes of feature branches, **no** scheduled macOS runs by default. `workflow_dispatch` is for manual runs.
  2. **Path filters:** macOS jobs run only when the change touches `Packages/**`, `Apps/**`, `Tests/**`, `*.xcodeproj`/`project.yml`/`Project.swift`, `Package.resolved`, or `.github/workflows/**`. Changes that are only `spec/**`, `*.md`, or `docs/**` do not start macOS jobs.
  3. **Concurrency:** `concurrency: { group: ${{ github.workflow }}-${{ github.ref }}, cancel-in-progress: true }`. A new push on the same PR cancels the old run.
  4. **Caches:** `actions/cache` for SPM (`~/Library/Caches/org.swift.swiftpm`, `.build`, keyed by the `Package.resolved` hash) and for DerivedData (keyed by the Xcode version, `Package.resolved`, and the project-file hash). Remember the 10 GB/repo cache-storage limit: old keys are cleaned up.
  5. **A fast Linux job first** (`runs-on: ubuntu-latest`, about 1× price). macOS jobs depend on it (`needs: lint`), so a lint or license error does not consume macOS minutes.
  6. **A light macOS core on PRs:** a PR runs GlassfinCore's tests (`swift test`) plus tvOS unit and UI smoke tests in one macOS job (one simulator boot). **iOS tests run on a PR only if the change touches `Apps/iOS/**` or `Packages/**`**, and always on a main push. The heavy UI suite (every XCUITest and snapshots at 1080p/4K + accessibility variants) and the `XCTMetric` performance tests run **on a main push and with the PR label `full-ci`**, not on every PR push.
  7. **A tvOS 26 smoke test of the minimum version** (`macos-26`): as a manual run and before release/TestFlight, not daily (a daily run would by itself consume a significant part of the budget).
  8. **Timeouts:** `timeout-minutes` per job (macOS 25 min, Linux 10 min), so that a stuck simulator does not burn the budget.
  9. **Budget watch:** GitHub Billing → Budgets: an Actions budget of $0 and "Stop usage when budget limit is reached" (the user sets this), so that there are no surprise bills. The Coder watches consumption (Settings → Billing → Usage), and if 200 min is not enough, the options are (a) the user's own Mac as a self-hosted runner (free in minutes; ⚠️ security: private repo only, no fork PR runs), (b) GitHub Pro (3,000 min ≈ 300 macOS min), or (c) making the repo public earlier.
- Estimate (ASSUMPTION, to be measured on the first runs): a cold tvOS build and tests about 12–15 min, with a cache about 6–8 min. The budget is therefore enough for about 20–30 PR runs per month, if the heavy suite is run rarely.

### Workflow structure
- **`ci.yml`:**
  1. **`lint` (Linux, on every PR and main push):** SwiftLint and `swift-format --lint` (both work on Linux), **the Linux part of the license check** (L3: a `Package.resolved` denylist, `THIRD_PARTY_LICENSES` correspondence, and correspondence of the license-view data), CI greps (no `NSAllowsArbitraryLoads`, no legacy auth headers or `api_key`, no `print(` logging; 03-security.md), plus `Info.plist` and entitlements checks (**v1.3.2:** SwiftLint `custom_rules` require SourceKit and do not work in the Linux container, so security-related grep rules are implemented as a separate script in the same way as `check-debug-only-strings.py`, not as SwiftLint custom rules; print, dump, and NSLog rules skip only unit tests (`Tests/`), but `UITests/` is scanned on purpose, because UI tests run the real build and output can end up in CI logs (Security 22.10.2026); header, plist, and `.public` rules apply to every file; the plist also forbids `NSExceptionMinimumTLSVersion` of `TLSv1.0`/`TLSv1.1`; the plist also forbids `NSExceptionAllowsInsecureHTTPLoads`; header names are checked case-insensitively, and the contents of string interpolation `\( … )` are treated as code): the Keychain access group is only on the app and Top Shelf targets (S1.4), and `ApiKey` occurs only in `MediaURLBuilder` (S1.5). Also `swift build`/`swift test` for those GlassfinCore targets that do not depend on Apple frameworks (models, mappers, ticks conversions), if they can be made to build on Linux (⚠️ jellyfin-sdk-swift/NIOTransportServices Linux compatibility is unchecked; if it does not work, this item is left out).
  2. **`test-tvos` (`xcode-27`, `needs: lint`, path filter):** `swift test` for GlassfinCore and `xcodebuild test -scheme Glassfin-tvOS -destination 'platform=tvOS Simulator,name=Apple TV 4K (3rd generation)' CODE_SIGNING_ALLOWED=NO -only-testing:<unit + smoke>`.
  3. **`test-ios` (`xcode-27`, `needs: lint`, conditional per item 6):** `xcodebuild test -scheme Glassfin-iOS -destination 'platform=iOS Simulator,name=iPhone 17' CODE_SIGNING_ALLOWED=NO`. Unit tests run **for both platforms** (always on a main push).
  4. **`full-ui` (`xcode-27`, main push or the `full-ci` label):** every XCUITest, snapshots, `XCTMetric` tests, and **the binary part of the license check** (`otool -L`/`file`, MH_DYLIB, FFmpeg configuration; requires a macOS build, and activates when an FFmpeg/VLC binary is added).
  5. **Artifacts (v1.2, the Tester's request: everything readable on Linux without Xcode):**
     - `.xcresult`: retained for 7 days because of the 500 MB artifact-storage limit.
     - **JUnit XML** from every test job (`xcresultparser -o junit` or `xcrun xcresulttool` → a converter).
     - **Screenshots as PNG**: XCUITest attachments and failed ref/diff images from snapshot tests are exported from the xcresult (`xcrun xcresulttool export attachments`), with the test name as the filename.
     - **Coverage JSON**: `xcrun xccov view --report --json <xcresult>` → `coverage.json`.
     - **Logs of failed tests**: a text file per test (the failure message, the location, and the test's own logging).
     - Artifacts are uploaded in an `always()` step, including on a failed run. The naming convention is `<job>-<run_id>`, and retention is 7 days (small text artifacts 14 days).
     - **S5 redaction also applies to artifacts (03-security.md S5.5):** before upload, a Linux step scans every text artifact (JUnit, logs, coverage) for forbidden patterns (`ApiKey=`, `api_key=`, `Token="`, `Authorization:`, `Pw`, the integration-test credential value). A hit → the job fails, and the artifact is not uploaded. Screenshots use only mock or test credentials, and tokens are never shown in the UI.
     - The Tester reviews the artifacts on Linux.
  6. **Coverage:** GlassfinCore ≥ 80% line coverage (P0 modules); the UI layer is not mandatory.
- **`integration.yml`** (`workflow_dispatch`, before release, and with the PR label `integration`; not nightly during the private-repo period): GlassfinCore integration tests against a real Jellyfin server.
  - **PROPOSAL (v1.2, resolves SPEC.md §6 open decision 10 – ASSUMPTION – requires user confirmation): Jellyfin Docker containers as a GitHub Actions service on a Linux runner.** This does not consume macOS minutes.
    - A matrix of three versions, using **version tags** of the official `jellyfin/jellyfin` image (verified from Docker Hub on 21.10.2026): `10.10.7`, `10.11.11` (the latest 10.11.x), and `12.2`.
    - Tags are pinned to a digest (`image@sha256:…`) and updated with Dependabot. The `latest` and `unstable` tags are not used.
    - **Seed:** the job runs the first startup through the API. The calls are `POST /Startup/Configuration` and `POST /Startup/User`, then `POST /Startup/Complete`, `POST /Library/VirtualFolders` (Movies (fi: "Elokuvat"), Series (fi: "Sarjat"), Music (fi: "Musiikki")), and `POST /Library/Refresh` (every endpoint is in OpenAPI 12.2.0). Finally the job waits until the scan is finished.
    - **Test library:** small files generated in CI (`ffmpeg -f lavfi testsrc/sine`, 5–10 s). Includes H.264/AAC MP4, HEVC MKV, SRT and ASS subtitles, chapters, and a series layout `S01E01–E03`, plus CC0-licensed material as needed. The library is under 50 MB and cached. Copyrighted media is not stored in the repo.
    - The library also includes edge-case data: `RunTimeTicks` 0 and a device name that contains an emoji, a comma, and a quotation mark (M01 v1.2).
    - ⚠️ **Prerequisite: the part under integration test builds on Linux.** jellyfin-sdk-swift 3.3.0 declares only Apple platforms, its CI runs only on macOS, and it depends on the `swift-nio-transport-services` and `Get` packages (checked from `Package.swift` on 21.10.2026), so the Linux build is unverified.
    - If the Linux build does not work, the Linux job runs HTTP-level **contract tests** with the Linux-compatible part of `CoreNetworking` (header, redirects, 401 handling) or with a script. The same job saves response fixtures that the macOS unit tests use. The SDK-level integration test is then run rarely on macOS (manually, before release).
  - **Credentials are generated per run (v1.3.2, replacing v1.2's Secrets ruling):** the test server's admin and test-user passwords are drawn for every run (`openssl rand`), redacted from logs, and not stored in the repo, fixtures, the workflow file, or Secrets. The container is bound only to `127.0.0.1`, and the Jellyfin and Swift images are pinned by digest. `integration.yml` has `permissions: contents: read`.
    - Secrets are not available on fork PRs (a `pull_request` trigger from forks does not get secrets). The integration job is never run with `pull_request_target`.
    - Tokens and credentials do not end up in artifacts (artifact scan above).
  - Other options, if the user does not accept the proposal: (a) the user's own test server, whose URL and credentials are in Secrets; (c) a self-hosted Mac.
- **`release.yml` (later, TestFlight; requires a paid Apple Developer Program, SPEC.md §7):**
  - Signing and upload with an **App Store Connect API key**, stored **only as GitHub Actions secrets**: `ASC_KEY_ID`, `ASC_ISSUER_ID`, and `ASC_KEY_P8` (base64), preferably as secrets of a `production` environment with manual approval.
  - **The key is never attached to chat, issues, PR comments, logs, or the repo.** The user adds it themselves in the GitHub UI (Settings → Secrets and variables → Actions). In the workflow the key is written to a temporary file, which is deleted in an `always()` step, and it is not printed. GitHub masks secrets in logs, but base64-decoded content is not echoed.
  - In App Store Connect the key is given the smallest sufficient role (App Manager or Developer; ⚠️ the exact minimum role for a TestFlight upload is to be checked), and the key is rotated if it is suspected of having leaked.
  - Trigger: only `workflow_dispatch` or a `v*` tag from the main branch. Never from a `pull_request` event, so that secrets are not exposed to PR code.
- **Secrets in general:** no tokens, server URLs, or Apple keys in the repo. Only GitHub Secrets. Workflow `permissions:` is `contents: read` by default.
- **Dependency updates:** Dependabot/Renovate for SPM dependencies (Dependabot runs do not consume Actions minutes, but the CI runs they start do; group them into weekly PRs). **Updates of FFmpeg-based libraries are checked weekly** (Security: they parse untrusted media).

## Testability requirements (apply to every module)
- Every service is a protocol (`protocol XService`), and they are injected in the constructor or as an `Environment` value. Singletons are not used.
- The API client is mockable (the `JellyfinAPIClient` protocol, see 01-core.md). Tests use a `MockAPIClient` implementation that returns fixture JSON.
- The clock, network state, Keychain, and UserDefaults are abstracted (`Clock`, `NetworkMonitor`, `SecureStore`, `SettingsStore`), so that error cases can be simulated.
- Every view has an `accessibilityIdentifier` for XCUITest (naming convention `screen.element`, for example `home.continueWatching.item.0`).
- Launch arguments for UI tests: `-uitest-mock-server` (use the mocked API), `-uitest-reset` (clear state).
  - **Security (v1.3):** all handling of `-uitest-*` arguments, and the mock-server and `MockAPIClient` code, is behind `#if DEBUG`, and is not compiled into the release build. Otherwise a published app could be pointed at a fake server.
  - CI check: a release-configuration build is run, and the binary is verified (`strings`/`nm`) to contain no strings `uitest-` or `MockAPIClient`. A hit fails the job.

## Acceptance criteria
- [ ] An empty tvOS and iOS app and GlassfinCore build in CI in the repo `kallupx/glassfin`, and `ci.yml` is green.
- [ ] Savings measures 1–8 are in use: a change that is only `spec/**` does not start a macOS job, a new push cancels the old run, a cache hit is visible on the second run, and a lint error prevents macOS jobs (`needs`).
- [ ] ~~macOS-minute forecast~~ (removed, the repo is public). In its place: `concurrency` cancellation in every workflow, full-ui runs when ready for review and on a main push, artifact retention 14 days.
- [ ] Unit tests run on both the tvOS and the iOS simulator, and the results appear as a JUnit artifact.
- [ ] One XCUITest smoke test (the app launches and the first view is visible) produces a screenshot artifact.
- [ ] Lint blocks a merge when there are errors.
- [ ] The Tester confirms they can open the artifacts on Linux: JUnit XML, PNG screenshots (including snapshot diffs), `coverage.json` (`xccov --report --json`), and logs of failed tests. Artifacts are also uploaded from a failed run.
- [ ] The artifact scan (S5.5) blocks upload on a test branch where an `ApiKey=` string has been planted in a log.
- [ ] `integration.yml` (after the user's approval) starts the Jellyfin containers `10.10.7`, `10.11.11`, and `12.2`, seeds them, and runs the tests on Linux without macOS minutes. Credentials are generated per run, and the repo contains no credentials (grep/secret scan).
- [ ] `LICENSE` (MPL-2.0, after the user's confirmation) and `THIRD_PARTY_LICENSES` are in the repo.
- [ ] `license-check` fails on a test branch to which a forbidden dependency (for example kingslay/FFmpegKit) or an `--enable-gpl` build has been added, and passes on a clean main.

## Language and README (v1.3.3, the user's ruling on 22.10.2026)
- **Everything in the repo is in English:** code, identifiers, comments, doc comments, test names, log messages, commit messages, PR and issue titles and descriptions, ADRs, workflows, and the README. The team chat is in Finnish, but nothing in Finnish is committed. The exception is the UI's Finnish localization.
- **UI strings:** the development language is English (`Localizable.xcstrings`, String Catalog), and Finnish is a localization. The spec's Finnish UI strings (for example "Palvelinta ei löytynyt") are **Finnish translations**. The Coder writes the English source string, and Finnish is added as a translation. Hardcoded user-visible strings are not allowed. ASSUMPTION: the first localizations are English and Finnish.
- **README:** short and in English (the user's request). One line is enough, "Glassfin – a Jellyfin client for tvOS and iOS", plus the note "This is a heavy work-in-progress project under active development. Not ready for use." and a license line (MPL-2.0). No install instructions, roadmap, or screenshots before TestFlight.
- **Check:** Finnish comments or strings in existing commits and code are fixed if there are any (history is not rewritten).
