# Performance measurement test additions

No existing test file or assertion is changed. No baseline or acceptance threshold
is weakened. New test files:

- `Apps/Shared/UITests/DevicePerformanceTests.swift`: P1 mock Home launch (launch,
  clock, signpost metrics), P3/P11 tvOS focus/browse (clock, app CPU, app memory,
  signpost metrics). Three measured iterations; fixtures are the existing mock Home.
- `Apps/Shared/Tests/Logic/DevicePlaybackPerformanceTests.swift`: P5 native first
  frame (clock, CPU, memory, actual coordinator signpost), P12/P13 ten native
  play/stop cycles (clock, CPU, memory). Real AVPlayerEngine/resource loader and
  AVPlayerLayer display readiness; API and byte origin stay in memory. Requires
  generated 12-second H.264 fixture. Missing fixture explicitly skips these two
  tests; CI and the device runner generate it before XcodeGen, so they must run.

The native benchmarks use the hosted app process, including XCTest overhead.
They are decoder/lifecycle regression measurements, not LAN startup, full-length
4K memory, or proof that retained growth is below 20 MB. See the runbook for those
acceptance procedures. No absolute device budgets are asserted on simulators.

`project.yml` adds the generated fixture as an optional test bundle resource to
both existing hosted unit-test targets. Both Debug test actions pass the existing
`-uitest-mock-server` argument so hosted app startup cannot restore a saved
server session while benchmarks run. Run/Profile/Archive actions are unchanged.
`scripts/macos-ci.sh` prepares it before
project generation. Test suites remain in their existing schemes and therefore
run in the regular tvOS/iOS CI jobs. Existing synthetic performance tests remain
intact. Source-check assertions and artifact redaction rules remain intact.
