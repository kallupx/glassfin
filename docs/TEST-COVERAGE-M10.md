# M10 PoC settings

This branch implements the minimal M10 tier: Sign out and the app version. The
scope follows SPEC.md section 3a on `origin/spec/poc-tier-followup`, M04 Q4-12,
and the repository's canonical `spec/TESTPLAN-PoC-ACCEPTANCE.md` J8. There is no
dedicated TESTPLAN-M10.md. The base branch and the external specification copy
still contain the full MVP description; this change does not replace those files.

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

Verified on Linux: the coverage gate passed with 343 tests, 5 skipped integration
tests, no failures, and 92.46% line coverage (6637/7178 lines). Strict swift-format,
the design-system check, String Catalog validation, the DEBUG-only string check,
and ci-grep passed. The skipped tests require an external integration server.

## tvOS simulator verification

On a Mac with the project's Xcode and a tvOS 26+ simulator:

```sh
xcodegen generate
xcodebuild test -scheme Glassfin-tvOS \
  -destination 'platform=tvOS Simulator,name=Apple TV 4K (3rd generation)' \
  -only-testing:Glassfin-tvOSTests/T10SettingsLogicTests \
  -only-testing:Glassfin-tvOSUITests/T10SettingsUITests \
  -only-testing:Glassfin-tvOSUITests/T04AuthUITests/testT04_68_settingsSignOutDefaultsToCancelAndKeepsServer \
  CODE_SIGNING_ALLOWED=NO
```

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
- The base/external SPEC.md copies omit the PoC section. This branch follows
  the explicit minimal M10 scope in the canonical PoC acceptance plan and the
  pending PoC specification branch instead of introducing inactive MVP controls.
