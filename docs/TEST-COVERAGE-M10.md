# M10 PoC settings

This branch implements the minimal M10 tier: Sign out and the app version. The
scope follows `spec/SPEC.md` section 3a, M04 Q4-12,
and the repository's canonical `spec/TESTPLAN-PoC-ACCEPTANCE.md` J8. There is no
dedicated TESTPLAN-M10.md. `spec/10-settings.md` still describes the full MVP;
this change does not replace that file.

Settings uses a shared observable view model and the M05 spacing, typography,
system focus, and glass button styles. Local content reclaims AppState.currentView
on every appearance, including tab re-entry, and remains available offline.
Cancelling confirmation returns to Settings. Confirmed sign-out uses the existing
M04 AuthFlow, LiveAuthBackend, and CredentialVault path; repeated Select presses
send one logout request. Cancel and Menu cannot reverse a confirmed request while
it is in flight. Network, timeout, and server failures still clear the local token
and show M04's localized warning that the server session may remain valid.

All new UI copy is in the app String Catalog with English and Finnish entries.
The version uses CFBundleShortVersionString, with a localized unavailable message
if that metadata is absent. No credentials or server metadata are shown by Settings.
No dependencies, Info.plist files, project.yml, or workflows change.

## Automated test mapping

New XCTestCase classes use @MainActor on individual async test methods.

| Canonical ID | Tests added | Coverage and limits |
| --- | --- | --- |
| TPOC-42 | `T10SettingsTests.testTPOC_42_settingsReclaimsVisibleContentOfflineWithoutRequests` | Local version, absent metadata, offline access without requests, tab re-entry, and departed-screen ownership |
| TPOC-42 | `T10SettingsLogicTests.testTPOC_42_versionMatchesTheAppBundleAndCatalogFormatsBothLanguages` | Hosted app bundle version and compiled English/Finnish catalog formats; requires Apple SDKs |
| TPOC-42 | `T10SettingsUITests.testTPOC_42_settingsContainsOnlySignOutAndVersion` | Minimal screen contents and screenshot attachment |
| TPOC-43 | `T10SettingsTests.testTPOC_43_cancelAndMenuKeepCredentialsWithoutLogoutRequest` | Cancel focus policy, Cancel/Menu actions, no API call, credentials retained |
| TPOC-43 | `T10SettingsUITests.testTPOC_43_cancelAndMenuReturnToSettingsWithFocus` | Actual tvOS Cancel focus on repeated entry, restored Settings focus, Menu, and tab navigation |
| TPOC-44 | `T10SettingsTests.testTPOC_44_confirmUsesM04LogoutAndClearsOnlyTheActiveCredential` | Production M04 adapter emits POST /Sessions/Logout through an injected transport; active token removed, other credential and server retained, no token in logs/preferences |
| TPOC-44 | `T10SettingsTests.testTPOC_44_failedLogoutStillClearsCredentialsAndShowsSafeNotice` | Network, timeout, and HTTP 500 failures clear the token and report the catalog notice |
| TPOC-44 | `T10SettingsTests.testTPOC_44_repeatedSelectSendsOneLogoutAndCannotCancelAfterConfirmation` | Suspended request verifies duplicate suppression and in-flight Cancel/Menu behavior |
| TPOC-44, TPOC-46 | `T10SettingsUITests.testTPOC_44_TPOC_46_confirmSignOutThenSignInWithPassword` | Mock UI journey to login on the retained server, then password sign-in to Home |
| TPOC-46 | `T10SettingsTests.testTPOC_46_passwordSignInAfterLogoutReturnsHome` | Production M04 password adapter with injected transport; new credential and Home phase |
| TPOC-47 | `T10SettingsTests.testTPOC_47_freshLaunchAfterLogoutKeepsServerWithoutRestoringSession` | New AppState/AuthFlow over retained stores; no /Users/Me call and no restored session |

The existing T04-68 UI test now expects Cancel to return to Settings. TPOC-45
requires a real server and Release app; it is not simulated by a unit assertion.
TPOC-46's server-side Continue watching/Next Up contents need the integrated M06
build, which is absent from this branch's base. TPOC-47's process relaunch with
actual Keychain/UserDefaults storage remains a simulator acceptance check.

## Linux verification

Run from the repository root:

```sh
export LD_LIBRARY_PATH=~/.local/lib/swiftcompat
source ~/.local/share/swiftly/env.sh
bash scripts/coverage-gate.sh
(cd Packages/GlassfinCore && swift-format lint --recursive --strict Package.swift Sources Tests ../../Apps)
python3 scripts/check-design-system.py
python3 scripts/check-string-catalogs.py
python3 scripts/check-debug-only-strings.py
bash scripts/ci-grep.sh
```

The coverage gate includes all seven new shared-core tests. Apple-hosted logic and
UI tests cannot execute on Linux.

Verified on Linux after merging main `d720120`, with M05 `d2d780b` already in
the branch's ancestry: the coverage gate passed with 436 tests, 7 skipped
integration tests, no failures, and 92.53% line coverage (7363/7957 lines). Strict swift-format,
the design-system check, String Catalog validation, the DEBUG-only string check,
and ci-grep passed. The skipped tests require an external integration server.

## CI run 40619479956 investigation

The [run at head 4c32988](https://github.com/kallupx/glassfin/actions/runs/40619479956)
passed lint, test-tvos, and full-ui. `gh run view 40619479956 -R kallupx/glassfin
--log-failed` returned no output because test-ios was cancelled, not marked failed.
The [test-ios job](https://github.com/kallupx/glassfin/actions/runs/40619479956/job/122590315082)
annotation explicitly states: "The job has exceeded the maximum execution time
of 25m0s". The step ran from 02:43:43 to 03:08:45 UTC; job cleanup ended at 03:09:16.

The [ios-results artifact](https://github.com/kallupx/glassfin/actions/runs/40619479956/artifacts/12788967506)
contains release-build.log, release-binary.txt, package-test.log, and app-test.log.
The Release binary scan and package tests passed. package-test.log records all
seven T10SettingsTests passing; app-test.log records the hosted
T10SettingsLogicTests test and all three T10SettingsUITests passing. The UI suite
nevertheless completed 17 tests with three failures before the job timed out,
so this was not solely an infrastructure
flake:

- T05-54 failed twice while looking for Search under the phone's native More tab.
  Merging M05 `da38a26` brings its compact-width limit of one inline library plus
  Libraries, leaving five native tabs total. Conflict resolution retains M10's
  existing Home/Search/Settings ordering and tvOS focus behavior.
- T04-03 found quickconnect.code, then lost it while reading its label. The failure
  snapshot already contains home.root. M04's DEBUG backend approves after two
  seconds, so the test races the transition to Home on this slow simulator.
  This is an M04 fixture/test synchronization issue outside M10's scope; its code
  and assertions remain unchanged.

The merge commits include main `45e21b4` (M04 squash `b0f0f22`, HLS auth `924888d`,
and spec updates) and M05 `da38a26`, followed by its newer tip `d2d780b`.
The newer M05 tip supplies the source-check exception for main's M04 glass and
background, which are restored while retaining M10's settings integration.
Main's workflows, project.yml, Info.plist
files, and M08 sources/tests are retained exactly. Existing M10 settings, sign-out
guards, catalog copy, and shared design-system integration are preserved. No new
test or assertion changes were needed. The pre-existing T04-68 adjustment remains:
Cancel returns to Settings, so it omits the Home assertion and reopening Settings.
Apple simulator verification of the merged head is still required; the timeout
and the M04 race are not claimed resolved by Linux checks.

## CI run 40627712719 investigation

The [run at head 4a076e7](https://github.com/kallupx/glassfin/actions/runs/40627712719)
passed lint, test-tvos, and full-ui. Its only failing job was
[test-ios](https://github.com/kallupx/glassfin/actions/runs/40627712719/job/122617041315).
The full job log from `gh api repos/kallupx/glassfin/actions/jobs/122617041315/logs
--allow-escape-sequences` and the uploaded
[ios-results artifact](https://github.com/kallupx/glassfin/actions/runs/40627712719/artifacts/12791533953)
identify one failing test, not a compile error or a job timeout:

- The Release build completed at 04:06:26 UTC and its binary scan passed.
  Package testing completed successfully at 04:10:38 UTC, including all seven
  T10SettingsTests. Seven external-server integration tests were skipped.
- app-test.log records 17 UI tests with one failure. All three M05 UI tests,
  all three T10SettingsUITests, and the settings sign-out test T04-68 passed.
- T04AuthUITests.testT04_03_quickConnectReachesHome failed at line 35 while
  reading `quickconnect.code.label`. Its elapsed test log finds the code at
  49.67 seconds and starts the label lookup at 50.72 seconds; the subsequent
  failure hierarchy already contains `home.root`. M04's DEBUG fixture approves
  after a fixed two-second sleep, independently of the test's code inspection.
- The app test command reports `TEST FAILED` at 04:20:57 UTC, and the script
  exits with code 65 at 04:21:08 UTC. The job ran from 04:03:09 to 04:21:16 UTC,
  below its 25-minute limit. This is a fixture synchronization race in upstream
  M04/main, not an M10 settings defect or a pure CI timeout.

The minimal upstream fix is confined to the DEBUG fixture in AuthRootView.swift
and the affected T04-03 UI test. An opt-in launch argument carries a unique Darwin
notification name. The fixture reads that name's state during normal Quick
Connect polling, holding approval until the runner has verified the code and
saved its screenshot. The runner then sets the state to approved, and the
existing polling and authentication path must reach Home. Each process releases
its registration. The unique name prevents approval from an earlier test run
from being reused. Apple's [notification API documentation](https://developer.apple.com/library/archive/documentation/System/Conceptual/ManPages_iPhoneOS/man3/notify.3.html)
describes this state API for synchronization between processes. The hook and its
Darwin import are DEBUG-only; no user-facing copy is added.

Test/assertion changes authored for this investigation:

- T04-03 registers its unique approval state and passes its name at launch, then
  signals approval after the existing code assertions and screenshot. This
  synchronization is required because the fixture could otherwise remove the
  code between the test's existence check and label lookup.
- Two new status assertions check notification registration and setting approval.
  Every existing assertion, screenshot, and timeout in T04-03 is retained.
- No M10 tests or assertions change. The requested main merge also imports
  upstream changes to ADRM08PrototypeTests.swift and
  PlaybackCoordinatorTests.swift exactly as supplied by `d720120`; no further
  playback test edits are authored here. The pre-existing T04-68 adjustment
  described above remains unchanged.

Main `d720120` was merged with `Merge main d720120 (stack base v6)`.
M05's remote tip remains `d2d780b`, already an ancestor, so no extra M05 merge
or fix is needed. Main's workflows, project.yml, and all Info.plist files are
retained exactly. Linux verification above passed after the merge and fixture
change. Linux cannot compile or execute the Apple-only fixture or UI test; a
green simulator rerun is still required.

On macOS, run `bash scripts/macos-ci.sh iOS` for the same Release, package-test,
and complete app-test checks as the failing job. For a focused regression run:

```sh
xcodegen generate
xcodebuild test -scheme Glassfin-iOS \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:Glassfin-iOSUITests/T04AuthUITests/testT04_03_quickConnectReachesHome \
  CODE_SIGNING_ALLOWED=NO
```

## CI run 40636959982 investigation

The [run at head 88acbdc](https://github.com/kallupx/glassfin/actions/runs/40636959982)
fails all three Apple jobs during compilation of the DEBUG app. Complete job logs
were downloaded through `gh api repos/kallupx/glassfin/actions/jobs/<id>/logs
--allow-escape-sequences`, rather than the truncated `gh run view --log-failed`
output:

| Job | Complete-log evidence (UTC) | Root cause |
| --- | --- | --- |
| [full-ui](https://github.com/kallupx/glassfin/actions/runs/40636959982/job/122646533906) | First error at 05:40:44; `TEST FAILED` at 05:40:44; exit 65 at 05:40:47 | Missing `notify` module import in AuthRootView.swift |
| [test-ios](https://github.com/kallupx/glassfin/actions/runs/40636959982/job/122646533921) | First error at 05:47:06; `TEST FAILED` at 05:47:06; exit 65 at 05:47:10 | Same missing import |
| [test-tvos](https://github.com/kallupx/glassfin/actions/runs/40636959982/job/122646533956) | First error at 05:45:20; `TEST FAILED` at 05:45:20; exit 65 at 05:45:26 | Same missing import |

Each job reports that `notify_register_check`, `notify_cancel`, `notify_get_state`,
and `NOTIFY_STATUS_OK` cannot be found at AuthRootView.swift lines 423, 427, and
433, then cancels testing because the build failed. Release builds and binary
scans passed, as did package tests, including all seven T10SettingsTests. No app
UI cases ran. None of the complete logs contains `Undefined symbols`,
`linker command failed`, a failed test case, or a job-timeout failure. These are
compile failures introduced by M10 CI commit `88acbdc`, not the M05 NIO link issue
and not pure CI flakes. The earlier Quick Connect timing race originated in
M04/main; the incorrect import in its synchronization fix belongs to M10.

Apple's [Libnotify module map](https://github.com/apple-oss-distributions/Libnotify/blob/main/notify.modulemap)
declares a separate `notify` module for notify.h. Replace `import Darwin` with
`import notify` in the DEBUG app fixture and its UI test. The test needs the same
import for registration, cancellation, setting approval, and the status constant;
its compilation was masked by the app failure. The approval protocol, existing
assertions, screenshots, and timeouts remain unchanged. The app import remains
inside `#if DEBUG`, so Release does not gain the fixture.

M09 [b7f8e86's run 40636754620](https://github.com/kallupx/glassfin/actions/runs/40636754620)
passed full-ui, test-ios, and test-tvos. Its
[tvOS log](https://github.com/kallupx/glassfin/actions/runs/40636754620/job/122645923067)
uses the same Swift 6.4 build `swiftlang-6.4.0.34.1` and Xcode 27.1 as M10, and
records T04-03 passing at 05:31:29 followed by `TEST SUCCEEDED`. Comparing sources
shows that M09 does not contain the notification synchronization added by
`88acbdc`; the green run therefore does not exercise this missing import.

After `git fetch origin`, main `d720120` was already an ancestor. M05 `79feaa0`
was merged with a merge commit. Its project.yml is taken verbatim, enabling the
hosted logic/snapshot targets from `b8c6349` while retaining `79feaa0`'s removal
of their duplicate GlassfinCore package dependency. The original failing M10
head had no hosted unit-test targets, so that M05 link regression was absent.
The merge also imports M05's ci-path-filter.py update verbatim so shared app and
project changes select iOS CI. No workflow or Info.plist changes are made.

Validation after the merge and import correction: 436 Linux package tests,
seven existing external-server skips, zero failures, and 92.53% line coverage
(7363/7957 lines). All requested strict swift-format, design-system, String
Catalog, DEBUG-only string, and ci-grep checks passed. project.yml matches M05
`79feaa0` exactly.

Test/assertion changes for this investigation: the import in T04AuthUITests.swift
must change to compile the existing notification calls. No test bodies,
assertions, screenshots, or timeouts are changed, added, or removed; no existing
test sources change through the M05 merge. Earlier T04-03 synchronization and
T04-68 changes documented above remain in place.

Linux cannot compile Apple's `notify` module, link the hosted bundles, or run
simulator tests. On macOS, run `bash scripts/macos-ci.sh iOS` and
`bash scripts/macos-ci.sh tvOS` for the same Release scans, package checks, and
complete app suites used by these jobs. A green Apple CI rerun remains required.

## tvOS simulator verification

On a Mac with the project's Xcode and a tvOS 26+ simulator:

```sh
xcodegen generate
xcodebuild test -scheme Glassfin-tvOS \
  -destination 'platform=tvOS Simulator,name=Apple TV 4K (3rd generation)' \
  -only-testing:Glassfin-tvOSUITests/T10SettingsUITests \
  -only-testing:Glassfin-tvOSUITests/T04AuthUITests/testT04_68_settingsSignOutDefaultsToCancelAndKeepsServer \
  CODE_SIGNING_ALLOWED=NO
```

The merged M05 project.yml defines Glassfin-tvOSUnitTests and
Glassfin-iOSUnitTests and includes them in the corresponding app schemes.
Their logic/snapshot sources, including T10SettingsLogicTests, run alongside
the UI tests when invoking the complete schemes.

The UI tests use the existing DEBUG-only M04 mock launch path and Siri Remote
helpers. Screenshot attachments show Settings, confirmation, and the sign-out /
sign-in results. They do not provide real-server acceptance evidence.

For acceptance, use the integrated PoC build with native macOS Jellyfin servers
10.10.7, 10.11.11, and 12.2 and the canonical J8 seed and instructions:

1. Sign in, navigate to Settings with the remote, and compare the version with
   the built app's CFBundleShortVersionString (TPOC-42).
2. Select Sign out. Verify Cancel is focused. Select Cancel, then repeat using
   Menu. Both return to Settings and retain the session (TPOC-43).
3. Confirm Sign out. Verify POST /Sessions/Logout, deletion of the active token,
   and login on the retained server (TPOC-44). On Release, check /Users/Me using
   the old token returns 401 without exposing the token in artifacts (TPOC-45).
4. Sign back in with a password and compare the server-side Home rows
   (TPOC-46). Sign out again, terminate, and relaunch: login must open without
   restoring a session (TPOC-47).
5. Repeat with the server unavailable: Settings still works, Cancel preserves
   credentials, and confirmed sign-out clears them with the offline warning.
6. Repeat in Finnish, with VoiceOver, Reduce Transparency, and Increase Contrast.
   Verify the remote can leave and re-enter Settings and that version text is
   readable and never takes focus. Apply the canonical artifact redaction rules.

## Known limits and TODOs

- Full P0 account details, playback preferences, subtitles, diagnostics, cache
  controls, About/source information, and the generated license view remain for
  full M10. They are outside the PoC's two-item placeholder; license acceptance
  remains required before the full MVP. No persistent settings are added here.
- This base has M04's Home placeholder; integration with the sibling Home shell
  must mount `SettingsView(flow:)` in its Settings slot and preserve tab selection
  across M04 confirmation. The model's appearance hooks handle screen ownership.
- Apple compilation, simulator focus checks, real Keychain checks, and server
  token revocation cannot be verified on this Linux host.

## Open questions

- QPOC-05 leaves version formatting open. This implementation conservatively
  displays the marketing version only, with a localized Version label; it adds
  neither a build number nor a commit SHA.
- QPOC-08 / Q4-12 leaves the post-sign-out target partly open. Existing M04
  behavior is retained: another saved user leads to the user picker; otherwise
  the login-method screen, or credentials when Quick Connect is disabled.
