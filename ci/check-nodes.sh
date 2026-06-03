#!/usr/bin/env bash
set -euo pipefail

url="${1:?Usage: check-nodes.sh <url> [node-id ...]}"
shift || true

if [[ "$#" -gt 0 ]]; then
  node_ids=("$@")
else
  read -r -a node_ids <<< "${REQUIRED_NODE_IDS:-20 50}"
fi

if [[ "${#node_ids[@]}" -eq 0 ]]; then
  echo "No node IDs configured for validation" >&2
  exit 1
fi

for nid in "${node_ids[@]}"; do
  response="$(curl -sf "${url}/node/${nid}?_format=json" 2>/dev/null)" || {
    echo "Node ${nid} is not available at ${url}" >&2
    exit 1
  }

  actual_nid="$(jq -re '.nid[0].value' <<< "$response")" || {
    echo "Node ${nid} response did not include .nid[0].value" >&2
    exit 1
  }

  if [[ "$actual_nid" != "$nid" ]]; then
    echo "Node ${nid} returned nid=${actual_nid}" >&2
    exit 1
  fi

  echo "Node ${nid} exists"
done
