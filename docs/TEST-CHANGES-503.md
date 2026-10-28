# HTTP 503 startup state test changes

The MVP decision in spec 02 gives HTTP 503 its own startup state. All added tests use in-memory mocks; they do not contact a Jellyfin server.

## Added coverage

- `Packages/GlassfinCore/Tests/CoreStateTests/ServerStartingTests.swift`: checks anonymous, login and authenticated error mapping, including an offline path report; sends mock HTTP 503 with `Retry-After: 60`, HTML and a private `Message` header through each session client; verifies startup copy, manual retry, token retention and no automatic retries; verifies the connect probe stops on 503 and stores no accepted TOFU pin until a normal response; checks Quick Connect polling stops on startup.
- `Packages/GlassfinCore/Tests/CorePlaybackTests/ServerStartingPlaybackTests.swift`: checks item and PlaybackInfo startup failures, no automatic fallback, manual retry recovery, startup reporting without an automatic retry, and session retention.

## Existing assertions preserved

No existing test file or assertion has been changed. The following legacy expectations conflict with the new MVP decision and block a green full suite:

| Existing test | Conflicting 503 expectation |
| --- | --- |
| `T02FoundationTests.testT02_08_mappingNeverTurnsNon401IntoLogout` | Maps 503 to `serverUnreachable`. |
| `T02FoundationTests.testT02_16_idempotentGETRetriesBackoffAndSkipsTerminalStatuses` | Requires automatic GET retry for 503. |
| `T04AuthFlowTests.testT04_41_transientPollFailureDoesNotSignOut` | Waits for an automatic second poll after 503. |
| `T04AuthFlowTests.testT04_50_passwordAndQuickConnectUseDistinctNetworkAndServerErrorKeys` | Requires generic server copy for login and Quick Connect 503. |
| `T04AuthFlowTests.testT04_61_usersMeFailuresKeepTheToken` | Requires generic network copy for restored-session 503. |
| `T04AuthFlowTests.testT04_87_launchFailurePingsEveryTenSecondsRecoversAndLater401SignsOut` | Waits for an automatic outage ping after 503. |
| `T09RetryTests.testT09_60_gatewayFailuresRetryTwiceWithSharedBackoff` | Requires two automatic GET retries after 503. |
| `T09RetryTests.testT09_60_cancelledQueryDoesNotRetryAfterBackoff` | Waits for an automatic retry delay after 503. |
| `PlaybackCoordinatorTests.testT08P_30_transientRetryCanRecover` | Requires automatic playback report retries after 503. |

The full Linux `swift test` invocation was stopped after 60 seconds because a legacy test waits for a retry that MVP now forbids. A separate diagnostic run excludes only the nine conflicts above to check the remaining regressions. These exclusions are command-line diagnostics only; CI and the repository's test configuration are unchanged.

## Validation

- New startup tests: 9 passed, 0 failures.
- Diagnostic regression run excluding the nine conflicts: 682 discovered/executed, including 672 passed and 10 Docker integration tests skipped, 0 failures.
- Full suite: blocked by the preserved legacy expectations above; no passing full-suite or coverage result is claimed.
- String Catalog checks, source guards, `swift-format` and whitespace validation pass locally.
- Apple builds and tests are reserved for GitHub Actions.

Updating these obsolete expectations requires an explicit exception to the task's rule against changing existing assertions. This draft must not be merged while that conflict remains unresolved. Automatic `Retry-After` scheduling remains deferred to P1.
