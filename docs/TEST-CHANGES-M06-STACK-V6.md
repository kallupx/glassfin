# M06 stack base v6 CI repair

Baseline: `3bfae2a`. Merge commit: `6865e0e`, titled
`Merge main d720120 (stack base v6)`. The fetched M05 tip, `d2d780b`,
was already an ancestor, so no additional M05 merge was needed.

## Failure evidence

[Run 40627832541](https://github.com/kallupx/glassfin/actions/runs/40627832541)
failed only in `test-ios`, job `122617516365`. Lint, tvOS, and full-ui passed.
The job console stopped showing build output at 04:24:25 UTC; its
[ios-results artifact](https://github.com/kallupx/glassfin/actions/runs/40627832541/artifacts/12792456467)
contains the later package and app diagnostics.

- `app-test.log:8633` and `:8771`: M05's iOS `selectTab` helper calls
  main-actor-isolated `require` from a nonisolated method. The helper came
  from M05; M06's earlier XCTest compatibility changes annotated the other
  UI helpers with `@MainActor`. Their integration missed this helper.
  Adding its missing annotation is the only M05-file repair needed for
  this PR. No UI queries or assertions change.
- `package-test.log:9354`: `testT06_76_missingContentLengthAbortsDuringDownload`
  reports 21,168,128 producer bytes against an assumed maximum of
  21,102,592 (20 MiB plus two 64 KiB chunks).
- `package-test.log:9359`: `testT06_78_advertisedOversizeRejectsBeforeBody`
  reports 327,680 producer bytes against an assumed maximum of 65,536.
  Both tests received the expected oversized-image error, observed stopped
  transport, and passed their no-cache assertions. The fixture produces
  chunks every 2 ms on a separate queue. URLProtocol delivery and
  URLSession cancellation are asynchronous, so these sender-side chunk
  bounds depend on scheduling. They do not measure the downloader's
  retained buffer. Production already rejects oversized headers and
  checks each delivered chunk before appending it.

These are an actor-isolation compile error and two M06 test timing flakes,
not a CI timeout. The job ran from 04:21:18 to 04:33:04 UTC, within its
25-minute limit. Release compilation and the Release binary scan passed.
No defect in main's production code caused these failures, and no new
production-code change is justified by the evidence.

## Explicit test and assertion changes

- `Apps/Shared/UITests/DesignSystemFocusTests.swift`: add `@MainActor` to
  `selectTab`, required to compile calls to the actor-isolated UI helpers.
  All assertions and interactions remain unchanged.
- `Packages/GlassfinCore/Tests/CoreStateTests/T06ImageStreamTests.swift`:
  remove the fixture-producer upper bounds of one chunk for header
  rejection, 20 MiB plus two chunks for body rejection, and less than the
  entire produced body. These bounds cannot be guaranteed across
  URLSession's asynchronous queues. Keep the expected error, transport
  cancellation, body-limit crossing, no disk-cache entry, no disk file,
  exact 20 MiB acceptance, 401 precedence, and explicit cancellation checks.
- Add `testT06_76_T06_77_deliveredByteLimitDoesNotTrustContentLength`:
  drive the production delegate with a four-byte budget, both unknown
  and falsely small lengths, and exact-limit versus one-byte-over bodies.
  Assert exact bytes on success and `responseTooLarge` on overflow.
- Add `testT06_78_oversizedHeaderCancelsTheReceivingDelegate`: assert the
  delegate returns `.cancel` and `responseTooLarge` before accepting body
  data for an oversized header. The fixture holds its real URLSession
  task idle after signaling startup, so controlled delegate callbacks
  have no competing producer. Late successful completion cannot replace
  a size rejection. No timeout or byte-budget constant was increased.
- The requested main merge also imports its playback test changes in
  `ADRM08PrototypeTests.swift` and `PlaybackCoordinatorTests.swift` verbatim:
  credential-only wrapping rejection, missing remux credential rejection
  on initial play and retry, request header/query assertions, and updated
  remux fixtures. Neither file has further local edits.

No test is removed, disabled, or newly skipped. No product UI string changes
are needed. All workflows, `project.yml`, and `Info.plist` files match main.

## Validation and limits

With the requested Swift environment:

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

All commands pass. The coverage gate executes 496 tests, with zero failures
and eight existing live-server skips. Line coverage is 91.43% (8050/8805),
above the 80% threshold. The focused image-stream suite passes all eight
tests. `git diff --check` passes.

This Linux host has no Xcode or Apple simulators, so the iOS compile repair,
Apple-only image decoding, UI tests, and snapshots require CI confirmation.
Live Jellyfin integration was not enabled.
