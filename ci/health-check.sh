#!/usr/bin/env bash
set -euo pipefail

url="${1:?Usage: health-check.sh <url> [node-id ...]}"
shift || true

timeout_seconds="${HEALTH_CHECK_TIMEOUT_SECONDS:-1200}"
interval_seconds="${HEALTH_CHECK_INTERVAL_SECONDS:-30}"
challenge_wait_seconds="${HEALTH_CHECK_CHALLENGE_WAIT_SECONDS:-12}"
deadline=$((SECONDS + timeout_seconds))
attempt=1
browser="${HEALTH_CHECK_BROWSER:-}"
browser_pid=""
profile_dir="$(mktemp -d)"

cleanup() {
  if [[ -n "$browser_pid" ]] && kill -0 "$browser_pid" >/dev/null 2>&1; then
    kill "$browser_pid" >/dev/null 2>&1 || true
    wait "$browser_pid" >/dev/null 2>&1 || true
  fi
  rm -rf "$profile_dir"
}
trap cleanup EXIT

if [[ -z "$browser" ]]; then
  for candidate in \
    google-chrome \
    google-chrome-stable \
    chromium \
    chromium-browser \
    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"; do
    if command -v "$candidate" >/dev/null 2>&1 || [[ -x "$candidate" ]]; then
      browser="$candidate"
      break
    fi
  done
fi

if [[ -z "$browser" || ! ( -x "$browser" || -n "$(command -v "$browser" 2>/dev/null)" ) ]]; then
  echo "no supported headless browser found; set HEALTH_CHECK_BROWSER or install Chrome/Chromium" >&2
  exit 1
fi

echo "Waiting up to ${timeout_seconds}s for ${url} to become available..."
while true; do
  "$browser" \
    --headless \
    --disable-gpu \
    --disable-background-networking \
    --no-default-browser-check \
    --no-first-run \
    --no-sandbox \
    --user-data-dir="$profile_dir" \
    "$url" >/dev/null 2>&1 &
  browser_pid="$!"
  sleep "$challenge_wait_seconds"
  kill "$browser_pid" >/dev/null 2>&1 || true
  wait "$browser_pid" >/dev/null 2>&1 || true
  browser_pid=""

  if ci/check-nodes.sh "$url" "$@"; then
    echo "Health check passed"
    exit 0
  fi

  if (( SECONDS >= deadline )); then
    echo "Health check failed after ${timeout_seconds}s"
    exit 1
  fi

  remaining_seconds=$((deadline - SECONDS))
  sleep_seconds=$interval_seconds
  if (( remaining_seconds < sleep_seconds )); then
    sleep_seconds=$remaining_seconds
  fi

  echo "Attempt ${attempt}: required nodes are not ready yet; retrying in ${sleep_seconds}s"
  attempt=$((attempt + 1))
  sleep "$sleep_seconds"
done
