# Live playback regression tests

New test files:

- `Packages/GlassfinCore/Tests/CorePlaybackTests/LivePlaybackRegressionTests.swift`
- `Packages/GlassfinCore/Tests/CorePlaybackTests/PlayerFailureDiagnosticTests.swift`
- `Packages/GlassfinCore/Tests/CorePlaybackTests/HLSAssetRecognitionTests.swift`
- `scripts/ci/test_playback_diagnostics.py`

The tests cover Jellyfin 10.11's slash-relative `TranscodingUrl` shape with synthetic
identifiers and credentials. They require a visible `.m3u8` extension on both master
and rewritten variant asset URLs, preserve the negotiated query and reverse proxy
base path, and verify that playlist authentication uses the separate server query
without an Authorization header. Key and progressive URL round trips are controls.

Existing test files changed:

- `Apps/Shared/UITests/T06HomeUITests.swift`
- `Apps/Shared/UITests/T08PlaybackWiringUITests.swift`

Only their `element` selector helpers change: requests for the native player's old
`home.playback` identifier now resolve to `playback.native`. The app's active player
was using the retired placeholder's identifier, causing PR #47's unchanged guard
to reject successful playback. Every existing assertion line and its intended
element remains unchanged. No test assertion is weakened, deleted or edited.
PR #47's files and assertions are not changed or included in the fix PR.

Diagnostic tests check exact domain/code-only output, unknown-domain redaction,
missing errors, and a bounded underlying error chain. No server is contacted.
Python tests verify that the e2e collector emits only the controlled summary,
discarding timestamps, process metadata, URLs, queries and unstructured lines,
including when a simulator log-store failure requires the host log-store fallback.

The Apple-only recognition test opens a real AVPlayer with the wrapped master and
requires a variant request to reach an in-memory mock origin. The mock returns
404 for the variant and never offers segment URLs, so no server is contacted.
