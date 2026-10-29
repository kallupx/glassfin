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

No existing test files or assertions are changed.

Diagnostic tests check exact domain/code-only output, unknown-domain redaction,
missing errors, and a bounded underlying error chain. No server is contacted.
Python tests verify that the e2e collector emits only the controlled summary,
discarding timestamps, process metadata, URLs, queries and unstructured lines.

The Apple-only recognition test opens a real AVPlayer with the wrapped master and
requires a variant request to reach an in-memory mock origin. The mock returns
404 for the variant and never offers segment URLs, so no server is contacted.
