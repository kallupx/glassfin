# ADR-M09-1: Search defaults to three parallel `/Items` requests

Status: accepted default; cross-version performance evidence pending.
Date: 2026-10-27.
Binding references: spec/09-search.md as updated by spec PR #18; SR1–SR5; S6.1/S6.5/S6.6/S6.7.

## Decision

Use `ItemsSearchBackend` by default. Start three parallel `/Items` requests, one each for Movie, Series and Episode, with an independent limit of 24. Preserve the server's order within each row. Initial results and subsequent pages use the same small `SearchBackend` protocol.

Keep `SearchHintsBackend` available for measurement and injection. Its initial `/Search/Hints` request has a total budget of 72, groups without re-sorting, and displays at most 24 per type. A full shared hints page can leave a type unrepresented; that row can subsequently fetch a type-specific page. This difference in coverage must be considered alongside latency. Do not silently fall back or switch endpoints.

Switch only if `/Search/Hints` is clearly faster on **all three** CI versions (10.10.7, 10.11.11, 12.2), retains usable image tags, and provides sufficient row coverage. The proposed interpretation of “clearly faster” is at least 20% lower median on each version with no p95 regression, confirmed in another run. This threshold is a conservative implementation proposal (Q9-04); changing the default requires reviewing and recording the evidence in this ADR.

## Reproducible benchmark

Run from the repository root:

```sh
export LD_LIBRARY_PATH=~/.local/lib/swiftcompat
source ~/.local/share/swiftly/env.sh
bash scripts/docker-integration.sh
# Or one version:
bash scripts/docker-integration.sh 10.10.7
```

`Tests/Fixtures/search-seed.json` and `scripts/jellyfin_search_seed.py` generate exactly 5,000 searchable items: 2,000 movies, 1,000 series and 2,000 episodes. The movies include `Sääasema (2024)` for T09-22. Media files are hard links to one ffmpeg dummy clip. Local NFOs and poster/episode images avoid external metadata dependencies. The bootstrap waits for the complete scan, excluding folders and seasons from its count.

`LiveServerTests.testT09_21_searchBackendLatencyAndResultCounts` measures both production backend implementations against the same authenticated HTTP client. It uses two warm-up rounds followed by 12 paired samples, alternating endpoint order. Each sample measures the entire initial grouped request, including decoding, but excludes debounce, image loading and UI rendering. It records milliseconds, per-row counts in Movie/Series/Episode order, and the number of primary image tags. The JSON includes nearest-rank median and p95 plus raw samples. T09-22 separately requires the umlaut item to be found through both implementations.

Output goes to the CI console as `T09-21 search-benchmark` JSON and to `artifacts/integration/search/search-<version>.json`. `integration.yml` needs the narrowly scoped redaction/upload steps added here: it previously had no artifact upload, so measurements would otherwise disappear with the runner. The `search-backend-benchmarks` artifact retains only these JSON files for seven days. No query text, credential, URL or raw server metadata is emitted. No xcresult is uploaded.

Docker measurements run on the host loopback connection. They compare endpoint cost and do not replace the P10 LAN/device acceptance measurement (T09-34: first results within 500 ms after debounce).

## Local evidence

On 2026-10-27, `docker info` failed with `docker: command not found`; `bash scripts/docker-integration.sh 10.10.7` reported `docker-integration: docker is not available`. There are therefore **no local latency numbers**, and no basis for switching to hints.

| Server version | `/Items` median / p95 | Hints median / p95 | Row counts / image tags |
|---|---|---|---|
| 10.10.7 | Not measured | Not measured | Pending Docker run |
| 10.11.11 | Not measured | Not measured | Pending Docker run |
| 12.2 | Not measured | Not measured | Pending Docker run |

The local seed smoke check passed: 2,000 movies + 1,000 series + 2,000 episodes; umlaut item present; all media files share the generated clip's inode. ffmpeg decoded the seed poster successfully. Integration tests compile and explicitly skip without `GLASSFIN_INTEGRATION=1`.

## Consequences

The default gives each row its own result budget and existing DTO/image semantics. There are three concurrent requests per initial search. New input cancels them; generation and response-term checks prevent late responses from changing the display. A shared session client handles a 401 before stale-response rejection, cancels search/image/detail work, and ends the session once.

Apple production searches pass parameters through the generated SDK query builders in CoreAPI. CoreNetworking retains responsibility for header authorization, TLS pins, redirects and URL construction. Linux uses equivalent URLQueryItems because the SDK's Network.framework dependency cannot build there. Search terms never enter paths or transport log messages.
