#!/usr/bin/env bash
# Signed tvOS device benchmarks with mock UI/API/media only. Run on the owner's Mac.
set -euo pipefail
if [[ $# -ne 2 ]]; then
  echo "Usage: scripts/device-measurement.sh APPLE_TV_UDID DEVELOPMENT_TEAM" >&2
  exit 2
fi
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
for tool in xcodebuild xcodegen ffmpeg; do
  command -v "$tool" >/dev/null || { echo "Missing tool: $tool" >&2; exit 1; }
done
bash scripts/prepare-perf-fixture.sh
xcodegen generate
result="$root/artifacts/device-perf/$(date -u +%Y%m%dT%H%M%SZ).xcresult"
mkdir -p "$(dirname "$result")"
xcodebuild test -project Glassfin.xcodeproj -scheme Glassfin-tvOS \
  -configuration Debug -destination "platform=tvOS,id=$1" \
  -parallel-testing-enabled NO -enableCodeCoverage NO \
  -resultBundlePath "$result" \
  -only-testing:Glassfin-tvOSUITests/DevicePerformanceTests \
  -only-testing:Glassfin-tvOSUnitTests/DevicePlaybackPerformanceTests \
  CODE_SIGN_STYLE=Automatic CODE_SIGNING_ALLOWED=YES CODE_SIGNING_REQUIRED=YES \
  CODE_SIGN_IDENTITY='Apple Development' DEVELOPMENT_TEAM="$2" \
  -allowProvisioningUpdates
