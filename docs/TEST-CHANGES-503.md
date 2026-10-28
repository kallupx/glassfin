# HTTP 503 startup state test changes

The MVP decision in spec 02 gives HTTP 503 its own startup state. All added tests use in-memory mocks; they do not contact a Jellyfin server.

## Added test files

- `Packages/GlassfinCore/Tests/CoreStateTests/ServerStartingTests.swift`: six tests cover API response classification in every authentication context, including an offline path report; mock HTTP 503 with `Retry-After: 60`, HTML and a private `Message` header through all three session clients; token retention and manual recovery; restored-session startup copy; connect probing without candidate fallback; accepted TOFU trust without pin persistence until a normal response; and Quick Connect polling without an automatic retry.
- `Packages/GlassfinCore/Tests/CorePlaybackTests/ServerStartingPlaybackTests.swift`: three tests cover item and PlaybackInfo startup failures, no automatic fallback, manual retry recovery, startup reporting without an automatic retry, and a current-user startup response after a media 401 without session expiry.

## Existing assertions preserved

No pre-existing test file or assertion is modified. Actual Jellyfin API responses use `HTTPStatusMapper.apiFailure(for:)`, which classifies HTTP 503 as `APIError.serverStarting` before decoding or retry handling. The generic HTTP/media mapper and explicitly constructed generic server errors retain their existing contracts. New transport mocks exercise actual HTTP 503 classification, including HTML and headers, instead of relying only on a manually constructed generic error.

Only the two new test files above are changed relative to main. The new tests' transport-error expectations use the dedicated API startup classification.

## Validation and scope

- New startup tests: 9 passed, 0 failures.
- Full Linux package suite: 691 executed, including 681 passed and 10 Docker integration tests skipped, 0 failures. No test filter or exclusion is used for this result.
- The repository's full-suite coverage gate passes at 91.89% line coverage (10,878 of 11,838 lines), above the 80% threshold.
- String Catalog checks, source guards, `swift-format` and whitespace validation pass locally.
- Apple builds and tests run only in GitHub Actions.
- Automatic `Retry-After` scheduling remains deferred to P1: clamp to 5–60 seconds, at most five attempts. MVP offers manual retry only.
