#!/usr/bin/env bash
# Source checks from 00-infra-ci and 03-security. Scans app and package sources, not spec prose.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
fail=0

search() {
  local pattern="$1"
  local message="$2"
  local hits
  hits="$(grep -RInE --exclude-dir=.build --exclude-dir=checkouts \
    --include='*.swift' --include='*.plist' --include='*.entitlements' --include='*.yml' \
    "$pattern" "$root/Packages" "$root/Apps" "$root/project.yml" || true)"
  if [[ -n "$hits" ]]; then
    echo "ci-grep: $message" >&2
    echo "$hits" >&2
    fail=1
  fi
}

search 'NSAllowsArbitraryLoads' 'NSAllowsArbitraryLoads is not allowed'
search 'NSExceptionDomains' 'ATS exception domains are not allowed'
search 'X-Emby-Token' 'legacy X-Emby-Token header'
search 'X-Emby-Authorization' 'legacy X-Emby-Authorization header'
search 'X-MediaBrowser-Token' 'legacy X-MediaBrowser-Token header'
search 'api_key' 'legacy api_key query name must not appear as a literal'
search '\bprint\(' 'print( is not allowed; use GlassfinLog'
search 'AppCore' 'package name is GlassfinCore, not AppCore'

ui_hits="$(grep -RInE --exclude-dir=.build --include='*.swift' 'import (SwiftUI|UIKit)' "$root/Packages" || true)"
ui_hits="$(printf '%s\n' "$ui_hits" | grep -v '/Tests/' || true)"
if [[ -n "$ui_hits" ]]; then
  echo "ci-grep: SwiftUI/UIKit import under Packages sources" >&2
  echo "$ui_hits" >&2
  fail=1
fi

python3 "$root/scripts/check-image-pipeline.py" || fail=1
python3 "$root/scripts/check-design-system.py" || fail=1
python3 "$root/scripts/check-string-catalogs.py" || fail=1

if [[ "$fail" -ne 0 ]]; then
  exit 1
fi
echo "ci-grep: passed"
