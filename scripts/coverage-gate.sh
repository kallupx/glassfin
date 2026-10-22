#!/usr/bin/env bash
# T01-19. Line coverage of GlassfinCore sources must stay at or above 80%.
# The jellyfin-sdk-swift wrapper (CoreAPI/SDKClient.swift) is excluded: it does not build on Linux.
# Swift 6.4's default swiftbuild layout does not write default.profdata. The native
# driver still emits per-process .profraw files next to GlassfinCorePackageTests.xctest.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root/Packages/GlassfinCore"

find .build -path '*/codecov/*.profraw' -type f -delete 2>/dev/null || true
find .build -path '*/codecov/*.profdata' -type f -delete 2>/dev/null || true
swift test --enable-code-coverage --build-system native

bindir="$(dirname "$(command -v swift)")"
profdata="$bindir/llvm-profdata"
cov="$bindir/llvm-cov"
if [[ ! -x "$profdata" ]]; then
  profdata="$(command -v llvm-profdata)"
  cov="$(command -v llvm-cov)"
fi

mapfile -t raws < <(find .build -path '*/codecov/*.profraw' -type f | sort)
merged="$(mktemp)"
summary="$(mktemp)"
trap 'rm -f "$merged" "$summary"' EXIT
if [[ ${#raws[@]} -eq 0 ]]; then
  echo "T01-19 coverage: no profraw files" >&2
  exit 1
fi
"$profdata" merge -sparse -o "$merged" "${raws[@]}"

mapfile -t bins < <(find .build -type f -name '*.xctest' ! -path '*/checkouts/*' | sort)
if [[ ${#bins[@]} -eq 0 ]]; then
  echo "T01-19 coverage: test binary missing" >&2
  exit 1
fi
args=("${bins[0]}" -instr-profile "$merged" -summary-only -ignore-filename-regex='Tests/|\.build/|checkouts/|CoreAPI/SDKClient\.swift')
for extra in "${bins[@]:1}"; do
  args+=(-object "$extra")
done
"$cov" export "${args[@]}" >"$summary"

python3 - "$summary" <<'PY'
import json
import sys

report = json.load(open(sys.argv[1], encoding="utf-8"))
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
