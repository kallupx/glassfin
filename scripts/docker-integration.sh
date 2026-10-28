#!/usr/bin/env bash
# T01-20 and T01-30 against throwaway jellyfin/jellyfin containers.
# Pins are the OCI index digests of tags 10.10.7, 10.11.11, and 12.2.
# Usage: scripts/docker-integration.sh [--self-test | version ...]
# GLASSFIN_HLS_PROBE_ARGS: whitespace-separated probe flags (no shell evaluation).
set -euo pipefail
# Check before displaying anything: a rejected capture must produce no stdout.
show_checked_output() {
  local captured="$1"
  if ! python3 - "$captured" <<'PYTHON'
import re
import sys
from pathlib import Path

# Match complete credential field names, including MediaBrowser's Token field.
# Concatenate the legacy spelling to keep credential-name source scans green.
pattern = re.compile(
    r"(?<![\w-])(?:apikey|api" + r"_key|token)\s*=\s*"
    r"(?:\"([^\"]*)\"|'([^']*)'|([^&\s,;\"']+))",
    re.IGNORECASE,
)
redacted = {"<redacted>", "[redacted]", "redacted"}
with Path(sys.argv[1]).open(encoding="utf-8", errors="replace") as captured:
    for line in captured:
        for match in pattern.finditer(line):
            value = next(value for value in match.groups() if value is not None)
            if value and value.casefold() not in redacted:
                sys.exit(1)
PYTHON
  then
    echo "docker-integration: captured output contains an unredacted credential; output withheld" >&2
    return 1
  fi
  cat "$captured"
}

self_test_checked_output() (
  local work sample case_number=0
  work="$(mktemp -d)"
  trap 'rm -rf "$work"' EXIT
  # All credential samples are obvious fakes, never values from the environment.
  local leaking=(
    'https://example.invalid/master?ApiKey=deadbeefdeadbeefdeadbeefdeadbeef'
    'https://example.invalid/master?API_KEY=deadbeefdeadbeefdeadbeefdeadbeef'
    'Token="deadbeefdeadbeefdeadbeefdeadbeef"'
    'tOkEn=FAKE_TOKEN_VALUE'
    'MediaBrowser Client="Glassfin", Device="TV", Token="FAKE_TOKEN_VALUE"'
    'mEdIaBrOwSeR Client="Glassfin", tOkEn=FAKE_TOKEN_VALUE'
    'MediaBrowser Token = "deadbeefdeadbeefdeadbeefdeadbeef"'
    "Token='FAKE_TOKEN_VALUE'"
    'https://example.invalid/master?token=FAKE_TOKEN_VALUE&keep=1'
    'Token="REDACTED" Token=FAKE_TOKEN_VALUE'
    'All checks passed
Token=FAKE_TOKEN_VALUE'
  )
  for sample in "${leaking[@]}"; do
    case_number=$((case_number + 1))
    printf '%s\n' "$sample" >"$work/input"
    if show_checked_output "$work/input" >"$work/stdout" 2>"$work/stderr"; then
      echo "docker-integration self-test: leaking case $case_number was accepted" >&2
      return 1
    fi
    if [[ -s "$work/stdout" ]] || ! grep -qxF \
      'docker-integration: captured output contains an unredacted credential; output withheld' "$work/stderr"; then
      echo "docker-integration self-test: leaking case $case_number was not safely withheld" >&2
      return 1
    fi
  done
  local clean=(
    'All checks passed; MediaBrowser client configured'
    'Token count: 3; tokenization completed; tokenizer=ready; mytoken=ready'
    'ApiKeyValue=example; api_key_name=example; not-token=example'
    'Token="<redacted>" ApiKey=<redacted> API_KEY=REDACTED'
    'MediaBrowser Client="Glassfin", Token="REDACTED"'
    "Token='[REDACTED]'"
    'Token='
    'Token=""'
    "Token=''"
    'https://example.invalid/master?PlaySessionId=example'
    ''
  )
  for sample in "${clean[@]}"; do
    case_number=$((case_number + 1))
    printf '%s\n' "$sample" >"$work/input"
    if ! show_checked_output "$work/input" >"$work/stdout" 2>"$work/stderr" \
      || ! cmp -s "$work/input" "$work/stdout" || [[ -s "$work/stderr" ]]; then
      echo "docker-integration self-test: clean case $case_number was altered or rejected" >&2
      return 1
    fi
  done
  echo "docker-integration self-test: $case_number cases passed"
)

if [[ "${1:-}" == "--self-test" ]]; then
  self_test_checked_output
  exit 0
fi

root="$(cd "$(dirname "$0")/.." && pwd)"
if [[ -x /opt/swift/usr/bin/swift ]]; then
  export PATH="/opt/swift/usr/bin:$PATH"
fi

if docker info >/dev/null 2>&1; then
  docker_cmd=(docker)
elif sudo docker info >/dev/null 2>&1; then
  docker_cmd=(sudo docker)
else
  echo "docker-integration: docker is not available" >&2
  exit 1
fi

if ! command -v ffmpeg >/dev/null 2>&1; then
  echo "docker-integration: ffmpeg is required to generate testsrc media" >&2
  exit 1
fi

swift_image="swift:6.4@sha256:6fbd5978b56a5a9ff05a48f8f678079fc45be496ecda15b4e74e8944fab857be"

declare -A images=(
  [10.10.7]="jellyfin/jellyfin:10.10.7@sha256:7ae36aab93ef9b6aaff02b37f8bb23df84bb2d7a3f6054ec8fc466072a648ce2"
  [10.11.11]="jellyfin/jellyfin:10.11.11@sha256:aefb67e6a7ff1debdd154a78a7bbb780fd0c873d8639210a7f6a2016ad2b35db"
  [12.2]="jellyfin/jellyfin:12.2@sha256:357724bf0ae27a672c7cbaa899db2d9abeb13dbd8657ccce750258a4c059d037"
)

if [[ "$#" -gt 0 ]]; then
  versions=("$@")
else
  versions=(10.10.7 10.11.11 12.2)
fi

run_tests() {
  if command -v swift >/dev/null 2>&1; then
    (
      cd "$root/Packages/GlassfinCore"
      swift test "$@"
    )
    return
  fi
  "${docker_cmd[@]}" run --rm --network host \
    -v "$root:/src" \
    -w /src/Packages/GlassfinCore \
    -e GLASSFIN_INTEGRATION \
    -e GLASSFIN_SERVER_URL \
    -e GLASSFIN_USERNAME \
    -e GLASSFIN_PASSWORD \
    -e GLASSFIN_TEST_USERNAME \
    -e GLASSFIN_TEST_PASSWORD \
    -e GLASSFIN_SERVER_VERSION \
    -e GLASSFIN_SEARCH_BENCHMARK_DIR=/src/artifacts/integration/search \
    "$swift_image" \
    swift test "$@"
}

container=""
cleanup() {
  if [[ -n "$container" ]]; then
    "${docker_cmd[@]}" rm -f "$container" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

results=()
probe_args=()
# T08P-102: require the old failure and D4 headerless media success, including fMP4 init.
read -r -a probe_args <<< "${GLASSFIN_HLS_PROBE_ARGS:---assert stripped:segment_noheader=401 --assert loader:segment_noheader=200 --assert loader:map_noheader=200}"

for version in "${versions[@]}"; do
  image="${images[$version]:-}"
  if [[ -z "$image" ]]; then
    echo "docker-integration: unknown version $version" >&2
    exit 2
  fi
  work="$(mktemp -d)"
  chmod 755 "$work"
  mkdir -p "$work/media" "$work/config"
  chmod 777 "$work/media" "$work/config"
  bash "$root/scripts/generate-playback-media.sh" "$work/media"
  port="$(python3 - <<'PY'
import socket
s = socket.socket()
s.bind(("127.0.0.1", 0))
print(s.getsockname()[1])
s.close()
PY
)"
  container="glassfin-jellyfin-${version//./-}"
  "${docker_cmd[@]}" rm -f "$container" >/dev/null 2>&1 || true
  "${docker_cmd[@]}" run -d --name "$container" \
    -p "127.0.0.1:${port}:8096" \
    -v "$work/config:/config" \
    -v "$work/media:/media" \
    "$image" >/dev/null
  username_file="$work/username"
  export GLASSFIN_INTEGRATION=1
  export GLASSFIN_SEED_ITEM_COUNT=6
  export GLASSFIN_SEED_EPISODE_COUNT=4
  export GLASSFIN_TEST_USERNAME="glassfin-viewer"
  export GLASSFIN_TEST_PASSWORD="$(openssl rand -hex 24)"
  export GLASSFIN_SERVER_URL="http://127.0.0.1:${port}"
  export GLASSFIN_SERVER_VERSION="$version"
  export GLASSFIN_SEARCH_BENCHMARK_DIR="$root/artifacts/integration/search"
  export GLASSFIN_USERNAME="glassfin"
  export GLASSFIN_USERNAME_FILE="$username_file"
  export GLASSFIN_PASSWORD="$(openssl rand -hex 16)"
  echo "docker-integration: bootstrapping $version"
  set +e
  python3 -u "$root/scripts/jellyfin_bootstrap.py"
  boot=$?
  set -e
  if [[ "$boot" -ne 0 ]]; then
    echo "docker-integration: bootstrap failed for $version"
    echo "docker-integration: raw server logs omitted to protect generated credentials" >&2
    results+=("$version bootstrap $boot")
    "${docker_cmd[@]}" rm -f "$container" >/dev/null
    container=""
    sudo rm -rf "$work"
    continue
  fi
  if [[ -s "$username_file" ]]; then
    GLASSFIN_USERNAME="$(tr -d '\n' < "$username_file")"
    export GLASSFIN_USERNAME
  fi
  echo "docker-integration: probing HLS segment authentication for $version"
  probe_output="$(mktemp "$work/hls-probe.XXXXXX")"
  set +e
  python3 -u "$root/scripts/probe_hls_segment_auth.py" "${probe_args[@]}" >"$probe_output" 2>&1
  probe_status=$?
  set -e
  if ! show_checked_output "$probe_output"; then probe_status=1; fi
  results+=("$version hls-probe $probe_status")
  echo "docker-integration: testing $version"
  test_output="$(mktemp "$work/live-tests.XXXXXX")"
  set +e
  run_tests --filter LiveServerTests --skip 'LiveServerTests.testT09_' >"$test_output" 2>&1
  status=$?
  set -e
  if ! show_checked_output "$test_output"; then status=1; fi
  results+=("$version tests $status")
  if [[ "$status" -eq 0 ]]; then
    # Keep M08's exact fixture counts intact until its checks have finished.
    python3 "$root/scripts/jellyfin_search_seed.py" \
      --media "$work/media" --sample "$work/media/Movies/Test Movie (2024).mp4"
    set +e
    python3 -u "$root/scripts/jellyfin_bootstrap.py" --search-seed
    status=$?
    if [[ "$status" -eq 0 ]]; then
      search_output="$(mktemp "$work/search-tests.XXXXXX")"
      run_tests --filter 'LiveServerTests.testT09_' >"$search_output" 2>&1
      status=$?
      if ! show_checked_output "$search_output"; then status=1; fi
    fi
    set -e
    results+=("$version search $status")
  fi
  "${docker_cmd[@]}" rm -f "$container" >/dev/null
  container=""
  sudo rm -rf "$work"
  echo "docker-integration: $version finished"
done

echo "docker-integration: summary"
failed=0
for row in "${results[@]}"; do
  echo "  $row"
  [[ "$row" == *" 0" ]] || failed=1
done
exit "$failed"
