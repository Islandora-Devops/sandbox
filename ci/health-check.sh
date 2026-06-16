#!/usr/bin/env bash
set -euo pipefail

url="${1:?Usage: health-check.sh <url> [node-id ...]}"
shift || true

timeout_seconds="${HEALTH_CHECK_TIMEOUT_SECONDS:-1500}"
interval_seconds="${HEALTH_CHECK_INTERVAL_SECONDS:-30}"
deadline=$((SECONDS + timeout_seconds))
attempt=1

echo "Waiting up to ${timeout_seconds}s for ${url} to become available..."
while true; do
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
