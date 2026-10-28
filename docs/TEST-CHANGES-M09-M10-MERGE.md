# M09 merge of M10 Settings from main

Merge `origin/main` at `eaf26b5` (PR #28) into `feat/m09-search`, whose
pre-merge head is `36e09f6`, using a merge commit. Preserve M10 SettingsView,
the sign-out confirmation and isSigningOut guard, Settings focus restoration,
and the externally bound tab selection alongside M09 Search. The app catalog
retains every English/Finnish entry from both parents without changing values.

## Exact test-file changes relative to the pre-merge branch

No test edits were authored to resolve conflicts or make checks pass. The merge
imports these four upstream test-file changes:

| File | Change and rationale |
| --- | --- |
| `Apps/Shared/Tests/Logic/T10SettingsLogicTests.swift` | Added verbatim from main. Covers the app bundle version and English/Finnish catalog formatting for M10 Settings. |
| `Apps/Shared/UITests/T10SettingsUITests.swift` | Added verbatim from main. Covers Settings contents, Cancel/Menu focus restoration, and confirmed sign-out followed by sign-in. |
| `Packages/GlassfinCore/Tests/CoreStateTests/T10SettingsTests.swift` | Added verbatim from main. Seven tests cover offline Settings ownership, version fallback, Cancel/Menu, credential cleanup, logout failures, repeated confirmation, sign-in, and relaunch. |
| `Apps/Shared/UITests/T04AuthUITests.swift` | Automatically imports main's unconditional `notify` import and its existing T04-68 Cancel-to-Settings adaptation. Upstream removes the Home wait assertion and Settings reactivation after Cancel because Settings is now restored directly. This merge authors no assertion changes; it retains the branch's existing async test signatures and actor annotations. All test bodies match main. |

There are no other test-file changes relative to `36e09f6`. Existing M09 tests,
assertions, fixtures, timeout values, and skips are unchanged. No test signature
fix was needed for this merge. The three added files match main byte for byte;
the only T04 difference from main is the branch's pre-existing async signatures
and method-level MainActor annotations.

## Security and validation

HTTPClient and BoundedResponseDownload retain their per-transfer certificate
pinning and disabled URL cache. Both bounded download delegates retain their
per-chunk check before appending bytes. BoundedImageDownload now explicitly sets
`configuration.urlCache = nil` before creating its session, including when its
caller supplies a configuration with a cache. Its TrustCapture delegation and
the response budget remain unchanged.

Validation on Linux with Swift 6.4.1 and the existing Swift compatibility library:

- `bash scripts/coverage-gate.sh` runs GlassfinCore's `swift test`: 563 tests,
  10 existing opt-in live-server skips, zero failures (553 passed). All seven
  M10 Settings tests pass. Source line coverage is 91.69% (8919/9727), above 80%.
- SwiftLint 0.65.1 and recursive strict swift-format lint pass for the package
  and Apps.
- `scripts/ci-grep.sh` passes, including image-pipeline, design-system, M09,
  and both String Catalog checks.
- License checks and self-test, entitlements, DEBUG-only string checks and
  self-test, unit-test target checks and self-test, and artifact-redaction
  self-test pass.
- Bootstrap, HLS probe, and benchmark artifact scanner Python tests pass:
  42 tests, zero failures. Run with `PYTHONPATH=scripts python3 -m unittest
  scripts/test_jellyfin_bootstrap.py scripts/test_probe_hls_segment_auth.py
  scripts/test_scan_benchmark_artifacts.py`; the scanner uses a sibling import
  and needs that path when invoked from the repository root. The initial
  invocation without that import path failed to load the scanner suite; no
  source or test changes were needed.
- Integration/media shell syntax checks and Docker integration self-test pass.
- Both parent catalogs' entries and main's SettingsView, SettingsViewModel, and
  AuthRootView are verified unchanged; workflows, project.yml, and Info.plists
  match main. `git diff --check` passes.

Apple app builds, hosted logic tests, UI/focus tests, and live-server acceptance
cannot be run on this Linux host. Their passing status is not claimed.
