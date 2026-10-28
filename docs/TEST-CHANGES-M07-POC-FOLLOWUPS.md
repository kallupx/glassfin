# M07 PoC follow-up test changes

Date: 2026-10-28. Branch: `test/poc-m07-followups`. PR: #32.

## Base merge compatibility

Merge the latest `origin/feat/m07-library-detail` (`45de3ec`) with a merge
commit. The merge resolves cleanly and retains both branches' tests.

The first Linux build exposed a protocol conformance error in
`Packages/GlassfinCore/Tests/CoreServicesTests/T07FilterEncodingTests.swift`.
The merged `RequestTransport` protocol requires `data(for:maximumBytes:)`.
Update only `T07FilterTransport.data`'s signature to accept `maximumBytes`.
Its recording behavior, fixture response, and all existing assertions are
unchanged. The service's request has no response byte limit, so the fixture
transport does not need to apply one.

## Existing PR-local test inventory

The original PoC follow-up commit adds these files:

- `Packages/GlassfinCore/Tests/CoreModelsTests/T07TechnicalRowTests.swift`:
  T07-32, T07-33, and T07-36 check default video/audio stream labels and
  first-media-source selection.
- `Packages/GlassfinCore/Tests/CoreServicesTests/T07FilterEncodingTests.swift`:
  T07-79 checks special-character genre query encoding through a recording
  HTTP transport.
- `Packages/GlassfinCore/Tests/CoreStateTests/T07PoCFollowupTests.swift`:
  T07-34 checks stable, deduplicated subtitle languages without downloads;
  T07-41 uses a gated fake client to prove concurrent item/seasons loading.

The fixtures are `Tests/Fixtures/m07-technical-items.json` and
`Tests/Fixtures/m07-subtitles.json`. Inherited test changes come from the
base merge; this follow-up does not edit their assertions, expectations,
timeouts, skip conditions, or test targets.

## Missing-pin factory regression

Add `PinFailureTests.testFeatureClientWithMissingPinAllowsClientCreation` in
`Packages/GlassfinCore/Tests/CoreStateTests/PinFailureTests.swift` as a separate
commit after the base merge and transport compatibility fix.

The test mirrors M09's
`testSearchFactoryWithMissingPinAllowsClientCreation`: sign in through the
in-memory harness, use an empty `SettingsCertificatePinStore`, and construct
the production factory. It explicitly checks that no pin is stored,
`makeFeatureClient()` succeeds, the backend request recorder remains empty,
and the session stays signed in. It invokes no client request and contacts
no server. M07's factory has no client override parameter; the recorder is
injected through `LiveAuthBackend` to catch unexpected authentication calls.

The change is additive. Every existing test method, assertion, expectation,
timeout, skip condition, helper, and target in `PinFailureTests.swift` is
unchanged. The only other test-file edit in this task is the transport
signature update documented above. No production or UI string changes are
needed for the missing-pin case.

## Validation

- Linux Swift 6.4.1, `swift test --package-path Packages/GlassfinCore`:
  655 tests total, 645 passed, 10 existing live-integration skips, zero failures.
  Before the missing-pin addition, the merged suite ran 654 tests with the
  same 10 skips and zero failures.
- Focused `PinFailureTests`: all 11 tests pass, including the new M07 case
  and the unchanged M09 missing-pin reference.
- `bash scripts/coverage-gate.sh`: the same 655 tests pass; source line
  coverage is 91.95% (10,149 / 11,038), above the 80% threshold.
- SwiftLint 0.65.1, strict recursive `swift-format`, `scripts/ci-grep.sh`,
  unit-test target checks, and `git diff --check` pass.
- A byte comparison confirms that removing the newly added method leaves
  `PinFailureTests.swift` identical to its pre-addition version. The filter
  test differs from its original PR version only in the transport signature.

Tests use in-memory stores, fake clients, and fixture responses. Live
integration tests remain skipped unless the Docker test harness enables them.
Apple builds and simulator tests run only in GitHub Actions; no Apple or
Docker integration results are claimed by these Linux checks.
