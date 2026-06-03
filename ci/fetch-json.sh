#!/usr/bin/env bash
set -euo pipefail

url="${1:?usage: ci/fetch-json.sh <url> <output>}"
outfile="${2:?usage: ci/fetch-json.sh <url> <output>}"

mkdir -p "$(dirname "$outfile")"
curl -fsSL "$url" | jq . > "$outfile"
