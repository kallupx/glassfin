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

## Validation

Run `swift test --package-path Packages/GlassfinCore` on Linux before pushing.
Tests use in-memory stores, fake clients, and fixture responses. Live
integration tests remain skipped unless the Docker test harness enables them.
Apple builds and simulator tests run only in GitHub Actions.
