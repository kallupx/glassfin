# Glassfin

Jellyfin client for tvOS and iOS. Swift 6, SwiftUI. M00 is the repository, project, and CI. M01 is the `GlassfinCore` package (networking, auth header, services, models). Later milestones are not implemented.

Bundle identifier: `org.glassfin.app`. Top Shelf: `org.glassfin.app.topshelf`. License: MPL-2.0 (`LICENSE`, `THIRD_PARTY_LICENSES`).

## Layout

- `Packages/GlassfinCore` — shared package. `CoreAPI` links jellyfin-sdk-swift only on Apple platforms.
- `Apps/tvOS`, `Apps/iOS` — stub apps. The iOS target compiles from day one.
- `Apps/TopShelf` — Top Shelf extension sources and entitlements. It is built, not embedded, so CI can compile it without signing.
- `project.yml` — XcodeGen project. The `.xcodeproj` is generated and not committed.
- `Tests/Fixtures` — Jellyfin JSON fixtures. `Tests/Media` does not contain media files.
- `spec` — milestone specs.

## Test locally (Linux)

Swift 6.2+ is required (`swift-tools-version: 6.2`).

```bash
cd Packages/GlassfinCore
swift test
bash ../../scripts/license-check.sh --self-test
bash ../../scripts/license-check.sh
bash ../../scripts/ci-grep.sh
bash ../../scripts/check-entitlements.sh
python3 ../../scripts/check-debug-only-strings.py --self-test
python3 ../../scripts/check-debug-only-strings.py
python3 ../../scripts/check-forbidden-calls.py --self-test
python3 ../../scripts/check-forbidden-calls.py
swift-format lint --recursive --strict Package.swift Sources Tests ../../Apps
```

`swift test` on Linux does not link jellyfin-sdk-swift. NIOTransportServices needs Network.framework. Header construction, redaction, redirects, ticks, backoff, and the HTTP client are still covered. `CoreAPI`'s SDK wrapper compiles on the macOS CI job.

Release check (T00-19), local stand-in:

```bash
cd Packages/GlassfinCore
swift build -c release
# The Release objects must not contain uitest- or MockAPIClient.
```

The macOS jobs run `scripts/check-release-binary.sh` on the Release `.app` executable with `strings` and `nm`. That check is part of `test-tvos` and `test-ios`. It is not a separate macOS job. The mock client type is `MockAPIClient`, and its source file is not named that, so the filename cannot leak into the Release binary. `-uitest-mock-server`, `-uitest-reset`, and `MockAPIClient` exist only inside `#if DEBUG` (or in UI-test sources, which are a separate bundle and are not scanned).

## CI

`.github/workflows/ci.yml` runs on pull requests to `main`, pushes to `main`, and `workflow_dispatch`.

- `lint` (Ubuntu, 10 minutes) runs first and gates GlassfinCore line coverage at 80% (T01-19). macOS jobs `needs: lint`.
- `test-tvos` and `test-ios` (`xcode-27`, 25 minutes) run on draft and ready pull requests, and on `workflow_dispatch`, when code, the project, or workflows change. They do not run on push. A spec-only change stays on Linux. Dependabot skips macOS until the `full-ci` label or `workflow_dispatch`. A grouped dependency pull request needs a green macOS build before merge. See `CONTRIBUTING.md`.
- `full-ui` runs on push to `main`, on a pull request that is ready for review, on `workflow_dispatch`, and on a draft labeled `full-ci`. Runners stay on the standard `xcode-27` label.
- Artifacts are kept for 14 days: JUnit XML, failed-test text, coverage JSON, screenshots, and the xcresult text export. Text artifacts are redacted before upload. xcresult bundles are not uploaded.
- `integration.yml` is `workflow_dispatch` only. `scripts/docker-integration.sh` runs T01-20 and T01-30 against jellyfin 10.10.7, 10.11.11, and 12.2.
- `release.yml` is `workflow_dispatch` or a `v*` tag. It has no `pull_request` trigger. The App Store Connect key is written to a temp file and removed with `if: always()`. Upload is not implemented.

UI tests launch with `-uitest-mock-server` and `-uitest-reset`. Those arguments are read only in debug builds.

## Acceptance coverage

M00: T00-01 through T00-19, including the Release binary string check (T00-19).
M01: T01-01 through T01-20, plus T01-21 through T01-27 (redirects, ApiKey scope, log redaction, entitlements, CR/LF rejection, percent-encoding, artifact redaction).

Live server tests (T01-20) are skipped until the Docker follow-up. See `Tests/IntegrationTests`.
