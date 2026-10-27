#!/usr/bin/env bash
# T00-19. Fail when a Release app executable contains mock-server strings or symbols.
# Scan only the app executable. UI-test bundles legitimately contain the launch arguments.
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: check-release-binary.sh App.app" >&2
  exit 2
fi

app="$1"
if [[ ! -d "$app" ]]; then
  echo "release-binary: app not found: $app" >&2
  exit 1
fi

plist="$app/Info.plist"
exec_name="$(basename "$app" .app)"
if [[ -f "$plist" ]] && command -v /usr/libexec/PlistBuddy >/dev/null 2>&1; then
  exec_name="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$plist")"
fi
binary="$app/$exec_name"
if [[ ! -f "$binary" ]]; then
  echo "release-binary: executable not found: $binary" >&2
  exit 1
fi

fail=0
if strings "$binary" | grep -F -e 'uitest-' -e 'MockAPIClient' -e 'AVURLAssetHTTPHeaderFieldsKey'; then
  echo "release-binary: $binary contains a test marker or the undocumented media header key" >&2
  fail=1
fi
if nm "$binary" 2>/dev/null | grep -F -e 'uitest-' -e 'MockAPIClient'; then
  echo "release-binary: $binary exports uitest- or MockAPIClient" >&2
  fail=1
fi

if [[ "$fail" -ne 0 ]]; then
  exit 1
fi
echo "release-binary: $binary has no test markers or undocumented media header key strings"
