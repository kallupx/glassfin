#!/usr/bin/env bash
# keychain-access-groups may exist only on the app and Top Shelf targets (S1.4).
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
allowed=(
  "Apps/tvOS/Glassfin.entitlements"
  "Apps/iOS/Glassfin.entitlements"
  "Apps/TopShelf/TopShelf.entitlements"
)
expected='$(AppIdentifierPrefix)org.glassfin.app'
fail=0

mapfile -t found < <(find "$root/Apps" "$root/Packages" -name '*.entitlements' -print 2>/dev/null || true)
declare -A allow=()
for path in "${allowed[@]}"; do
  allow["$root/$path"]=1
  if [[ ! -f "$root/$path" ]]; then
    echo "entitlements: missing $path" >&2
    fail=1
  elif ! grep -F -q "$expected" "$root/$path"; then
    echo "entitlements: $path does not grant $expected" >&2
    fail=1
  fi
done

for path in "${found[@]}"; do
  if ! grep -q 'keychain-access-groups' "$path"; then
    continue
  fi
  if [[ -z "${allow[$path]:-}" ]]; then
    echo "entitlements: keychain-access-groups is not allowed in $path" >&2
    fail=1
  fi
done

if [[ "$fail" -ne 0 ]]; then
  exit 1
fi
echo "entitlements: keychain access group is limited to the app and Top Shelf"
