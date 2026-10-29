#!/usr/bin/env bash
# tvOS or iOS job body. With tvOS shards, shard 1 owns Release and package checks.
set -euo pipefail

platform="${1:?tvOS or iOS}"
shard="${2:-}"
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
shard_selection=""
if [[ -n "$shard" ]]; then
  if [[ "$platform" != "tvOS" ]]; then
    echo "UI sharding is supported only for tvOS" >&2
    exit 1
  fi
  shard_selection="$(python3 scripts/check-tvos-ui-shards.py --shard "$shard")"
fi
source_packages="$root/SourcePackages"
artifacts="$root/artifacts/$platform"
mkdir -p "$artifacts/screenshots"
status=0

pick_destination() {
  local os_name="$1"
  local preferred="$2"
  local list
  list="$(xcrun simctl list devices available)"
  if printf '%s\n' "$list" | grep -F "$preferred" >/dev/null; then
    printf 'platform=%s Simulator,name=%s\n' "$os_name" "$preferred"
    return
  fi
  local name
  name="$(printf '%s\n' "$list" | awk -v os="$os_name" '
    $0 ~ "^-- " os { inside = 1; next }
    $0 ~ "^-- " { inside = 0 }
    inside && $0 ~ /\(/ {
      sub(/^[[:space:]]+/, "")
      sub(/[[:space:]]+\(.*/, "")
      print
      exit
    }
  ')"
  if [[ -z "$name" ]]; then
    echo "No ${os_name} simulator is installed" >&2
    exit 1
  fi
  echo "Using fallback ${os_name} simulator: $name" >&2
  printf 'platform=%s Simulator,name=%s\n' "$os_name" "$name"
}

if ! command -v xcodegen >/dev/null 2>&1; then
  brew install xcodegen
fi
if ! command -v ffmpeg >/dev/null 2>&1; then
  brew install ffmpeg
fi
bash scripts/prepare-perf-fixture.sh
xcodegen generate

if [[ "$platform" == "tvOS" ]]; then
  destination="$(pick_destination tvOS "Apple TV 4K (3rd generation)")"
  scheme="Glassfin-tvOS"
  sdk_glob='*appletvsimulator*'
else
  destination="$(pick_destination iOS "iPhone 17")"
  scheme="Glassfin-iOS"
  sdk_glob='*iphonesimulator*'
fi

if [[ -z "$shard" || "$shard" == "1" ]]; then
  release_data="$root/DerivedData-release-$platform"
  rm -rf "$release_data"
  # Scan the Release binary for the simulator architecture used by the tests.
  # A generic destination builds both arm64 and x86_64, consuming the iOS test budget.
  xcodebuild build \
    -scheme "$scheme" \
    -configuration Release \
    -destination "$destination" \
    -clonedSourcePackagesDirPath "$source_packages" \
    -derivedDataPath "$release_data" \
    ONLY_ACTIVE_ARCH=YES \
    CODE_SIGNING_ALLOWED=NO \
    | tee "$artifacts/release-build.log" || status=$?

  app="$(find "$release_data/Build/Products" -path "$sdk_glob" -name 'Glassfin.app' -type d | head -1 || true)"
  if [[ -z "$app" ]]; then
    echo "Release app was not produced" >&2
    status=1
  else
    bash "$root/scripts/check-release-binary.sh" "$app" | tee "$artifacts/release-binary.txt" || status=$?
  fi

  if [[ "$platform" == "tvOS" ]]; then
    (
      cd "$root/Packages/GlassfinCore"
      swift test
    ) | tee "$artifacts/swift-test.log" || status=$?
  else
    (
      cd "$root/Packages/GlassfinCore"
      NSUnbufferedIO=YES xcodebuild test \
        -scheme GlassfinCore \
        -destination "$destination" \
        -test-timeouts-enabled YES \
        -default-test-execution-time-allowance 180 \
        -maximum-test-execution-time-allowance 180 \
        -clonedSourcePackagesDirPath "$source_packages" \
        -derivedDataPath "$root/DerivedData-package-$platform" \
        -resultBundlePath "$artifacts/package.xcresult" \
        CODE_SIGNING_ALLOWED=NO
    ) | tee "$artifacts/package-test.log" || status=$?
  fi
fi

app_test_args=(-scheme "$scheme")
if [[ "$platform" == "tvOS" ]]; then
  app_test_args+=(-parallel-testing-enabled NO)
fi
if [[ -n "$shard" ]]; then
  while IFS= read -r argument; do
    app_test_args+=("$argument")
  done <<< "$shard_selection"
fi

# Bound XCTest's automation/idle waits as well as the explicit waits in each test.
# Unbuffered output keeps the active test visible in the streamed CI log.
NSUnbufferedIO=YES xcodebuild test \
  "${app_test_args[@]}" \
  -destination "$destination" \
  -test-timeouts-enabled YES \
  -default-test-execution-time-allowance 180 \
  -maximum-test-execution-time-allowance 180 \
  -clonedSourcePackagesDirPath "$source_packages" \
  -derivedDataPath "$root/DerivedData-$platform" \
  -resultBundlePath "$artifacts/app.xcresult" \
  CODE_SIGNING_ALLOWED=YES \
  | tee "$artifacts/app-test.log" || status=$?

bundles=()
if [[ -d "$artifacts/package.xcresult" ]]; then
  bundles+=(--xcresult "$artifacts/package.xcresult")
fi
if [[ -d "$artifacts/app.xcresult" ]]; then
  bundles+=(--xcresult "$artifacts/app.xcresult")
fi
if [[ ${#bundles[@]} -gt 0 ]]; then
  python3 "$root/scripts/export_xcresult.py" "${bundles[@]}" --output "$artifacts/readable" || true
fi
if [[ -d "$root/artifacts/screenshots" ]]; then
  mkdir -p "$artifacts/readable/screenshots"
  cp -R "$root/artifacts/screenshots/." "$artifacts/readable/screenshots/" || true
fi
python3 "$root/scripts/redact_artifacts.py" "$artifacts"
exit "$status"
