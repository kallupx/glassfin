#!/usr/bin/env bash
# tvOS or iOS job body. Release binary scan runs in this job; it is not a separate macOS job.
set -euo pipefail

platform="${1:?tvOS or iOS}"
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
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
xcodegen generate

if [[ "$platform" == "tvOS" ]]; then
  destination="$(pick_destination tvOS "Apple TV 4K (3rd generation)")"
  scheme="Glassfin-tvOS"
  generic="generic/platform=tvOS Simulator"
  sdk_glob='*appletvsimulator*'
else
  destination="$(pick_destination iOS "iPhone 17")"
  scheme="Glassfin-iOS"
  generic="generic/platform=iOS Simulator"
  sdk_glob='*iphonesimulator*'
fi

release_data="$root/DerivedData-release-$platform"
rm -rf "$release_data"
xcodebuild build \
  -scheme "$scheme" \
  -configuration Release \
  -destination "$generic" \
  -derivedDataPath "$release_data" \
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
    xcodebuild test \
      -scheme GlassfinCore \
      -destination "$destination" \
      -derivedDataPath "$root/DerivedData-package-$platform" \
      -resultBundlePath "$artifacts/package.xcresult" \
      CODE_SIGNING_ALLOWED=NO
  ) | tee "$artifacts/package-test.log" || status=$?
fi

xcodebuild test \
  -scheme "$scheme" \
  -destination "$destination" \
  -derivedDataPath "$root/DerivedData-$platform" \
  -resultBundlePath "$artifacts/app.xcresult" \
  CODE_SIGNING_ALLOWED=NO \
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
