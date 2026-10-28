# Glassfin P1–P15 device results

Copy once per device/build/network. Follow [DEVICE-MEASUREMENT.md](DEVICE-MEASUREMENT.md).
Leave unmeasured values blank. Status: pass / fail / blocked / N/A, with evidence.
Mock and simulator trends are separate from device acceptance.

## Environment

| Field | Value |
|---|---|
| Date/time UTC; operator alias | |
| Commit SHA; branch/PR | |
| App version/build; Debug/Release; optimization | |
| Xcode/Swift; test/profiling tool versions | |
| Xcode install / TestFlight; signing; debugger/coverage/diagnostics | |
| Apple TV model/generation/chip; memory class | |
| Actual tvOS version/build; display resolution/refresh rate | |
| Glass; Reduce Motion/Transparency/Contrast settings | |
| Gigabit LAN / Wi-Fi 5; topology alias (no IP/SSID) | |
| Docker image version/digest; host alias/resources; idle load | |
| Indexed movies/series; fixture generator command/version | |
| Playback fixture alias; duration/codec/resolution/fps/bitrate | |
| DirectPlay / server DirectStream / video transcode / on-device remux | |
| Cache state; preparation/warm-up; thermal/background state | |
| Timing source/resolution; memory units/definition | |

## Acceptance summary

Targets: A15 / oldest, latency in ms, memory in MB. A12 is a separate observation
unless an explicit budget is agreed. P2 gates p95; other latency rows report
median/p95/max and conservatively compare max. P3 uses total hitch ms / seconds.
For memory record baseline, steady and peak; P13 final idle minus baseline (<20 MB).

| ID / scenario | A15 / oldest target | n / failures | Median | p95 | Max / peak / growth | Status | Sanitized evidence / limitation |
|---|---|---|---|---|---|---|---|
| P1 cold launch, warm disk | ≤1500 / ≤3000 | | | | | | |
| P1 cold launch, purged cache | ≤1500 / ≤3000 | | | | | | |
| P2 launch all sections | ≤1000 / ≤2000 p95 | | | | | | |
| P2 stale Home return | ≤1000 / ≤2000 p95 | | | | | | |
| P3 rows / 2,000-item grid | 60 fps; hitch <5 / <10 ms/s | | | | | | |
| P4 cache | ≤100 / ≤200 | | | | | | |
| P4 LAN | ≤500 / ≤800 | | | | | | |
| P5 DirectPlay LAN | ≤1500 / ≤2500 | | | | | | |
| P6 video transcode: Play / PlaybackInfo origin | ≤4000 / ≤6000 | | | | | | |
| P7 seek forward / backward | ≤1000 / ≤2000 | | | | | | |
| P8 cached trickplay | ≤150 / ≤300 | | | | | | |
| P9 audio / subtitle, DirectPlay / HLS | ≤1000 / ≤2000; no restart | | | | | | |
| P10 search, excludes 300 ms debounce | ≤500 / ≤1000 | | | | | | |
| P11 browse footprint | ≤250 / ≤200 MB | | | | | | |
| P12 AVPlayer footprint | ≤400 / ≤300 MB | | | | | | |
| P12 on-device remux footprint | ≤500 / ≤400 MB | | | | | | |
| P13 ten play/stop cycles, retained growth | <20 MB / <20 MB | | | | | | |
| P14 stop → Home state visible | ≤2000 / ≤2000 | | | | | | |
| P15 second-client action → Home visible | ≤5000 / ≤5000 | | | | | | |

## Raw trials

Repeat rows per scenario. Preserve slow successes; record failures/cancellations
and missing intervals. Do not mix warm/cold, mock/LAN, or platform/distribution.
Nearest-rank p95 = sorted sample at ceil(0.95*n), 1-based. Record the actual
endpoints: app init versus system launch, assignment versus pixels, receipt
versus external-client action. Distinguish these when comparing to the spec.

| ID | Scenario | Trial | Start endpoint | End endpoint | Value | Unit | Completed / cancelled / failed | Trace/result filename and range |
|---|---|---|---|---|---|---|---|---|
| | | | | | | | | |

## P13 idle samples (same process; ten-second settling at each stop)

| Sample | Warm baseline | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 |
|---|---|---|---|---|---|---|---|---|---|---|---|
| Physical footprint MB | | | | | | | | | | | |

Final minus warm baseline: ___ MB. Retained-object findings: ___.

## Regression benchmarks (not acceptance)

| Test | Device/simulator | Iterations | Clock | CPU | Memory | Signpost | Evidence |
|---|---|---|---|---|---|---|---|
| P1 mock Home | | | | | | | |
| P3/P11 mock Home focus | | | | | | | |
| P5 native mock byte origin | | | | | | | |
| P12/P13 ten native mock cycles | | | | | | | |

## Decision and outstanding work

- Missing devices/scenarios, blocked product routes, skipped tests:
- Budget failures and follow-up issue links:
- Known measurement overhead/proxy limitations:
- Owner/reviewer decision and date:

Share numeric summaries and reviewed/redacted exports only. Never include
credentials, tokens, account/item IDs, personal titles, server URLs, IPs, or raw
authenticated `.trace` / `.xcresult` bundles in the repository or PR.
