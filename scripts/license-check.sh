#!/usr/bin/env bash
# Fail when a resolved dependency is missing from THIRD_PARTY_LICENSES, or when
# a forbidden GPL / nonfree marker shows up in package manifests or sources.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
if [[ "${1:-}" == "--root" ]]; then
  root="$2"
  shift 2
fi

if [[ "${1:-}" == "--self-test" ]]; then
  tmp="$(mktemp -d)"
  mkdir -p "$tmp/Packages" "$tmp/Apps"
  printf '%s\n' 'identity: example-lib' >"$tmp/THIRD_PARTY_LICENSES"
  printf '%s\n' 'let clean = 1' >"$tmp/Packages/Clean.swift"
  printf '%s\n' '{"pins":[{"identity":"example-lib","state":{"version":"1.0.0"}}],"version":2}' >"$tmp/Package.resolved"
  bash "$0" --root "$tmp" >/tmp/license-check-positive.txt
  printf '%s\n' 'import Kingslay' $'let url = "https://github.com/kingslay/FFmpegKit"' >"$tmp/Packages/Bad.swift"
  if bash "$0" --root "$tmp" >/tmp/license-check-negative.txt 2>&1; then
    echo "license-check self-test failed: forbidden dependency was accepted" >&2
    exit 1
  fi
  rm -f "$tmp/Packages/Bad.swift"
  printf '%s\n' '--enable-gpl' >"$tmp/Apps/build-notes.txt"
  if bash "$0" --root "$tmp" >/tmp/license-check-gpl.txt 2>&1; then
    echo "license-check self-test failed: --enable-gpl was accepted" >&2
    exit 1
  fi
  echo "license-check self-test passed"
  exit 0
fi

licenses="$root/THIRD_PARTY_LICENSES"
if [[ ! -f "$licenses" ]]; then
  echo "license-check: missing THIRD_PARTY_LICENSES" >&2
  exit 1
fi

fail=0
forbidden='kingslay/FFmpegKit|ffmpegkit|--enable-gpl|--enable-nonfree|MPVKit-GPL|\bx264\b'
while IFS= read -r file; do
  if grep -E -n -I "$forbidden" "$file"; then
    echo "license-check: forbidden marker in $file" >&2
    fail=1
  fi
done < <(find "$root/Packages" "$root/Apps" "$root/project.yml" -type f \
  \( -name '*.swift' -o -name 'Package.swift' -o -name 'Package.resolved' -o -name '*.yml' -o -name '*.txt' \) \
  -not -path '*/.build/*' 2>/dev/null || true)

python3 - "$root" "$licenses" <<'PY' || fail=1
import json, sys
from pathlib import Path
root = Path(sys.argv[1])
licenses = Path(sys.argv[2]).read_text(encoding="utf-8").lower()
resolved_files = [path for path in root.rglob("Package.resolved") if ".build" not in path.parts]
if not resolved_files:
    print("license-check: no Package.resolved found", file=sys.stderr)
    sys.exit(1)
missing = []
for path in resolved_files:
    data = json.loads(path.read_text(encoding="utf-8"))
    pins = data.get("pins") or data.get("object", {}).get("pins") or []
    for pin in pins:
        identity = pin.get("identity") or pin.get("package")
        if identity and identity.lower() not in licenses:
            missing.append(f"{identity} ({path})")
if missing:
    print("license-check: missing from THIRD_PARTY_LICENSES:", file=sys.stderr)
    for item in missing:
        print(f"  {item}", file=sys.stderr)
    sys.exit(1)
print(f"license-check: {sum(1 for _ in resolved_files)} Package.resolved file(s) match THIRD_PARTY_LICENSES")
PY

exit "$fail"
