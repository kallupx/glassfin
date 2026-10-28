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

Verified on Linux after merging main `45e21b4` and M05 `d2d780b`: the coverage
gate passed with 434 tests, 7 skipped integration tests, no failures, and 92.52%
line coverage (7352/7946 lines). Strict swift-format,
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

Main's project.yml does not define the hosted Glassfin-tvOSTests or
Glassfin-iOSTests targets. Their logic/snapshot test sources are retained, but
they will not run through the generated app schemes until M05's project setup is
integrated separately. No project changes are made here.

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
