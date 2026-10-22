#!/usr/bin/env bash
# T01-19. Line coverage of GlassfinCore sources must stay at or above 80%.
# The jellyfin-sdk-swift wrapper (CoreAPI/SDKClient.swift) is excluded: it does not build on Linux.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root/Packages/GlassfinCore"

swift test --enable-code-coverage

llvm="$(dirname "$(command -v swift)")/llvm-cov"
if [[ ! -x "$llvm" ]]; then
  llvm="$(command -v llvm-cov)"
fi
prof="$(find .build -path '*/codecov/default.profdata' -type f | head -1)"
bin="$(find .build -type f -name 'GlassfinCorePackageTests.xctest' | head -1)"
if [[ -z "$prof" || -z "$bin" ]]; then
  echo "T01-19 coverage: profdata or test binary missing" >&2
  exit 1
fi

summary="$(mktemp)"
trap 'rm -f "$summary"' EXIT
"$llvm" export "$bin" \
  -instr-profile "$prof" \
  -summary-only \
  -ignore-filename-regex='Tests/|\.build/|checkouts/|CoreAPI/SDKClient\.swift' \
  >"$summary"

python3 - "$summary" <<'PY'
import json
import sys

report = json.load(open(sys.argv[1]))
lines = report["data"][0]["totals"]["lines"]
count = int(lines["count"])
covered = int(lines["covered"])
if count == 0:
    print("T01-19 coverage: no instrumented lines", file=sys.stderr)
    sys.exit(1)
percent = 100.0 * covered / count
print(f"T01-19 line coverage {percent:.2f}% ({covered}/{count}), threshold 80%")
if percent < 80.0:
    sys.exit(1)
PY
