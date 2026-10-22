# M00 – Infra, repository, and macOS CI (P0)

**Dependencies:** none (done first). **Owner:** Coder. **Reviewers:** Tester, Security.

## Why
The Tester has only a Linux machine. Xcode, the tvOS simulator, and XCUITest run only on macOS, so **all of that testing runs in CI on a macOS runner**. The Tester reads the results from artifacts (JUnit, xcresult text export, screenshots).

## Repository
- **Resolved (21 Oct 2026): GitHub repository `kallupx/glassfin`.** It can later move to an organization. The original plan was to make it public at release. **As of 22 Oct 2026 the repository is public** (see [Public repo (v1.3.3)](#public-repo-v133)). M00 has no remaining blockers.
  - Organization transfer: GitHub redirects old URLs, but Actions secrets, branch-protection rules, and any GitHub App installations must be checked after the move. Workflows do not hard-code the owner (`${{ github.repository }}`).
  - On a public repository, minutes for standard GitHub-hosted runners are free (see costs below), and the private-repo CI limits can be relaxed. v1.3.3 does that.
- The application name is **Glassfin** (tvOS and iOS). The proposed bundle ID is `org.glassfin.app` (placeholder, SPEC.md §6.13).
- **An Apple Developer account is not a prerequisite for M00:** CI builds and tests on the simulator without signing (`CODE_SIGNING_ALLOWED=NO`, no Apple account). Installing on a personal device works with a free Apple ID (Personal Team, 7-day provisioning). A paid membership is required only before TestFlight (SPEC.md §7).
- Layout:
  ```
  /Packages/GlassfinCore   # Swift package, shared by tvOS + iOS (M01–M02; "GlassfinCore" in the spec)
  /Apps/tvOS               # Glassfin tvOS app target, UI (primary)
  /Apps/iOS                # Glassfin iOS app target, built from day 1 (UI is a stub at first, M11)
  /Tests/Fixtures          # JSON fixtures from real Jellyfin responses (12.x and 10.10/10.11)
  /Tests/Media             # test-media matrix (see 08-playback.md), downloaded, not stored in the repo
  /spec                    # this specification
  ```
- Xcode project generation: XcodeGen or Tuist (the Coder chooses, so the project file does not cause merge conflicts). This is a recommendation, not a requirement.
- Swift 6 language mode and strict concurrency `complete`.
- **Open source:** the user's decision on 21 Oct 2026 is that the app is free and open source. The repository was private during early development and is public from 22 Oct 2026. License files are present from the start so publication does not need follow-up work.
  - The root contains `LICENSE` (**MPL-2.0 – PROPOSAL – needs the user's confirmation**, see SPEC.md §7 R9) and `THIRD_PARTY_LICENSES` (L4): every dependency, its version, its license, and a source link. Binary libraries (FFmpeg, VLCKit, MPV) get a link or tarball of the exact matching source plus the build configuration (configure line and any `changes.diff`).
  - Files copied from Swiftfin keep their MPL-2.0 headers and copyright notices.

## CI requirements (GitHub Actions)
- Verified 21 Oct 2026:
  - GitHub's `xcode-27` runner label is generally available from 15 Oct 2026 (Apple Silicon). It includes the tvOS 27.0/27.2 and iOS 27 SDKs and the simulators "Apple TV 4K (3rd generation)" and "(at 1080p)".
  - The `macos-26` image has Xcode 26.6 and tvOS 26.x simulators.
  - **Use only standard labels** (`xcode-27`, `macos-26`). **Do not use the `xcode-27-xlarge` label.** Larger runners are not included in free minutes even on public repositories. Self-hosted runners are also forbidden (v1.3.3).

### Cost limits (private repo)
These limits applied while the repository was private. The [public-repo rules](#public-repo-v133) supersede job selection and artifact retention. The prohibition on larger and self-hosted runners still applies.

- Verified from GitHub Docs on 21 Oct 2026:
  - A GitHub Free account includes **2,000 Actions minutes per month** for private repositories.
  - A standard macOS runner costs $0.062/min and a 2-core Linux runner $0.006/min, so **macOS consumes minutes at about 10x**. In practice the budget is **about 200 macOS minutes per month**.
  - Minutes are rounded up per job.
  - Without a payment method, usage stops when the quota is exhausted.
  - On public repositories, standard runners are free.
- **Required savings while the repository is private:**
  1. **Triggers:** `pull_request` (targeting `main`) and `push` to `main`. **No** pushes of feature branches, **no** scheduled macOS runs by default. `workflow_dispatch` is for manual runs.
  2. **Path filters:** macOS jobs run only when the change touches `Packages/**`, `Apps/**`, `Tests/**`, `*.xcodeproj` / `project.yml` / `Project.swift`, `Package.resolved`, or `.github/workflows/**`. Changes that are only `spec/**`, `*.md`, or `docs/**` do not start macOS jobs.
  3. **Concurrency:** `concurrency: { group: ${{ github.workflow }}-${{ github.ref }}, cancel-in-progress: true }`. A new push to the same pull request cancels the previous run.
  4. **Caches:** `actions/cache` for SPM (`~/Library/Caches/org.swift.swiftpm`, `.build`, keyed by the `Package.resolved` hash) and for DerivedData (keyed by the Xcode version, `Package.resolved`, and the project-file hash). Remember the 10 GB/repo cache limit: old keys are evicted.
  5. **A fast Linux job first** (`runs-on: ubuntu-latest`, about 1x price). macOS jobs depend on it (`needs: lint`), so a lint or license failure does not spend macOS minutes.
  6. **Light macOS trunk on pull requests:** a pull request runs GlassfinCore tests (`swift test`) plus tvOS unit and UI smoke tests in one macOS job (one simulator boot). **iOS tests run on a pull request only when the change touches `Apps/iOS/**` or `Packages/**`, and always on a push to main.** The heavy UI suite (all XCUITests and snapshots at 1080p/4K plus accessibility variants) and `XCTMetric` performance tests run **on push to main and with the pull-request label `full-ci`**, not on every pull-request push.
  7. **Minimum-version tvOS 26 smoke** (`macos-26`): manual, and before a release or TestFlight, not daily (a daily run would by itself use a large share of the budget).
  8. **Timeouts:** `timeout-minutes` per job (macOS 25 min, Linux 10 min), so a stuck simulator does not burn the budget.
  9. **Budget watch:** GitHub Billing → Budgets: an Actions budget of $0 and "Stop usage when budget limit is reached" (set by the user), so there are no surprise bills. The Coder watches usage (Settings → Billing → Usage). If 200 minutes is not enough, the options are (a) the user's own Mac as a self-hosted runner (free in minutes; security: private repository only, no fork pull-request runs), (b) GitHub Pro (3,000 min ≈ 300 macOS min), or (c) making the repository public earlier.
- Estimate (DEFAULT, measure on the first runs): a cold tvOS build and tests about 12–15 min, with cache about 6–8 min. The budget then covers about 20–30 pull-request runs per month if the heavy suite runs rarely.

### Public repo (v1.3.3)
The repository `kallupx/glassfin` is public as of 22 Oct 2026. Standard GitHub-hosted runner minutes are free. This section is the CI that ships. Where it differs from [Cost limits (private repo)](#cost-limits-private-repo), this section wins.

- **Runners.** Jobs use only `ubuntu-latest` or `xcode-27`. `xcode-27` is a standard GitHub-hosted label, not a self-hosted runner. **Self-hosted runners and any `-xlarge` label are forbidden.** `scripts/ci-grep.sh` fails the lint job if `.github/workflows` contains `self-hosted` or `xlarge`.
- **Concurrency on every workflow** (`ci.yml`, `integration.yml`, `release.yml`):
  ```yaml
  concurrency:
    group: ${{ github.workflow }}-${{ github.ref }}
    cancel-in-progress: true
  ```
  A new push to the same ref cancels the in-progress run of that workflow.
- **`ci.yml` triggers.** `pull_request` types `opened`, `synchronize`, `reopened`, `labeled`, and `ready_for_review`, branches `[main]`. Also `push` to `main`, and `workflow_dispatch`. `labeled` lets the `full-ci` label start macOS on a Dependabot pull request. `ready_for_review` starts `full-ui` when a draft becomes ready. A `synchronize` event on a pull request that is already ready also starts `full-ui`.
- **Draft pull requests** run `lint`, `test-tvos`, and `test-ios`. They do not run `full-ui` unless the pull request has the `full-ci` label or the event is `workflow_dispatch`.
- **`test-tvos` and `test-ios` share one gate.** Both run when lint succeeded, the event is `pull_request` or `workflow_dispatch`, and either the macOS path output is true or the event is `workflow_dispatch`. Push to `main` does not run them. Dependabot skips both until the pull request has `full-ci` or the event is `workflow_dispatch`. The macOS path prefixes are `Packages/`, `Apps/`, `Tests/`, `project.yml`, and `.github/workflows/`. A tvOS-only change still runs `test-ios`. The narrower "iOS only when `Apps/iOS` or `Packages` change" rule from the private-repo section does not apply.
- **`full-ui`** runs when lint succeeded and the event is `workflow_dispatch`, a push to `main`, or a `pull_request` that is not a draft. A draft runs it when it has the `full-ci` label. The path filter does not gate `full-ui`, so a ready pull request runs it even when the diff is workflows or docs. Dependabot does not run it unless the event is `workflow_dispatch` or `push`, or the pull request has `full-ci`.
- **`dependabot-macos`** always reports after a successful lint. Human pull requests pass. A Dependabot pull request fails until it has `full-ci` and at least one of `test-tvos` and `test-ios` succeeded. Do not enable auto-merge on lint alone.
- **Artifacts.** `tvos-results`, `ios-results`, and `full-ui-results` use `retention-days: 14`. xcresult bundles are not uploaded. macOS jobs upload the redacted text export only (logs and readable text under `artifacts/`).
- **What stays from the private-repo list.** Path filters still skip `test-tvos` and `test-ios` for a spec-only diff. Linux lint still runs first (`needs: lint`). Caches, timeouts (macOS 25 min, Linux lint 10 min, integration 40 min), and `permissions: contents: read` stay. A spec-only push on a **ready** pull request still starts `full-ui`, because that job is not path-filtered.

### Workflow structure
- **`ci.yml`:**
  1. **`lint` (Linux, every pull request and every push to main):** SwiftLint and `swift-format --lint` (both run on Linux), the **Linux part of the license check** (L3: `Package.resolved` denylist, `THIRD_PARTY_LICENSES` correspondence, and license-screen data correspondence), CI greps (no `NSAllowsArbitraryLoads`, no legacy auth headers or `api_key`, no `print(` logging; 03-security.md), plus `Info.plist` and entitlements checks. Also `swift build` / `swift test` for GlassfinCore targets that do not depend on Apple frameworks (models, mappers, ticks conversion), when they build on Linux. The Linux lint container is `swift:6.4` pinned by digest. SwiftLint 0.65.1 is pinned by sha256.
  2. **`test-tvos` (`xcode-27`, `needs: lint`, public-repo gate above):** `bash scripts/macos-ci.sh tvOS`.
  3. **`test-ios` (`xcode-27`, `needs: lint`, same gate as `test-tvos`):** `bash scripts/macos-ci.sh iOS`.
  4. **`full-ui` (`xcode-27`, ready pull request, push to main, `workflow_dispatch`, or a draft labeled `full-ci`):** `bash scripts/macos-ci.sh tvOS`, including the UI suite that script runs on that destination.
  5. **Artifacts:** redacted text under `artifacts/` (retention 14 days). The Tester reviews them on Linux. xcresult bundles stay on the runner.
  6. **Coverage:** GlassfinCore line coverage ≥ 80% (P0 modules). The UI layer is not required. The gate runs in the Linux lint job.
- **`integration.yml`** (`workflow_dispatch` only): GlassfinCore integration tests against real Jellyfin servers. The job is `docker-matrix` on `ubuntu-latest` (timeout 40 min). It runs `scripts/docker-integration.sh` (T01-20 and T01-30) against pinned `jellyfin/jellyfin` images `10.10.7`, `10.11.11`, and `12.2`. Credentials are generated per run. It does not run on `pull_request`.
- **`release.yml` (later, TestFlight; requires a paid Apple Developer Program membership, SPEC.md §7):**
  - Signing and upload with an **App Store Connect API key**, stored **only as GitHub Actions secrets**: `ASC_KEY_ID`, `ASC_ISSUER_ID`, and `ASC_KEY_P8` (base64), preferably as secrets of a `production` environment with manual approval.
  - **The key is never pasted into chat, issues, pull-request comments, logs, or the repository.** The user adds it in the GitHub UI (Settings → Secrets and variables → Actions). The workflow writes the key to a temporary file that an `always()` step deletes, and it does not print the key. GitHub masks secrets in logs, but the base64-decoded contents are not echoed.
  - In App Store Connect the key gets the smallest sufficient role (App Manager or Developer; the exact minimum role for TestFlight upload is still to be checked), and the key is rotated if it is suspected of leaking.
  - Trigger: only `workflow_dispatch` or a `v*` tag from `main`. Never from `pull_request`, so secrets are not exposed to pull-request code. The workflow also has the concurrency block above.
- **Secrets in general:** no tokens, server URLs, or Apple keys in the repository. GitHub Secrets only. Workflow `permissions:` default to `contents: read`. `ci.yml` also has `pull-requests: read` so the path filter can list pull-request files.
- **Dependency updates:** Dependabot for SPM dependencies. Dependabot runs do not consume Actions minutes, but the CI they start does. Group them into weekly pull requests. **Updates of FFmpeg-based libraries are checked weekly** (Security: they parse untrusted media). Dependabot pull requests do not run macOS until `full-ci` or `workflow_dispatch`.

## Testability requirements (every module)
- Every service is a protocol (`protocol XService`), injected in the constructor or as an `Environment` value. No singletons.
- The API client is mockable (`JellyfinAPIClient`, see 01-core.md). Tests use a `MockAPIClient` that returns fixture JSON.
- Clock, network status, Keychain, and UserDefaults are abstracted (`Clock`, `NetworkMonitor`, `SecureStore`, `SettingsStore`) so error cases can be simulated.
- Every view has an `accessibilityIdentifier` for XCUITest (naming `screen.element`, for example `home.continueWatching.item.0`).
- Launch arguments for UI tests: `-uitest-mock-server` (use the mocked API), `-uitest-reset` (clear state).

## Acceptance criteria
- [ ] An empty tvOS app, an empty iOS app, and GlassfinCore build in CI in `kallupx/glassfin`, and `ci.yml` is green.
- [ ] Public-repo rules are in effect: every workflow has `cancel-in-progress: true`; a draft runs `lint`, `test-tvos`, and `test-ios` when the macOS path filter matches; `full-ui` runs on a ready pull request and on push to `main`; `full-ci` still runs `full-ui` on a draft; every artifact has `retention-days: 14`; `ci-grep` rejects `self-hosted` and `xlarge`.
- [ ] A new push cancels the previous run. A lint failure blocks macOS jobs (`needs`). A second run shows a cache hit.
- [ ] On a draft, a spec-only diff does not start `test-tvos`, `test-ios`, or `full-ui`. On a ready pull request, a spec-only diff starts `full-ui` and does not start `test-tvos` or `test-ios` unless the pull request also changes a macOS path.
- [ ] Unit tests run on both the tvOS and iOS simulators when the macOS path filter matches, and the results are in the text artifacts.
- [ ] One XCUITest smoke test (the app launches and the first view is visible) produces a screenshot artifact.
- [ ] Lint blocks a merge when there are errors.
- [ ] The Tester confirms the artifacts open on Linux.
- [ ] `LICENSE` (MPL-2.0, after the user confirms) and `THIRD_PARTY_LICENSES` are in the repository.
- [ ] `license-check` fails on a test branch that adds a forbidden dependency (for example kingslay/FFmpegKit) or an `--enable-gpl` build, and passes on a clean main.
