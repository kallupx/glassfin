#!/usr/bin/env bash
# T01-20 and T01-30 against throwaway jellyfin/jellyfin containers.
# Pins are the OCI index digests of tags 10.10.7, 10.11.11, and 12.2.
# Usage: scripts/docker-integration.sh [version ...]
set -euo pipefail
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
      swift test --filter LiveServerTests
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
    -e GLASSFIN_SERVER_VERSION \
    "$swift_image" \
    swift test --filter LiveServerTests
}

container=""
cleanup() {
  if [[ -n "$container" ]]; then
    "${docker_cmd[@]}" rm -f "$container" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

results=()
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
  export GLASSFIN_SEED_ITEM_COUNT=5
  export GLASSFIN_SERVER_URL="http://127.0.0.1:${port}"
  export GLASSFIN_SERVER_VERSION="$version"
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
    "${docker_cmd[@]}" logs "$container" 2>&1 | sed "s|${GLASSFIN_PASSWORD}|[redacted]|g" | tail -n 40 || true
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
  echo "docker-integration: testing $version"
  set +e
  run_tests
  status=$?
  set -e
  results+=("$version $status")
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
