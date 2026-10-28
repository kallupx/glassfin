# Refreshed MVP integration test audit

No test file is manually edited during the refresh. All imported test files and
assertions are retained byte-for-byte from their owning source heads. The M09
snapshot `self.verticalScroll(in:)` correction from the first canary is now
supplied by #46 itself. The recording transport correction is supplied by #32.
No assertion, timeout, reference, skip condition or test target is changed.

#47 adds two gated acceptance methods and their support client. No credentials
are supplied, so the methods skip in normal CI. No native or real Jellyfin server
is started; mocks or the repository Docker test server remain the only allowed
server paths for this canary.

The complete changed test/fixture inventory relative to main `085582b` follows.

| Change | File | Matching source head |
| --- | --- | --- |
| Added | `Apps/Shared/Tests/Logic/T07ArtworkTests.swift` | `942f4f0`, `dc7c296`, `190daf2` |
| Added | `Apps/Shared/Tests/Snapshots/T09SearchSnapshotTests.swift` | `a34000a` |
| Added | `Apps/Shared/UITests/PoCLiveServer.swift` | `af14624` |
| Added | `Apps/Shared/UITests/T07LibraryUITests.swift` | `942f4f0`, `dc7c296`, `190daf2` |
| Added | `Apps/Shared/UITests/T08PlaybackWiringUITests.swift` | `190daf2` |
| Added | `Apps/Shared/UITests/T09SearchMVPTests.swift` | `a34000a` |
| Modified | `Apps/Shared/UITests/T10SettingsUITests.swift` | `ff6c543` |
| Added | `Apps/Shared/UITests/TPOCPlaybackAcceptanceUITests.swift` | `af14624` |
| Modified | `Apps/Shared/UITests/UIInteraction.swift` | `ff6c543` |
| Added | `Packages/GlassfinCore/Tests/CoreModelsTests/T07MetadataTests.swift` | `942f4f0`, `dc7c296`, `190daf2` |
| Added | `Packages/GlassfinCore/Tests/CoreModelsTests/T07TechnicalRowTests.swift` | `dc7c296` |
| Added | `Packages/GlassfinCore/Tests/CoreModelsTests/T09MVPCardTests.swift` | `a34000a` |
| Added | `Packages/GlassfinCore/Tests/CoreNetworkingTests/T07ImageTests.swift` | `942f4f0`, `dc7c296`, `190daf2` |
| Added | `Packages/GlassfinCore/Tests/CorePlaybackTests/PlaybackFeatureTests.swift` | `ff6c543` |
| Added | `Packages/GlassfinCore/Tests/CorePlaybackTests/TrickplayImageDecoderTests.swift` | `ff6c543` |
| Added | `Packages/GlassfinCore/Tests/CoreServicesTests/T07FilterEncodingTests.swift` | `dc7c296` |
| Modified | `Packages/GlassfinCore/Tests/CoreStateTests/PinFailureTests.swift` | `dc7c296` |
| Modified | `Packages/GlassfinCore/Tests/CoreStateTests/Support.swift` | `942f4f0`, `dc7c296`, `190daf2` |
| Modified | `Packages/GlassfinCore/Tests/CoreStateTests/T02BehaviorTests.swift` | `942f4f0`, `dc7c296`, `190daf2` |
| Modified | `Packages/GlassfinCore/Tests/CoreStateTests/T02FoundationTests.swift` | `942f4f0`, `dc7c296`, `190daf2` |
| Modified | `Packages/GlassfinCore/Tests/CoreStateTests/T04AuthTests.swift` | `942f4f0`, `dc7c296`, `190daf2` |
| Added | `Packages/GlassfinCore/Tests/CoreStateTests/T07DetailTests.swift` | `942f4f0`, `dc7c296`, `190daf2` |
| Added | `Packages/GlassfinCore/Tests/CoreStateTests/T07LibraryTests.swift` | `942f4f0`, `dc7c296`, `190daf2` |
| Added | `Packages/GlassfinCore/Tests/CoreStateTests/T07PoCFollowupTests.swift` | `dc7c296` |
| Added | `Packages/GlassfinCore/Tests/CoreStateTests/T07ScreenLifecycleTests.swift` | `942f4f0`, `dc7c296`, `190daf2` |
| Added | `Packages/GlassfinCore/Tests/CoreStateTests/T07SecurityStateTests.swift` | `942f4f0`, `dc7c296`, `190daf2` |
| Added | `Packages/GlassfinCore/Tests/CoreStateTests/T08PlaybackWiringTests.swift` | `190daf2` |
| Added | `Packages/GlassfinCore/Tests/CoreStateTests/T09MVPTests.swift` | `a34000a` |
| Added | `Tests/Fixtures/m07-subtitles.json` | `dc7c296` |
| Added | `Tests/Fixtures/m07-technical-items.json` | `dc7c296` |
