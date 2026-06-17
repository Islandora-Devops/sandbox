#!/usr/bin/env bash
set -euo pipefail

url="${1:?usage: ci/screenshot.sh <url> <output>}"
outfile="${2:?usage: ci/screenshot.sh <url> <output>}"

mkdir -p "$(dirname "$outfile")"

browser=""
for candidate in google-chrome google-chrome-stable chromium chromium-browser; do
  if command -v "$candidate" >/dev/null 2>&1; then
    browser="$candidate"
    break
  fi
done

if [[ -z "$browser" ]]; then
  echo "no supported headless browser found; install Chrome or Chromium" >&2
  exit 1
fi

"$browser" \
  --headless \
  --disable-gpu \
  --no-sandbox \
  --hide-scrollbars \
  --window-size=1440,2400 \
  --screenshot="$outfile" \
  "$url"
