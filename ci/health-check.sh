#!/usr/bin/env bash
set -euo pipefail

url="${1:?Usage: health-check.sh <url> [node-id ...]}"
shift || true

echo "Giving VM 10m to come online..."
sleep 600

echo "Waiting for ${url} to become available..."
for i in $(seq 1 30); do
  if ci/check-nodes.sh "$url" "$@"; then
    echo "Health check passed"
    exit 0
  fi
  echo "Attempt ${i}/30: required nodes are not ready yet"
  sleep 30
done

echo "Health check failed after 25 minutes"
exit 1
